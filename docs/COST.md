# Actions minutes and storage

Public repositories are free and unmetered. Private repositories draw on a
monthly allowance (2,000 minutes on the Free plan), and not all minutes cost
the same:

| Runner | Billing multiplier |
| --- | --- |
| `ubuntu-latest` | 1x |
| `windows-latest` | 2x |
| `macos-latest` | 10x |

A single `os-matrix: full` C++ build therefore costs about **13x** a Linux-only
one. That is why `linux` is the default and everything else is opt-in.

## What the defaults do for you

**Linux only.** Set `os-matrix: full` per project or per call when you actually
need cross-platform coverage — typically for releases, not for every push.

**Cancel superseded runs.** Concurrency is grouped by ref with
`cancel-in-progress` on branches. Pushing three times in a minute costs one
run, not three. It is deliberately *not* enabled on `main` or tags, where you
want every run to complete.

**Skip work instead of skipping the check.** A docs-only pull request runs
`detect` and then skips the build jobs — around 30 seconds. This is done inside
the jobs rather than with `paths-ignore`, because `paths-ignore` leaves a
required status check pending forever and blocks the merge.

**Cap every job.** `timeout-minutes` defaults to 20. Without it, a hung test
can burn the platform maximum of six hours from one mistake.

**Cache the expensive parts.** ccache for C++, `~/.nuget/packages` for .NET,
keyed on the project files so a dependency change busts the cache and nothing
else does.

**`fail-fast: false`.** When three platforms are building and one breaks, you
see all three results. Cancelling the siblings just means paying again to learn
what you could have known the first time.

**Short artifact retention.** 7 days by default, because storage is metered
too and a build artifact older than a week is rarely the one you want.

## Rough costs

| Scenario | Approximate Linux minutes |
| --- | --- |
| Docs-only pull request | under 1 |
| Unity / Unreal / empty repository | 1-2 (hygiene and secret scan only) |
| Small .NET solution | 2-4 |
| Small CMake project | 2-4 |
| Either, with CodeQL | +3-6 |
| `os-matrix: full` | multiply by roughly 13 |

## Watching the meter

Your `gh` token does not carry the `user` scope, so the billing API is not
reachable from the CLI. Check **Settings → Billing → Actions** on github.com.
