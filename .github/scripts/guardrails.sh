#!/usr/bin/env bash
# Enforce the hub's own safety promises.
#
# Every check corresponds to a line in the README's "Guarantees" section. The
# point is that those are not promises anyone has to take on trust: if the hub
# ever gains the ability to write to a caller's repository, or starts loading
# an action from a mutable tag, this job goes red.
#
# This script is excluded from its own scans - it necessarily contains the
# patterns it searches for.
set -uo pipefail

SELF=".github/scripts/guardrails.sh"
FAILED=0

scan_files() {
  git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml' \
    '.github/actions/*' '.github/scripts/*' 'starters/*' 2>/dev/null |
    grep -v "^${SELF}$"
}

# Emit "file:line:text" for every executable line, skipping comments. A comment
# cannot run, and documenting a git command in prose must not trip a guardrail.
executable_lines() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -nv '^[[:space:]]*#' "$f" 2>/dev/null | sed "s|^|${f}:|"
  done < <(scan_files)
}

fail() {
  FAILED=$((FAILED + 1))
  echo "::error::$1"
}

report() {
  if [ "$1" -eq 0 ]; then echo "  ok - $2"; fi
}

# ---------------------------------------------------------------------------
echo "== 1. No repository writes =="
# The hub must never commit, tag, push or force anything into a caller's repo.
# Releases are created through the GitHub API, which needs none of these.
#
# Read-only git commands are fine and are used for changelogs, so "git tag" is
# only a violation when it is not one of the listing forms.
before=$FAILED
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "Repository write detected: $hit"
done < <(executable_lines | grep -E \
  'git[[:space:]]+push|git[[:space:]]+commit|git[[:space:]]+tag[[:space:]]+(-[af]|[^-])|--force([^-]|$)|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+push' |
  grep -vE 'git[[:space:]]+tag[[:space:]]+(-l|--list|--sort|--points-at|--merged|--contains)' || true)
report $((FAILED - before)) "no git write commands anywhere in the hub"

# ---------------------------------------------------------------------------
echo
echo "== 2. No pull_request_target =="
# pull_request_target runs untrusted fork code with a writable token and access
# to secrets. It is the most common way CI gets compromised.
before=$FAILED
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  fail "pull_request_target is banned: $hit"
done < <(executable_lines | grep 'pull_request_target' || true)
report $((FAILED - before)) "pull_request_target is not used"

# ---------------------------------------------------------------------------
echo
echo "== 3. Third-party actions are pinned to a commit SHA =="
# A mutable tag can be repointed at malicious code by anyone who compromises
# the action's repository. Local actions (./...) are our own code.
before=$FAILED
while IFS= read -r line; do
  [ -n "$line" ] || continue
  file="$(echo "$line" | cut -d: -f1)"
  ref="$(echo "$line" | sed -E 's/.*uses:[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
  case "$ref" in
  # Our own code, not third-party supply chain.
  ./* | "") continue ;;
  # References to this hub's own reusable workflows use a moving major tag on
  # purpose: that is the mechanism by which one fix reaches every project.
  # Pinning them to a SHA would defeat the entire design. Projects that want
  # zero moving parts pin a SHA themselves - see docs/SECURITY.md.
  */ci-hub/*) continue ;;
  esac
  echo "$ref" | grep -qE '@[0-9a-f]{40}$' ||
    fail "Unpinned action in ${file}: ${ref}"
done < <(executable_lines | grep -E 'uses:[[:space:]]*[^ ]' || true)
report $((FAILED - before)) "every third-party action is pinned to a full commit SHA"

# ---------------------------------------------------------------------------
echo
echo "== 4. Every workflow declares read-only default permissions =="
# Without an explicit block a workflow inherits the repository default, which
# may be read-write.
before=$FAILED
while IFS= read -r f; do
  grep -qE '^permissions:' "$f" ||
    fail "$f has no top-level permissions block; it should declare 'permissions: contents: read'."
done < <(git ls-files '.github/workflows/*.yml' 2>/dev/null)
report $((FAILED - before)) "every workflow declares its permissions"

# ---------------------------------------------------------------------------
echo
echo "== 5. contents: write appears only in the release workflow =="
# Write access is the exception that proves the rule, so its blast radius is
# checked explicitly rather than assumed.
before=$FAILED
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  case "$hit" in
  # The release workflow, and the starter template that calls it, are the one
  # sanctioned write path: creating a GitHub Release from a tag you pushed.
  .github/workflows/release.yml:* | starters/release.yml:*) continue ;;
  esac
  fail "contents: write outside release.yml: $hit"
done < <(executable_lines | grep -E 'contents:[[:space:]]*write' || true)
report $((FAILED - before)) "only release.yml can write, and only to create a Release"

# ---------------------------------------------------------------------------
echo
if [ "$FAILED" -ne 0 ]; then
  echo "Guardrails FAILED with $FAILED violation(s). The hub's safety promises are no longer true."
  exit 1
fi
echo "All guardrails passed."
