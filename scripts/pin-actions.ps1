<#
.SYNOPSIS
    Report, and optionally update, the commit SHAs that third-party actions are
    pinned to.

.DESCRIPTION
    Pinning to a mutable tag such as @v4 means whoever controls that action can
    change what runs in your CI at any time. The hub pins everything to a full
    commit SHA, and guardrails.yml fails if that ever stops being true.

    This script resolves the tag written in the trailing comment (# v4) back to
    a SHA and tells you when a pin has drifted behind a newer release.

    Read-only by default. -Apply rewrites the pins in place, which you then
    review as a normal diff before committing.

.EXAMPLE
    pwsh ./scripts/pin-actions.ps1
    pwsh ./scripts/pin-actions.ps1 -Apply
#>
[CmdletBinding()]
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$hubRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Sha {
    param([string]$Repo, [string]$Tag)
    try {
        $ref = gh api "repos/$Repo/git/ref/tags/$Tag" 2>$null | ConvertFrom-Json
        if (-not $ref) { return $null }
        # An annotated tag points at a tag object, which in turn points at the
        # commit. Dereference it, or the pin would be the tag object's SHA.
        if ($ref.object.type -eq 'tag') {
            $tagObj = gh api "repos/$Repo/git/tags/$($ref.object.sha)" 2>$null | ConvertFrom-Json
            return $tagObj.object.sha
        }
        return $ref.object.sha
    }
    catch { return $null }
}

$targets = Get-ChildItem -Path $hubRoot -Recurse -Include *.yml, *.yaml |
    Where-Object { $_.FullName -match '\.github|starters' }

$pattern = 'uses:\s*([A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)@([0-9a-f]{40}|[^\s#]+)\s*(#\s*(\S+))?'
$changed = 0
$drift = 0

foreach ($file in $targets) {
    $text = Get-Content -Raw $file.FullName
    $updated = $text

    foreach ($m in [regex]::Matches($text, $pattern)) {
        $ref = $m.Groups[1].Value
        $pin = $m.Groups[2].Value
        $tag = $m.Groups[4].Value

        # An action may live in a subdirectory (github/codeql-action/init), but
        # the API only knows about the repository, so keep the first two path
        # segments.
        $parts = $ref.Split('/')
        $repo = "$($parts[0])/$($parts[1])"

        # References to this hub's own reusable workflows use a moving major
        # tag on purpose - that is how a fix reaches every project. They are
        # not third-party supply chain and must not be rewritten to a SHA.
        if ($ref -like '*/ci-hub/*') { continue }

        if (-not $tag) {
            Write-Host "  ? $ref@$pin has no version comment; cannot verify" -ForegroundColor Yellow
            continue
        }

        $sha = Resolve-Sha -Repo $repo -Tag $tag
        if (-not $sha) {
            Write-Host "  ? $repo tag '$tag' could not be resolved" -ForegroundColor Yellow
            continue
        }

        if ($pin -eq $sha) {
            Write-Host "  ok $ref@$tag" -ForegroundColor DarkGray
        }
        else {
            $drift++
            Write-Host "  DRIFT $ref@$tag" -ForegroundColor Yellow
            Write-Host "        pinned:  $pin"
            Write-Host "        actual:  $sha"
            $updated = $updated.Replace("$ref@$pin", "$ref@$sha")
        }
    }

    if ($Apply -and $updated -ne $text) {
        Set-Content -Path $file.FullName -Value $updated -NoNewline -Encoding utf8
        $changed++
        Write-Host "  updated $($file.Name)" -ForegroundColor Green
    }
}

Write-Host ""
if ($drift -eq 0) {
    Write-Host "All action pins match their version comments." -ForegroundColor Green
}
elseif ($Apply) {
    Write-Host "$drift pin(s) updated across $changed file(s). Review the diff before committing." -ForegroundColor Cyan
}
else {
    Write-Host "$drift pin(s) differ from their version comment. Re-run with -Apply to update." -ForegroundColor Yellow
}

exit 0
