#!/usr/bin/env bash
# Build the release notes and the SHA256SUMS file.
#
# Reads git history; writes only into $RUNNER_TEMP. It creates no tag, moves no
# ref, and makes no commit - the tag it describes was pushed by a human.
set -uo pipefail

VERSION="${1:?version required}"
TMP="${RUNNER_TEMP:-/tmp}"
NOTES="$TMP/RELEASE_NOTES.md"
FILES="$TMP/release-files"
mkdir -p "$FILES"

# --- Flatten the per-OS artifact directories -------------------------------
if [ -d "$TMP/artifacts" ]; then
  find "$TMP/artifacts" -type f -exec cp {} "$FILES/" \; 2>/dev/null || true
fi

# --- Checksums -------------------------------------------------------------
if [ -n "$(ls -A "$FILES" 2>/dev/null)" ]; then
  (cd "$FILES" && sha256sum ./* >SHA256SUMS 2>/dev/null || true)
fi

# --- Changelog since the previous tag --------------------------------------
# --sort=-v:refname orders semantically, so v1.10.0 correctly follows v1.9.0.
PREV="$(git tag --sort=-v:refname | grep -A1 -x "$VERSION" | tail -n1)"
[ "$PREV" = "$VERSION" ] && PREV=""

{
  echo "## $VERSION"
  echo
  if [ -n "$PREV" ]; then
    echo "Changes since \`$PREV\`:"
    echo
    git log --no-merges --pretty=format:'- %s (%h)' "$PREV..$VERSION" 2>/dev/null || true
    echo
  else
    echo "First release."
    echo
    git log --no-merges --pretty=format:'- %s (%h)' -n 25 "$VERSION" 2>/dev/null || true
    echo
  fi

  if [ -f "$FILES/SHA256SUMS" ]; then
    echo
    echo "### Checksums"
    echo
    echo '```'
    cat "$FILES/SHA256SUMS"
    echo '```'
  fi

  echo
  echo "---"
  echo
  echo "_Built from tag \`$VERSION\`. This release was generated without"
  echo "committing, tagging or pushing anything to the repository._"
} >"$NOTES"

echo "Release notes:"
cat "$NOTES"
