#!/usr/bin/env bash
# detect-stack: fingerprint a repository and decide which CI jobs should run.
#
# Contract: this script NEVER fails the build. Anything it cannot classify
# becomes stack "unknown", which downstream jobs treat as "run hygiene only".
# A green run must always be explainable, so every decision appends a line to
# the reasons log that ends up in the job summary.
set -uo pipefail

ROOT="${1:-.}"
OVERRIDE_FILE="${2:-.github/ci.yml}"
OUT="${GITHUB_OUTPUT:-/dev/stdout}"
ACTION_PATH="${DETECT_ACTION_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

cd "$ROOT" || exit 0

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "" >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done

REASONS=""
note() { REASONS="${REASONS}- $*"$'\n'; }

# ---------------------------------------------------------------------------
# Marker discovery
#
# Depth-bounded (<=4) and pruned. The prune list is not cosmetic: every entry
# is a directory holding marker files that are generated, vendored or
# engine-owned, and that would otherwise produce a false positive.
#   obj/ bin/ Build~/  -> generated .csproj fragments
#   Library/ Temp/     -> Unity caches
#   Intermediate/ Binaries/ DerivedDataCache/ Saved/ Content/ -> Unreal
#   _tparty/ third_party/ vendor/ node_modules/ packages/    -> vendored deps
# ---------------------------------------------------------------------------
# .ci-hub is where ci.yml checks out this hub inside the caller's workspace.
# Without pruning it, every project would "detect" the hub's own test fixtures.
PRUNE=(.git .ci-hub obj bin "Build~" Library Temp Intermediate Binaries
       DerivedDataCache Saved Content node_modules _tparty third_party vendor
       packages .godot .vs .idea dist out cmake-build-debug cmake-build-release)

prune_expr=()
for d in "${PRUNE[@]}"; do prune_expr+=(-name "$d" -o); done
unset "prune_expr[$((${#prune_expr[@]} - 1))]"

# find_marker <pattern> [maxdepth] -> matching paths, shallowest first
find_marker() {
  local pattern="$1" depth="${2:-4}"
  find . -maxdepth "$depth" \( "${prune_expr[@]}" \) -prune -o \
    -type f -name "$pattern" -print 2>/dev/null |
    sed "s|^\./||" |
    awk '{ n = gsub(/\//, "/"); print n "\t" $0 }' |
    sort -n -k1,1 |
    cut -f2-
}
has_dir() { [ -d "$1" ]; }
first() { head -n1; }

# ---------------------------------------------------------------------------
# Engine detection (runs first: engines take precedence over generic stacks)
# ---------------------------------------------------------------------------
ENGINE="none"
ENGINE_REASON=""

UPROJECT="$(find_marker "*.uproject" 3 | first)"
GODOT_PROJ="$(find_marker "project.godot" 4 | first)"
UNITY_VERSION="$(find_marker "ProjectVersion.txt" 3 | grep -i "ProjectSettings/" | first)"
META_COUNT="$(find_marker "*.meta" 5 | wc -l | tr -d " ")"

if [ -n "$UPROJECT" ]; then
  ENGINE="unreal"
  ENGINE_REASON="Unreal project detected (\`${UPROJECT}\`). Building needs a licensed engine install, so build jobs are skipped; hygiene and security still run."
elif [ -n "$UNITY_VERSION" ] || { [ "$META_COUNT" -ge 5 ] && { has_dir Packages || has_dir Assets; }; }; then
  ENGINE="unity"
  ENGINE_REASON="Unity project detected. Building needs a Unity licence seat, so build jobs are skipped; hygiene and security still run."
elif [ -n "$GODOT_PROJ" ]; then
  ENGINE="godot"
  ENGINE_REASON="Godot project detected (\`${GODOT_PROJ}\`). Godot C# projects build with the standard .NET SDK, so a .NET build is still attempted when a solution is present."
fi
[ -n "$ENGINE_REASON" ] && note "$ENGINE_REASON"

# ---------------------------------------------------------------------------
# C++
# ---------------------------------------------------------------------------
HAS_CPP=false
CPP_BUILD_SYSTEM=""
CPP_ROOT=""
CMAKE_FILE="$(find_marker "CMakeLists.txt" 3 | first)"
MAKEFILE="$(find_marker "Makefile" 2 | first)"
[ -z "$MAKEFILE" ] && MAKEFILE="$(find_marker "makefile" 2 | first)"

if [ -n "$CMAKE_FILE" ]; then
  HAS_CPP=true
  CPP_BUILD_SYSTEM="cmake"
  CPP_ROOT="$(dirname "$CMAKE_FILE")"
elif [ -n "$MAKEFILE" ]; then
  HAS_CPP=true
  CPP_BUILD_SYSTEM="make"
  CPP_ROOT="$(dirname "$MAKEFILE")"
fi

# ---------------------------------------------------------------------------
# .NET
#
# Selection order: shallowest real .sln/.slnx, else shallowest real .csproj.
# .slnx matters: it is what "dotnet new sln" emits from .NET 10 onward.
# "Real" excludes Unity-generated assemblies and stale backups. Generated
# fragments under obj/ are already pruned above.
# ---------------------------------------------------------------------------
HAS_DOTNET=false
DOTNET_PROJECT=""
dotnet_candidates() {
  {
    find_marker "*.sln" 4
    find_marker "*.slnx" 4
    find_marker "*.csproj" 4
  } |
    grep -v -E "(^|/)Assembly-CSharp" |
    grep -v -E "\.(csproj|sln|slnx)\.(old|meta|bak)"
}
DOTNET_SLN="$(dotnet_candidates | grep -E "\.slnx?$" | first)"
DOTNET_CSPROJ="$(dotnet_candidates | grep -E "\.csproj$" | first)"
if [ -n "$DOTNET_SLN" ]; then
  HAS_DOTNET=true
  DOTNET_PROJECT="$DOTNET_SLN"
elif [ -n "$DOTNET_CSPROJ" ]; then
  HAS_DOTNET=true
  DOTNET_PROJECT="$DOTNET_CSPROJ"
fi

# ---------------------------------------------------------------------------
# Analysis-only and hygiene-only stacks
# ---------------------------------------------------------------------------
HAS_PYTHON=false
HAS_NODE=false
HAS_RUST=false
HAS_GRADLE=false
[ -n "$(find_marker "pyproject.toml" 3)$(find_marker "requirements*.txt" 3)$(find_marker "setup.py" 3)" ] && HAS_PYTHON=true
[ -n "$(find_marker "package.json" 3)" ] && HAS_NODE=true
[ -n "$(find_marker "Cargo.toml" 3)" ] && HAS_RUST=true
[ -n "$(find_marker "build.gradle" 3)$(find_marker "build.gradle.kts" 3)$(find_marker "settings.gradle*" 3)" ] && HAS_GRADLE=true

# NOTE: global.json is deliberately NOT a .NET marker. Unreal projects ship one
# next to the .uproject, which would otherwise start a .NET build on an engine
# project that has no buildable solution.

# ---------------------------------------------------------------------------
# Engine precedence
# ---------------------------------------------------------------------------
case "$ENGINE" in
unreal | unity)
  if [ "$HAS_NODE" = true ]; then
    note "\`package.json\` found but treated as a ${ENGINE} package manifest, not a Node project."
    HAS_NODE=false
  fi
  if [ "$HAS_CPP" = true ]; then
    note "C++ sources found but not built: they belong to the ${ENGINE} project and cannot compile standalone."
    HAS_CPP=false
    CPP_BUILD_SYSTEM=""
    CPP_ROOT=""
  fi
  if [ "$HAS_DOTNET" = true ]; then
    note "C# sources found but not built: they belong to the ${ENGINE} project and need the editor to generate assemblies."
    HAS_DOTNET=false
    DOTNET_PROJECT=""
  fi
  ;;
esac

# ---------------------------------------------------------------------------
# Override file: the last word on everything above.
# Parsed with a strict, dependency-free reader for the documented subset
# (see docs/OVERRIDES.md). Unknown keys are ignored rather than fatal.
# ---------------------------------------------------------------------------
OS_MATRIX="linux"
OVERRIDE_APPLIED=false
if [ -f "$OVERRIDE_FILE" ]; then
  eval "$([ -n "$PY" ] && "$PY" "${ACTION_PATH}/parse_override.py" "$OVERRIDE_FILE" 2>/dev/null)" || true
  if [ -n "${OV_PARSED:-}" ]; then
    OVERRIDE_APPLIED=true
    note "Override file \`${OVERRIDE_FILE}\` applied."
    [ -n "${OV_OS_MATRIX:-}" ] && OS_MATRIX="$OV_OS_MATRIX"
    if [ "${OV_CPP_ENABLED:-}" = "false" ]; then
      HAS_CPP=false
      note "Override disabled the C++ build."
    elif [ "${OV_CPP_ENABLED:-}" = "true" ]; then
      HAS_CPP=true
    fi
    [ -n "${OV_CPP_ROOT:-}" ] && CPP_ROOT="$OV_CPP_ROOT"
    [ -n "${OV_CPP_BUILD_SYSTEM:-}" ] && CPP_BUILD_SYSTEM="$OV_CPP_BUILD_SYSTEM"
    if [ "${OV_DOTNET_ENABLED:-}" = "false" ]; then
      HAS_DOTNET=false
      note "Override disabled the .NET build."
    elif [ "${OV_DOTNET_ENABLED:-}" = "true" ]; then
      HAS_DOTNET=true
    fi
    [ -n "${OV_DOTNET_PROJECT:-}" ] && {
      DOTNET_PROJECT="$OV_DOTNET_PROJECT"
      note "Override pinned the .NET project to \`${OV_DOTNET_PROJECT}\`."
    }
  else
    note "Override file \`${OVERRIDE_FILE}\` could not be parsed and was ignored. Auto-detection was used instead."
  fi
fi
[ "$HAS_CPP" = true ] && [ -z "$CPP_BUILD_SYSTEM" ] && CPP_BUILD_SYSTEM="cmake"
[ "$HAS_CPP" = true ] && [ -z "$CPP_ROOT" ] && CPP_ROOT="."

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------
STACKS=()
[ "$HAS_CPP" = true ] && STACKS+=("cpp")
[ "$HAS_DOTNET" = true ] && STACKS+=("dotnet")
[ "$HAS_PYTHON" = true ] && STACKS+=("python")
[ "$HAS_NODE" = true ] && STACKS+=("node")
[ "$HAS_RUST" = true ] && STACKS+=("rust")
[ "$HAS_GRADLE" = true ] && STACKS+=("gradle")
[ "$ENGINE" != "none" ] && STACKS+=("$ENGINE")
if [ ${#STACKS[@]} -eq 0 ]; then
  STACKS+=("unknown")
  note "No build system recognised. Ran hygiene and security checks only - this is a pass, not a failure."
fi

[ "$HAS_CPP" = true ] && note "C++ (${CPP_BUILD_SYSTEM}) build enabled in \`${CPP_ROOT}\`."
[ "$HAS_DOTNET" = true ] && note ".NET build enabled for \`${DOTNET_PROJECT}\`."
[ "$HAS_PYTHON" = true ] && note "Python detected: static analysis only, no build step is defined for Python in v1."
[ "$HAS_RUST" = true ] && note "Rust detected: hygiene and secret scanning only, no build step is defined for Rust in v1."
[ "$HAS_GRADLE" = true ] && note "Gradle detected: hygiene and secret scanning only, no build step is defined for Gradle in v1."

# CodeQL supports a fixed language set; asking it for anything else fails the
# job, which is exactly the kind of unrelated red badge this system avoids.
CODEQL=()
[ "$HAS_CPP" = true ] && CODEQL+=("c-cpp")
[ "$HAS_DOTNET" = true ] && CODEQL+=("csharp")
[ "$HAS_PYTHON" = true ] && CODEQL+=("python")
[ "$HAS_NODE" = true ] && CODEQL+=("javascript-typescript")

json_array() {
  if [ -n "$PY" ]; then
    printf "%s\n" "$@" |
      "$PY" -c "import json,sys; print(json.dumps([l for l in sys.stdin.read().split(chr(10)) if l]))"
  else
    # No usable interpreter. Detection still has to produce valid JSON, because
    # returning an empty string here would break every downstream matrix.
    local out="" item
    for item in "$@"; do out="${out}\"${item}\","; done
    printf "[%s]\n" "${out%,}"
  fi
}

{
  echo "stacks=$(json_array "${STACKS[@]}")"
  if [ ${#CODEQL[@]} -eq 0 ]; then
    echo "codeql_languages=[]"
    echo "has_codeql=false"
  else
    echo "codeql_languages=$(json_array "${CODEQL[@]}")"
    echo "has_codeql=true"
  fi
  echo "has_cpp=$HAS_CPP"
  echo "cpp_build_system=$CPP_BUILD_SYSTEM"
  echo "cpp_root=$CPP_ROOT"
  echo "has_dotnet=$HAS_DOTNET"
  echo "dotnet_project=$DOTNET_PROJECT"
  echo "has_python=$HAS_PYTHON"
  echo "has_node=$HAS_NODE"
  echo "has_rust=$HAS_RUST"
  echo "has_gradle=$HAS_GRADLE"
  echo "engine=$ENGINE"
  echo "os_matrix=$OS_MATRIX"
  echo "override_applied=$OVERRIDE_APPLIED"
  echo "reasons<<__EOR__"
  printf "%s" "$REASONS"
  echo ""
  echo "__EOR__"
} >>"$OUT"

exit 0
