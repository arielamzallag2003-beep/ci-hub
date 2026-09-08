#!/usr/bin/env bash
# Render one report used both as the job summary and as the pull request
# comment body.
#
# The goal is that a green run explains itself. Someone reading this should be
# able to tell "nothing ran because this project has no build system" apart
# from "nothing ran because CI is broken" without opening a single log.
set -uo pipefail

OUT="${RUNNER_TEMP:-/tmp}/ci-report.md"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

icon_for() {
  case "$1" in
  success) echo "pass" ;;
  failure) echo "FAIL" ;;
  skipped) echo "skip" ;;
  cancelled) echo "cancelled" ;;
  *) echo "$1" ;;
  esac
}

{
  echo "## CI report"
  echo

  # --- What was detected ---------------------------------------------------
  stacks_pretty="$(echo "${STACKS:-[]}" | tr -d '[]"' | tr ',' ' ')"
  echo "**Stacks:** ${stacks_pretty:-none}  "
  echo "**Runners:** ${OS_MODE:-linux}  "
  if [ "${DOCS_ONLY:-false}" = "true" ]; then
    echo "**Docs-only change:** build jobs were skipped to save Actions minutes."
  fi
  echo

  # --- Job results ---------------------------------------------------------
  echo "| Job | Result |"
  echo "| --- | --- |"
  echo "${NEEDS:-{\}}" |
    jq -r 'to_entries[] | "\(.key)\t\(.value.result)"' 2>/dev/null |
    while IFS=$'\t' read -r job result; do
      echo "| $job | $(icon_for "$result") |"
    done
  echo

  # --- Why things were skipped --------------------------------------------
  if [ -n "${REASONS:-}" ]; then
    echo "### Why"
    echo
    echo "$REASONS"
    echo
  fi

  # --- The guarantee, restated where it is checkable -----------------------
  echo "---"
  echo
  echo "_No commits, tags, merges or pushes were made to this repository._"
} >"$OUT"

cat "$OUT" >>"$SUMMARY"
echo "Report written to $OUT"
