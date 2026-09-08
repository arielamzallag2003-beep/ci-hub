# CI Hub

One CI/CD system for every repository you own — whatever it's written in.

[![Guardrails](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/guardrails.yml/badge.svg)](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/guardrails.yml)
[![E2E](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/e2e.yml/badge.svg)](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/e2e.yml)
[![Self CI](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/self-ci.yml/badge.svg)](https://github.com/arielamzallag2003-beep/ci-hub/actions/workflows/self-ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

---

Instead of a hand-written pipeline in every repository, each project gets a
15-line file that calls this hub. The hub works out what the project is at run
time and runs only what makes sense.

- **Works with any project.** C++, C#, Python, Rust, Node, Gradle, Unity,
  Unreal, Godot, or an empty repository. A stack it cannot build still finishes
  green, with the reason printed — never a red badge for something that isn't
  your fault.
- **Never writes to your repository.** No commits, no tags, no merges, no
  force-pushes. Enforced by a workflow, not by good intentions.
- **Fix it once.** A bug fixed here reaches every repository pinned to `@v1` on
  its next run. No fan-out pull requests.

## The 60-second version

```bash
pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project          # dry run, shows the diff
pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project -Apply   # opens a pull request
```

Merge the pull request. That's the whole adoption. There is no per-language
configuration step.

## How it works

```mermaid
flowchart LR
    D[detect] --> H[hygiene]
    D --> S[secret scan]
    D --> R[dependency review]
    D --> Q[CodeQL]
    D --> C[C++ build]
    D --> N[.NET build]
    H & S & R & Q & C & N --> P[report]
    P --> OK([ci-ok])
```

`detect` fingerprints the repository — build systems, engines, analysis
languages — and every other job is conditional on what it found.

Everything funnels into **`ci-ok`**, and that is the only status check you ever
make required. It fails when a job *failed*; a job that was *skipped* because
your project has no C# in it keeps it green. That's what lets one identical
branch-protection rule work across every repository you own, including the ones
CI can't build.

## Quickstart

### A new project

1. Create the repository and write some code:
   ```bash
   gh repo create my-project --private --clone && cd my-project
   ```
2. Adopt the hub:
   ```bash
   pwsh /path/to/ci-hub/scripts/bootstrap-repo.ps1 -Repo my-project -Apply
   ```
   *Expected:* a printed list of files to add, then a pull request URL.
3. Merge the pull request and push. *Expected:* a CI run whose summary names
   your stack, e.g. `C++ (cmake) build enabled in '.'`.

### An existing repository

1. See where you stand — this changes nothing:
   ```bash
   pwsh ./scripts/audit-repos.ps1
   ```
   *Expected:* a table of every repository with its workflow count, branch
   protection and secret-scanning status.
2. Adopt one, reviewing the dry run first:
   ```bash
   pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project
   pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project -Apply
   ```
   Existing workflows are never touched or overwritten.
3. Once CI is green, require it:
   ```bash
   pwsh ./scripts/apply-protection.ps1 -Repo my-project -Apply
   ```
   *Expected:* `ci-ok` required, force-pushes and branch deletion blocked.

## What you get, per stack

| Your project | What runs | Tier |
| --- | --- | --- |
| CMake or Makefile C++ | build, `ctest`/`make test`, `clang-format` check | full build |
| .NET `.sln` / `.slnx` / `.csproj` | restore, build, `dotnet test`, format check | full build |
| Python | CodeQL, hygiene, secret scan | analysis |
| Node | CodeQL, hygiene, secret scan | analysis |
| Rust, Gradle/Kotlin | hygiene, secret scan | hygiene |
| Godot | .NET build if a solution exists, else hygiene | mixed |
| **Unity** | hygiene, secret scan — **build skipped, needs a licence seat** | green |
| **Unreal** | hygiene, secret scan — **build skipped, needs the engine** | green |
| **Empty / unrecognised** | hygiene, secret scan — **stated as such** | green |

The bottom three rows are the point of the design. They pass, and the summary
says exactly why nothing was built.

## The caller file

Identical in every repository, regardless of language:

```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
jobs:
  ci:
    uses: arielamzallag2003-beep/ci-hub/.github/workflows/ci.yml@v1
    permissions:
      contents: read
      security-events: write # CodeQL
      pull-requests: write # the PR comment
      actions: read
```

The `permissions` block belongs to the caller because a reusable workflow can
only *narrow* permissions, never widen them.

Copies live in [`starters/`](starters/).

## Configuration

Inputs to `ci.yml` — all optional:

| Input | Default | Effect |
| --- | --- | --- |
| `os-matrix` | `linux` | `full` adds Windows and macOS. `auto` uses Linux on PRs and escalates on main and tags. |
| `dotnet-version` | `8.0.x` | Ignored when the project has a `global.json`. |
| `cmake-build-type` | `Release` | Passed to `CMAKE_BUILD_TYPE`. |
| `run-security` | `true` | Secret scanning and dependency review. |
| `run-codeql` | `true` | CodeQL for the detected languages. |
| `artifact-retention-days` | `7` | Keeps you clear of the storage quota. |
| `timeout-minutes` | `20` | Per build job. |
| `working-directory` | `.` | For a monorepo whose project isn't at the top level. |

When detection gets it wrong, commit `.github/ci.yml` in the project:

```yaml
os-matrix: full
stacks:
  cpp:
    enabled: false # the only CMakeLists.txt here is a vendored dependency
  dotnet:
    project: plugin/MyTool.csproj # pin the right one
```

Anything you leave out stays auto-detected. Full reference:
[docs/OVERRIDES.md](docs/OVERRIDES.md).

## Guarantees

Each of these is checked by
[`guardrails.yml`](.github/workflows/guardrails.yml) on every change to the
hub. If one stops being true, the hub's own CI goes red.

| The hub will never… | Enforced by |
| --- | --- |
| commit, tag, push, or force-push to your repository | grep for `git push`/`commit`/`tag`/`--force` across all hub code |
| reformat your code | `clang-format`/`dotnet format` run in check mode; violations become an annotation and a downloadable `format.patch` |
| merge anything | no `contents: write` outside `release.yml`, verified |
| use `pull_request_target` | grep; it is the standard fork-token exfiltration vector |
| run an action from a mutable tag | every third-party action pinned to a full commit SHA |
| require a secret | `ci.yml` declares none, so fork PRs have nothing to leak |
| create a release tag | `release.yml` only *reads* the tag you pushed |

The one exception is deliberate: when **you** push a `v*.*.*` tag,
`release.yml` builds artifacts and creates a **draft** release for you to
publish. It still creates no tag and makes no commit.

## Cost control

Actions minutes are free on public repositories and metered on private ones,
where Windows costs 2× and macOS 10× a Linux minute. Defaults are chosen
accordingly:

- **Linux only** unless you ask for `full`.
- **Concurrency cancellation** on PR branches, so a force-push doesn't leave
  three stale runs burning minutes.
- **Docs-only pull requests skip the build jobs** entirely (~30 seconds).
- **`timeout-minutes` on every job**, so a hung job can't eat six hours.
- **Caching** for ccache and NuGet.
- **`fail-fast: false`**, so one run reports every broken platform instead of
  making you pay for a second.

More detail: [docs/COST.md](docs/COST.md).

## Troubleshooting

**My stack was detected wrong.**
Read the *Detected* section of the run summary — it states every decision and
why. Then commit a `.github/ci.yml` override
([reference](docs/OVERRIDES.md)) to correct it.

**CI is red and I can't tell why.**
Open the `ci-ok` job. It names the jobs that actually failed, as opposed to the
ones that were skipped.

**I want Windows and macOS builds.**
Set `os-matrix: full` — in the caller's `with:` block for always, or in the
project's `.github/ci.yml` to make it the project's own default.

**How do I skip CI for a documentation change?**
You don't need to. A pull request touching only `*.md`, `docs/`, `LICENSE` or
`.gitignore` skips the build jobs automatically and stays green.

## Versioning

Projects pin `@v1`. Releases are tagged `v1.x.y` and the `v1` tag is moved to
the newest of them, so bug fixes arrive without any change on your side.
Anything that would break existing callers goes to `v2`; `v1` keeps working
until you choose to move. To opt out of moving tags entirely, pin a commit SHA
instead — see [docs/SECURITY.md](docs/SECURITY.md).

## Contributing

Test a change before tagging:

```bash
bash tests/run-detect-tests.sh        # detection snapshots
bash .github/scripts/guardrails.sh    # the safety guarantees
```

Then push a branch: `guardrails.yml`, `self-ci.yml` and `e2e.yml` run the real
`ci.yml` against the fixtures in [`tests/fixtures/`](tests/fixtures/), including
the `empty` and `unity-like` cases that must finish green. Do not tag a release
while any of the three is red.

Architecture and design rationale: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
