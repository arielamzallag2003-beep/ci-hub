#!/usr/bin/env bash
# Gather whatever the build produced into $RUNNER_TEMP/dist.
#
# Best-effort by design: a project with nothing to ship should still get a
# release with notes and a changelog, not a failed workflow.
set -uo pipefail

VERSION="${1:-unversioned}"
CPP_DIR="${2:-.}"
DIST="${RUNNER_TEMP:-/tmp}/dist"
mkdir -p "$DIST"

produced=false

# --- .NET ------------------------------------------------------------------
if [ -d "${RUNNER_TEMP:-/tmp}/publish" ] && [ -n "$(ls -A "${RUNNER_TEMP:-/tmp}/publish" 2>/dev/null)" ]; then
  archive="$DIST/dotnet-${VERSION}-$(uname -s | tr '[:upper:]' '[:lower:]').zip"
  (cd "${RUNNER_TEMP:-/tmp}/publish" && zip -qr "$archive" .) && produced=true
fi

# --- C++ -------------------------------------------------------------------
# Executables land in different places for CMake single- and multi-config
# generators, so look in both rather than assuming one layout.
if [ -d "$CPP_DIR/build" ]; then
  found=$(find "$CPP_DIR/build" -maxdepth 3 -type f \
    \( -perm -u+x -o -name "*.exe" \) \
    ! -name "*.o" ! -name "*.a" ! -name "*.cmake" ! -name "CMakeCache.txt" \
    2>/dev/null | head -20)
  if [ -n "$found" ]; then
    mkdir -p "$DIST/bin"
    echo "$found" | while IFS= read -r f; do cp "$f" "$DIST/bin/" 2>/dev/null || true; done
    if [ -n "$(ls -A "$DIST/bin" 2>/dev/null)" ]; then
      (cd "$DIST" && zip -qr "cpp-${VERSION}-$(uname -s | tr '[:upper:]' '[:lower:]').zip" bin && rm -rf bin)
      produced=true
    fi
  fi
fi

if [ "$produced" = true ]; then
  echo "Collected:"
  ls -la "$DIST"
else
  echo "No shippable artifacts were produced. The release will contain notes only."
fi

echo "produced=$produced" >>"${GITHUB_OUTPUT:-/dev/stdout}"
