# Project overrides — `.github/ci.yml`

Auto-detection is a heuristic. It is right for most repositories and wrong for
some, and when it is wrong you need a way to say so that does not involve
editing the hub. That is this file.

Commit it at `.github/ci.yml` **in your project** (not in the hub). Every key is
optional; anything you omit stays auto-detected. Unknown keys are ignored, so a
newer override file never breaks an older pinned hub version.

## Full schema

```yaml
os-matrix: linux        # linux | full | auto

stacks:
  cpp:
    enabled: false      # true | false
    root: engine        # directory holding CMakeLists.txt or the Makefile
    build-system: cmake # cmake | make
  dotnet:
    enabled: true
    project: plugin/MyTool.csproj   # .sln, .slnx or .csproj
```

That is the whole schema. It is parsed by a small dependency-free reader rather
than PyYAML, because relying on a package that may or may not be on a runner
image is exactly the kind of unrelated CI failure this hub exists to prevent.

Consequences of that choice, all of which the schema above stays inside:

- Two levels of nesting, two-space indent.
- `key: value` pairs only — no lists, no flow mappings (`{a: 1}`), no anchors.
- Comments and blank lines are fine.

If the file cannot be parsed it is ignored, auto-detection is used, and the run
summary says so. A malformed override never fails your build.

## When you actually need this

**A vendored dependency ships its own build files.** The detector prunes the
common vendor directory names (`vendor/`, `third_party/`, `_tparty/`,
`node_modules/`, `packages/`), but not every project uses one of those names.

```yaml
stacks:
  cpp:
    enabled: false
```

**Several solutions, and the shallowest is not the one you want.** Detection
picks the shallowest real `.sln`/`.slnx`, then the shallowest `.csproj`.

```yaml
stacks:
  dotnet:
    project: src/Real/Real.csproj
```

**A monorepo whose project is not at the top level.** Prefer the caller's
`working-directory` input for this, which scopes the whole run:

```yaml
jobs:
  ci:
    uses: arielamzallag2003-beep/ci-hub/.github/workflows/ci.yml@v1
    with:
      working-directory: services/api
```

**You want Windows and macOS builds for this project always.**

```yaml
os-matrix: full
```

Remember the cost: a Windows minute bills at 2x and a macOS minute at 10x on
private repositories.

## Checking your override took effect

The run summary's *Detected* section names the override explicitly:

```
- Override file `.github/ci.yml` applied.
- Override disabled the C++ build.
- Override pinned the .NET project to `plugin/MyTool.csproj`.
```

If those lines are missing, the file was not found or not parsed.
