#!/usr/bin/env bash
# Repository hygiene checks.
#
# Split deliberately into two classes:
#   ERRORS   things that are already broken, or that GitHub itself will reject.
#   WARNINGS things worth cleaning up that must never block a merge.
#
# Nothing here modifies the repository. Findings are reported as annotations
# and in the job summary; fixing them is the author's decision.
set -uo pipefail

ERRORS=0
WARNINGS=0
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

err() {
  ERRORS=$((ERRORS + 1))
  echo "::error::$1"
  echo "- **error** $1" >>"$SUMMARY"
}
warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "::warning::$1"
  echo "- **warning** $1" >>"$SUMMARY"
}

echo "## Hygiene" >>"$SUMMARY"
echo >>"$SUMMARY"

# Only look at tracked files. Anything ignored is by definition not committed.
mapfile -t TRACKED < <(git ls-files 2>/dev/null)
if [ "${#TRACKED[@]}" -eq 0 ]; then
  echo "No tracked files to inspect." >>"$SUMMARY"
  exit 0
fi

# --- Oversized files -------------------------------------------------------
# GitHub hard-rejects a push containing a blob over 100 MB, so a file that size
# in history is a problem the author needs to know about immediately.
for f in "${TRACKED[@]}"; do
  [ -f "$f" ] || continue
  size=$(wc -c <"$f" 2>/dev/null || echo 0)
  if [ "$size" -gt 104857600 ]; then
    err "\`$f\` is $((size / 1048576)) MB. GitHub refuses blobs over 100 MB; use Git LFS."
  elif [ "$size" -gt 52428800 ]; then
    warn "\`$f\` is $((size / 1048576)) MB. Consider Git LFS before it reaches the 100 MB limit."
  fi
done

# --- Merge conflict markers ------------------------------------------------
# A committed conflict marker means broken source, every time.
conflicts=$(git grep -lE '^(<{7}|={7}|>{7})( |$)' -- "${TRACKED[@]}" 2>/dev/null | head -20)
if [ -n "$conflicts" ]; then
  while IFS= read -r f; do
    err "\`$f\` contains unresolved merge conflict markers."
  done <<<"$conflicts"
fi

# --- CRLF in files that must be LF -----------------------------------------
# A shell script checked out with CRLF fails on Linux with "\r: command not
# found" - an unrelated red badge that is very hard to read from the log.
for f in "${TRACKED[@]}"; do
  case "$f" in
  *.sh | *.bash) ;;
  *) continue ;;
  esac
  [ -f "$f" ] || continue
  if head -c 4096 "$f" 2>/dev/null | grep -q $'\r'; then
    err "\`$f\` has CRLF line endings and will not run on Linux runners. Add \`*.sh text eol=lf\` to .gitattributes."
  fi
done

# --- Committed build output ------------------------------------------------
artifacts=$(printf '%s\n' "${TRACKED[@]}" |
  grep -E '(^|/)(bin|obj|node_modules)/|\.(exe|dll|pdb|o|a|lib|so|dylib)$|\.dSYM/' |
  grep -vE '^tests?/fixtures/' | head -10)
if [ -n "$artifacts" ]; then
  count=$(printf '%s\n' "${TRACKED[@]}" |
    grep -cE '(^|/)(bin|obj|node_modules)/|\.(exe|dll|pdb|o|a|lib|so|dylib)$|\.dSYM/')
  warn "$count build artifacts are committed. They bloat clones and cause noisy diffs. Examples: $(echo "$artifacts" | head -3 | tr '\n' ' ')"
fi

# --- Housekeeping files ----------------------------------------------------
[ -f .gitignore ] || warn "No .gitignore. Build output will be committed by accident."
[ -f .gitattributes ] || warn "No .gitattributes. Line endings will differ between Windows and Linux checkouts."
# Test each candidate separately: "ls A B C" reports failure when ANY argument
# is missing, so it answers "do all of these exist", not "does any".
any_exists() {
  local f
  for f in "$@"; do [ -e "$f" ] && return 0; done
  return 1
}
any_exists LICENSE LICENSE.md LICENSE.txt COPYING ||
  warn "No LICENSE file. Without one the code is All Rights Reserved by default."
any_exists README README.md README.rst README.txt ||
  warn "No README."

# --- Result ----------------------------------------------------------------
{
  echo
  echo "${#TRACKED[@]} tracked files checked - $ERRORS errors, $WARNINGS warnings."
} >>"$SUMMARY"

if [ "$ERRORS" -gt 0 ]; then
  echo "Hygiene found $ERRORS error(s)."
  exit 1
fi
echo "Hygiene passed with $WARNINGS warning(s)."
exit 0
