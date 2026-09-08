## What changed

<!-- One or two sentences. -->

## Why

<!-- The problem this solves. -->

## Checks

Every change to the hub affects every project that depends on it.

- [ ] `bash tests/run-detect-tests.sh` passes
- [ ] `bash .github/scripts/guardrails.sh` passes
- [ ] `e2e.yml` is green, including the `empty` and `unity-like` fixtures
- [ ] If detection changed: a snapshot assertion was added for the new case
- [ ] If this is a breaking change for callers: it targets `v2`, not `v1`
