#!/usr/bin/env bash
# Snapshot tests for detect-stack.
#
# These encode the specific misclassifications that motivated the detector's
# design. If one of them regresses, a real project silently gets the wrong CI:
# an engine project starts a build it cannot finish, or a buildable project
# stops being built at all. Both are worse than a loud failure here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="$HERE/../.github/actions/detect-stack"
PASS=0
FAIL=0

# expect <fixture> <field> <value>
expect() {
  local fixture="$1" field="$2" want="$3" got
  got="$(cd "$HERE/fixtures/$fixture" &&
    DETECT_ACTION_PATH="$ACTION" bash "$ACTION/detect.sh" . .github/ci.yml 2>/dev/null |
    grep -E "^${field}=" | head -1 | cut -d= -f2-)"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %-12s %-18s = %s\n' "$fixture" "$field" "$got"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %-12s %-18s = %s   (expected %s)\n' "$fixture" "$field" "$got" "$want"
  fi
}

echo "detect-stack snapshot tests"
echo

echo "cpp-cmake: a CMake project builds with CMake"
expect cpp-cmake stacks '["cpp"]'
expect cpp-cmake cpp_build_system cmake
expect cpp-cmake codeql_languages '["c-cpp"]'

echo "cpp-make: a Makefile-only project is still a buildable C++ project,"
echo "          and its vendored _tparty/CMakeLists.txt must not hijack the build"
expect cpp-make stacks '["cpp"]'
expect cpp-make cpp_build_system make

echo "dotnet: the solution is selected, not an individual project"
expect dotnet stacks '["dotnet"]'
expect dotnet dotnet_project Fixture.sln
expect dotnet has_cpp false

echo "unity-like: generated .csproj under obj/ and Build~/ must not look buildable,"
echo "            and a Unity package.json must not register as a Node project"
expect unity-like stacks '["unity"]'
expect unity-like engine unity
expect unity-like has_dotnet false
expect unity-like has_node false
expect unity-like codeql_languages '[]'

echo "empty: an unrecognised repository is a pass, not a failure"
expect empty stacks '["unknown"]'
expect empty engine none
expect empty has_codeql false

echo
if [ "$FAIL" -eq 0 ]; then
  echo "all $PASS assertions passed"
  exit 0
fi
echo "$FAIL of $((PASS + FAIL)) assertions failed"
exit 1
