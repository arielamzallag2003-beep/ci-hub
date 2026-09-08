<#
.SYNOPSIS
    Add the CI hub's caller workflow to a repository, via a pull request.

.DESCRIPTION
    Dry run by default: it prints exactly what it would add and changes
    nothing. Pass -Apply to act.

    Even with -Apply it cannot damage a repository:
      * it works on a new branch, never on the default branch;
      * it only adds files, never edits or deletes existing ones;
      * it refuses to overwrite a workflow that is already there;
      * it opens a pull request for you to review and merge yourself.

.EXAMPLE
    pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project
    pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project -Apply
    pwsh ./scripts/bootstrap-repo.ps1 -Repo my-project -WithRelease -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$Owner,
    [switch]$WithRelease,
    [switch]$WithSecurity,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$hubRoot = Split-Path -Parent $PSScriptRoot

if (-not $Owner) {
    $Owner = (gh api user --jq '.login' 2>$null)
    if (-not $Owner) { throw "Could not determine the GitHub account. Run 'gh auth login' first." }
}
$slug = "$Owner/$Repo"

# --- What we would add -----------------------------------------------------
$files = @(
    @{ Source = Join-Path $hubRoot 'starters/ci.yml'; Target = '.github/workflows/ci.yml' }
)
if ($WithRelease) {
    $files += @{ Source = Join-Path $hubRoot 'starters/release.yml'; Target = '.github/workflows/release.yml' }
}
if ($WithSecurity) {
    $files += @{ Source = Join-Path $hubRoot 'starters/security.yml'; Target = '.github/workflows/security.yml' }
}

Write-Host "Repository: $slug" -ForegroundColor Cyan

# --- Refuse to clobber anything -------------------------------------------
$existing = @()
foreach ($f in $files) {
    $probe = $null
    try { $probe = gh api "repos/$slug/contents/$($f.Target)" 2>$null } catch { }
    if ($probe) { $existing += $f.Target }
}
if ($existing.Count -gt 0) {
    Write-Host ""
    Write-Host "These files already exist and will NOT be touched:" -ForegroundColor Yellow
    $existing | ForEach-Object { Write-Host "  $_" }
    $files = $files | Where-Object { $existing -notcontains $_.Target }
    if ($files.Count -eq 0) {
        Write-Host ""
        Write-Host "Nothing to do: this repository already has everything." -ForegroundColor Green
        exit 0
    }
}

Write-Host ""
Write-Host "Would add:" -ForegroundColor Cyan
foreach ($f in $files) { Write-Host "  + $($f.Target)" }

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN - nothing was changed." -ForegroundColor Yellow
    Write-Host "Contents that would be written:" -ForegroundColor Yellow
    foreach ($f in $files) {
        Write-Host ""
        Write-Host "--- $($f.Target) ---" -ForegroundColor DarkGray
        Get-Content $f.Source | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    Write-Host ""
    Write-Host "Re-run with -Apply to open a pull request." -ForegroundColor Yellow
    exit 0
}

# --- Apply, on a branch, as a pull request ---------------------------------
$branch = "ci/adopt-ci-hub"
$defaultBranch = gh api "repos/$slug" --jq '.default_branch'
$baseSha = gh api "repos/$slug/git/ref/heads/$defaultBranch" --jq '.object.sha'

Write-Host ""
Write-Host "Creating branch '$branch' from '$defaultBranch'..." -ForegroundColor Cyan
try {
    gh api "repos/$slug/git/refs" -f ref="refs/heads/$branch" -f sha="$baseSha" | Out-Null
}
catch {
    Write-Host "  branch already exists; reusing it" -ForegroundColor Yellow
}

foreach ($f in $files) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.Source))
    Write-Host "  adding $($f.Target)" -ForegroundColor Green
    gh api "repos/$slug/contents/$($f.Target)" -X PUT `
        -f message="ci: adopt the central CI hub" `
        -f content="$b64" `
        -f branch="$branch" | Out-Null
}

$prBody = @"
Adopts the central CI hub.

This adds a caller workflow only. The hub is read-only: it never commits,
tags, merges or pushes to this repository. Formatting problems are reported
as annotations and as a downloadable patch, never applied automatically.

What runs is decided at run time by fingerprinting this repository, so a
stack the hub cannot build still finishes green with the reason stated.

Set ``ci-ok`` as the required status check once this is merged.
"@

Write-Host ""
Write-Host "Opening a pull request..." -ForegroundColor Cyan
$pr = gh pr create --repo $slug --base $defaultBranch --head $branch `
    --title "ci: adopt the central CI hub" --body $prBody
Write-Host $pr -ForegroundColor Green
Write-Host ""
Write-Host "Review and merge it yourself. Nothing was pushed to $defaultBranch." -ForegroundColor Yellow
