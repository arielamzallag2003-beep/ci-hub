# Security model

## Threat model

The hub runs on other people's code (fork pull requests) and pulls in other
people's code (third-party actions). Both are treated as untrusted.

| Threat | Mitigation |
| --- | --- |
| A fork pull request steals write access or secrets | `ci.yml` requires no secrets and never uses `pull_request_target`; forks get a read-only token |
| A compromised action runs in your CI | every third-party action is pinned to a full commit SHA, verified by `guardrails.yml` |
| A secret is committed | gitleaks over the working tree on every push and pull request, plus a full-history scan weekly |
| A vulnerable dependency is introduced | `dependency-review-action` blocks pull requests adding high-severity CVEs |
| A vulnerability in your own code | CodeQL for every detected supported language |
| CI itself damages the repository | no write permission anywhere except `release.yml`, grep-enforced |

## Pinning policy

Third-party actions are pinned to a 40-character commit SHA with the version in
a trailing comment:

```yaml
uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5
```

A tag like `@v5` is mutable — whoever controls the action can repoint it at any
time. `scripts/pin-actions.ps1` re-resolves each comment to a SHA and reports
drift; `guardrails.yml` fails the build if any reference is unpinned.

gitleaks is the one tool downloaded as a binary rather than used as an action.
It is pinned by version *and* verified against a SHA256 recorded in
`.github/scripts/gitleaks.sh`, which is a stronger guarantee than an action
tag: the run aborts if the bytes do not match. The reason for not using
`gitleaks/gitleaks-action` is behavioural rather than security - it derives a
commit range from the push event, and on a repository's first push that range
is invalid, so the job fails having scanned nothing.

## Pinning the hub itself

Projects pin `@v1`, a tag this hub moves on each `v1.x.y` release. That is what
makes "fix once, applies everywhere" work, and it is a deliberate trade: you
trust this hub the way you trust your own code.

For maximum strictness, pin a commit instead:

```yaml
uses: arielamzallag2003-beep/ci-hub/.github/workflows/ci.yml@<40-char-sha>
```

You then upgrade explicitly, and nothing changes underneath you.

## Permissions

Every workflow declares `permissions: contents: read` at the top level.
Elevation is per job and minimal:

| Permission | Where | Why |
| --- | --- | --- |
| `security-events: write` | `codeql`, `scorecard` | upload SARIF to the Security tab |
| `pull-requests: write` | `report` | the single updating PR comment |
| `contents: write` | `release.yml` publish job only | create a Release from a tag you pushed |

`guardrails.yml` fails if `contents: write` appears anywhere else.

## Reporting a problem

Open a private security advisory on the repository. Do not open a public issue
for anything exploitable.
