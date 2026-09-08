#!/usr/bin/env bash
# Render the detection result into the job summary.
#
# A green run must never be ambiguous: if a build was skipped, the reason it
# was skipped appears here. "Nothing ran and that is correct" and "nothing ran
# because CI is broken" have to be distinguishable at a glance.
set -uo pipefail

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

{
  echo "## Detected"
  echo
  echo "${REASONS:-No detection notes were produced.}"
} >>"$SUMMARY"
