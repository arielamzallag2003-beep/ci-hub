#!/usr/bin/env bash
# Secret scanning with gitleaks, run directly rather than through the action.
#
# Why not gitleaks/gitleaks-action: it derives a commit range from the push
# event. On the FIRST push to a new repository the event's "before" SHA is all
# zeros, its `git log` call fails with "stderr is not empty", it scans nothing,
# and the job exits 1. Every project adopting this hub would therefore go red
# on its first push for a reason that has nothing to do with its code - the
# precise failure mode this hub exists to eliminate.
#
# Running the binary is also stricter about supply chain: the release is pinned
# by version AND verified against a SHA256 recorded here, which is a stronger
# guarantee than trusting a mutable action tag.
set -euo pipefail

MODE="${1:-dir}" # dir = working tree (fast, per push) | git = full history
VERSION="8.24.3"
SHA256="9991e0b2903da4c8f6122b5c3186448b927a5da4deef1fe45271c3793f4ee29c"
ARCHIVE="gitleaks_${VERSION}_linux_x64.tar.gz"
URL="https://github.com/gitleaks/gitleaks/releases/download/v${VERSION}/${ARCHIVE}"

TOOLS="${RUNNER_TEMP:-/tmp}/gitleaks"
mkdir -p "$TOOLS"

echo "Downloading gitleaks ${VERSION}..."
curl -fsSL -o "$TOOLS/$ARCHIVE" "$URL"

echo "Verifying checksum..."
echo "${SHA256}  ${TOOLS}/${ARCHIVE}" | sha256sum -c - || {
  echo "::error::gitleaks checksum mismatch. Refusing to run a binary that is not the pinned release."
  exit 1
}

tar -xzf "$TOOLS/$ARCHIVE" -C "$TOOLS" gitleaks
chmod +x "$TOOLS/gitleaks"

REPORT="${RUNNER_TEMP:-/tmp}/gitleaks-report.json"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

echo "Scanning (mode: ${MODE})..."
set +e
"$TOOLS/gitleaks" "$MODE" . \
  --redact \
  --no-banner \
  --report-format json \
  --report-path "$REPORT" \
  --exit-code 2
status=$?
set -e

# 0 = clean, 2 = leaks found (we chose that code), anything else = tool failure.
case "$status" in
0)
  echo "## Secret scan" >>"$SUMMARY"
  echo >>"$SUMMARY"
  echo "No secrets found (${MODE} scan, gitleaks ${VERSION})." >>"$SUMMARY"
  echo "Clean."
  ;;
2)
  count="$(python3 -c "import json;print(len(json.load(open('$REPORT'))))" 2>/dev/null || echo "?")"
  {
    echo "## Secret scan"
    echo
    echo "**${count} potential secret(s) found.** Values are redacted below; treat"
    echo "every one as compromised and rotate it, then remove it from history."
    echo
    echo '```'
    python3 -c "
import json
for f in json.load(open('$REPORT'))[:20]:
    print(f\"{f.get('File','?')}:{f.get('StartLine','?')}  {f.get('RuleID','?')}\")
" 2>/dev/null || cat "$REPORT"
    echo '```'
  } >>"$SUMMARY"
  echo "::error::gitleaks found ${count} potential secret(s). See the job summary."
  exit 1
  ;;
*)
  echo "::error::gitleaks failed to run (exit ${status}). This is a tool failure, not a leak."
  exit 1
  ;;
esac
