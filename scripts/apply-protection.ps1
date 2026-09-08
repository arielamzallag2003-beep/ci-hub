<#
.SYNOPSIS
    Apply the standard branch protection ruleset to a repository.

.DESCRIPTION
    Dry run by default: prints the exact ruleset it would apply and changes
    nothing. Pass -Apply to act.

    The ruleset is deliberately about preventing loss, not about ceremony:
      * require a pull request before merging;
      * require the 'ci-ok' status check to pass;
      * block force pushes to the default branch;
      * block deletion of the default branch.

    'ci-ok' is the hub's single gate job, so this exact ruleset works for every
    repository regardless of language - including ones the hub cannot build,
    where ci-ok still reports success.

.EXAMPLE
    pwsh ./scripts/apply-protection.ps1 -Repo my-project
    pwsh ./scripts/apply-protection.ps1 -Repo my-project -Apply
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$Owner,
    [string]$Branch,
    [switch]$RequireReview,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

if (-not $Owner) {
    $Owner = (gh api user --jq '.login' 2>$null)
    if (-not $Owner) { throw "Could not determine the GitHub account. Run 'gh auth login' first." }
}
$slug = "$Owner/$Repo"
if (-not $Branch) { $Branch = gh api "repos/$slug" --jq '.default_branch' }

# required_approving_review_count of 0 is correct for a solo account: it still
# forces changes through a pull request, without you having to approve your
# own work to merge it.
$reviewCount = if ($RequireReview) { 1 } else { 0 }

$protection = @{
    required_status_checks        = @{
        strict   = $false
        contexts = @('ci-ok')
    }
    enforce_admins                = $false
    required_pull_request_reviews = @{
        required_approving_review_count = $reviewCount
        dismiss_stale_reviews           = $false
    }
    restrictions                  = $null
    allow_force_pushes            = $false
    allow_deletions               = $false
    required_conversation_resolution = $true
}

Write-Host "Repository: $slug" -ForegroundColor Cyan
Write-Host "Branch:     $Branch" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ruleset to apply:" -ForegroundColor Cyan
Write-Host "  require a pull request before merging     yes ($reviewCount approval(s))"
Write-Host "  required status check                     ci-ok"
Write-Host "  force pushes                              blocked"
Write-Host "  branch deletion                           blocked"
Write-Host "  conversation resolution                   required"

$current = $null
try { $current = gh api "repos/$slug/branches/$Branch/protection" 2>$null | ConvertFrom-Json } catch { }
Write-Host ""
if ($current) {
    Write-Host "This branch is ALREADY protected. Applying would replace the existing rules." -ForegroundColor Yellow
}
else {
    Write-Host "This branch is currently unprotected." -ForegroundColor Yellow
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "DRY RUN - nothing was changed. Re-run with -Apply to apply." -ForegroundColor Yellow
    exit 0
}

$json = $protection | ConvertTo-Json -Depth 10
$tmp = New-TemporaryFile
Set-Content -Path $tmp -Value $json -Encoding utf8

Write-Host ""
Write-Host "Applying..." -ForegroundColor Cyan
gh api "repos/$slug/branches/$Branch/protection" -X PUT --input $tmp | Out-Null
Remove-Item $tmp -Force

Write-Host "Done. '$Branch' now requires ci-ok and rejects force pushes and deletion." -ForegroundColor Green
Write-Host "Your existing commits and history were not touched." -ForegroundColor Green
