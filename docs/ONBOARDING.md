# Day-to-day: creating and adopting projects

The defining property of this system: **the caller file is byte-for-byte
identical regardless of technology.** You never write language-specific CI.

## New project, any stack

```bash
gh repo create raymarcher --private --clone && cd raymarcher
# ...write code...
pwsh /path/to/ci-hub/scripts/bootstrap-repo.ps1 -Repo raymarcher -Apply
```

Two commands. Merge the pull request it opens. Whatever you wrote — CMake, a
`.sln`, `pyproject.toml`, `Cargo.toml`, nothing at all — CI now does the right
thing for it.

## Worked examples

### C++

```bash
gh repo create raymarcher --private --clone && cd raymarcher
# CMakeLists.txt + src/main.cpp
pwsh .../bootstrap-repo.ps1 -Repo raymarcher -Apply
```

First run: `detect: cpp (cmake)` → configure → build → `ctest` → clang-format
check (only if you have a `.clang-format`; without one the check is skipped
rather than inventing a style for you).

A Makefile project is the same command and the same caller file; `detect` picks
the make path and runs `make`, then `make test` if that target exists.

### .NET

```bash
gh repo create inventory-tool --public --clone && cd inventory-tool
dotnet new sln && dotnet new classlib -o src/Core && dotnet new xunit -o tests/Core.Tests
dotnet sln add src/Core tests/Core.Tests
pwsh .../bootstrap-repo.ps1 -Repo inventory-tool -Apply
```

Restore → build → `dotnet test` (with results uploaded as an artifact) →
`dotnet format --verify-no-changes`.

### Unity or Unreal

```bash
gh repo create my-unity-game --private --clone && cd my-unity-game
pwsh .../bootstrap-repo.ps1 -Repo my-unity-game -Apply
```

**The same caller file.** CI finishes green and the summary reads:

> Unity project detected. Building needs a Unity licence seat, so build jobs
> are skipped; hygiene and security still run.

You still get secret scanning and large-file protection on a project CI
fundamentally cannot build. No red badge, no disabled workflow, no special
case in your repository.

### When detection is wrong

Commit `.github/ci.yml` in the project:

```yaml
stacks:
  cpp:
    enabled: false                # vendored only
  dotnet:
    project: plugin/Tool.csproj   # pin the real one
os-matrix: full
```

Everything you don't mention stays auto-detected. See
[OVERRIDES.md](OVERRIDES.md).

## Adopting repositories you already have

```bash
pwsh ./scripts/audit-repos.ps1
```

Read-only. Prints workflow count, branch protection and secret-scanning status
for every repository, so you can decide what to adopt and in what order.

Then one at a time, dry run first:

```bash
pwsh ./scripts/bootstrap-repo.ps1 -Repo <name>
pwsh ./scripts/bootstrap-repo.ps1 -Repo <name> -Apply
```

Existing workflows are detected and left alone — the script refuses to
overwrite a file that is already there. Nothing is bulk-pushed; each adoption
is a pull request you review.

Once CI is green:

```bash
pwsh ./scripts/apply-protection.ps1 -Repo <name> -Apply
```

## Shipping a release

Add `starters/release.yml`, then:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

CI builds artifacts, writes a changelog from the commits since the previous
tag, computes `SHA256SUMS`, and creates a **draft** release. You click Publish.
CI created no tag — you did.

## Why this pays off

Six months from now you find the .NET cache key is wrong and every build
re-downloads NuGet. Fix it once here, tag `v1.4.2`, move `v1`. Every repository
pinned to `@v1` picks it up on its next run. No pull requests, no fan-out.

That is the whole reason for a hub instead of copied files.
