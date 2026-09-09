# Architecture and rationale

## Why a hub, not copied files

The alternative is a template repository whose `.github/` folder you copy into
each project. It is simpler to start and worse to live with: fixing one bug
means opening one pull request per repository, and the repositories you touch
least — the ones most likely to have the bug — get fixed last, if ever.

With a hub, a fix is one tag move. The cost is a cross-repository dependency,
which is managed by pinning: projects use `@v1`, breaking changes go to `@v2`,
and anyone wanting zero moving parts can pin a commit SHA.

## Why `ci-ok`

GitHub branch protection requires named status checks. Naming the real jobs
would mean a different rule per repository — `cpp` here, `dotnet` there — and
a repository with neither could never satisfy its own rule.

So every job funnels into one terminal gate:

```yaml
ci-ok:
  needs: [detect, hygiene, secrets-scan, deps-review, codeql, cpp, dotnet, report]
  if: always()
```

It fails only on `result == 'failure'`. `skipped` is the normal outcome for a
language the project does not contain and keeps it green. One rule, every
repository, including the ones CI cannot build.

## Why detection is a set, not a language

A repository is not "a C# project". `snake-godot` is a .NET solution *and* a
Godot project *and* contains Unity-generated assemblies. Detection therefore
returns a set of stacks, and jobs are individually conditional.

Precedence exists only where stacks are mutually exclusive in practice: an
Unreal or Unity repository's C++ and C# cannot compile without the engine, so
the engine marker suppresses those build jobs and records why.

### The rules were written against real repositories

Each of these exists because a naive detector got a real project wrong:

| Rule | The repository that forced it |
| --- | --- |
| `global.json` is not a .NET marker | an Unreal project ships one beside the `.uproject`; the .NET job would fire and fail |
| prune `obj/`, `bin/`, `Build~/` | a Unity package whose only `.csproj` paths are generated files |
| ignore `Assembly-CSharp*.csproj` | Unity generates it; it is not a buildable project |
| prefer the shallowest real `.sln` | a repository with a genuine root solution *and* generated ones nested below |
| Makefile counts as C++ | a Makefile-only project would otherwise get no build at all |
| Unity `package.json` is not Node | Unity package manifests share npm's filename |
| `.slnx` is a solution | `dotnet new sln` emits `.slnx` from .NET 10 onward |

These are locked in as snapshot assertions in `tests/run-detect-tests.sh`. A
regression means a real project silently gets the wrong CI, which is worse than
a loud failure.

## Why the hub checks itself out

A reusable workflow runs in the *caller's* context, so `uses: ./.github/...`
inside `ci.yml` would resolve against the caller's repository, not the hub. The
usual workaround is fully-qualified `owner/repo/path@ref` references, which
have to be rewritten at every release.

Instead `ci.yml` checks the hub out beside the caller's code:

```yaml
- uses: actions/checkout@<sha>
  with:
    repository: arielamzallag2003-beep/ci-hub
    ref: ${{ github.job_workflow_sha }}
    path: .ci-hub
```

`job_workflow_sha` is the commit of the reusable workflow file itself, so the
scripts always match the version the project pinned — automatically, with no
rewriting. Actions are then plain local paths (`./.ci-hub/.github/actions/...`).

The cost is one extra checkout per job, and one subtlety: `.ci-hub` sits inside
the workspace, so `detect-stack` prunes it. Without that, every project would
detect the hub's own test fixtures.

Renaming the hub, or forking it, means repointing every self-reference — and
there are more of them than just `HUB_REPO`. The complete list is in the
README's [Using this in your own
account](../README.md#using-this-in-your-own-account) section. Missing
`HUB_REPO` in particular is silent: a fork's projects keep checking out and
running the *original* hub's code.

## Why formatting is never applied

A bot that reformats your code is a bot that writes to your repository, and
once it can do that the guarantee is gone. So formatters run in check mode, and
the diff they *would* have made is uploaded as `format.patch`:

```bash
git apply format.patch
```

You stay in control, and the guarantee stays a single enforceable rule rather
than a list of exceptions.

## Why zero secrets

`ci.yml` declares no secrets at all. That is not an accident of scope — it is
what makes fork pull requests safe: they run with a read-only token and there
is nothing to exfiltrate. It is also why `pull_request_target`, the usual way
that safety gets thrown away, is banned and grep-enforced.
