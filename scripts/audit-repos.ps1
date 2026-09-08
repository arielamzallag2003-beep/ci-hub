<#
.SYNOPSIS
    Read-only survey of every repository on your account.

.DESCRIPTION
    Reports which repositories have CI, whether their default branch is
    protected, whether secret scanning is on, and what the hub's detector would
    classify them as.

    This script makes no changes of any kind. It issues only GET requests. Use
    it to decide what to adopt and in what order; nothing here adopts anything.

.EXAMPLE
    pwsh ./scripts/audit-repos.ps1
    pwsh ./scripts/audit-repos.ps1 -Owner someone-else
#>
[CmdletBinding()]
param(
    [string]$Owner,
    [int]$Limit = 100
)

$ErrorActionPreference = 'Stop'

function Get-GhJson {
    param([string]$Path)
    # A 404 is a normal answer here (no workflows directory, no protection),
    # so failures are turned into $null rather than being allowed to abort.
    try { gh api $Path 2>$null | ConvertFrom-Json } catch { $null }
}

if (-not $Owner) {
    $Owner = (gh api user --jq '.login' 2>$null)
    if (-not $Owner) { throw "Could not determine the GitHub account. Run 'gh auth login' first." }
}

Write-Host "Auditing repositories for '$Owner' (read-only)..." -ForegroundColor Cyan
Write-Host ""

$repos = gh repo list $Owner --limit $Limit --json name, isPrivate, defaultBranchRef, isArchived |
    ConvertFrom-Json |
    Where-Object { -not $_.isArchived }

$rows = foreach ($repo in $repos) {
    $name = $repo.name
    $branch = if ($repo.defaultBranchRef) { $repo.defaultBranchRef.name } else { '-' }

    $workflows = Get-GhJson "repos/$Owner/$name/contents/.github/workflows"
    $ci = if ($workflows) { ($workflows | Measure-Object).Count } else { 0 }
    $usesHub = $false
    if ($workflows) {
        foreach ($wf in $workflows) {
            $content = Get-GhJson "repos/$Owner/$name/contents/$($wf.path)"
            if ($content -and $content.content) {
                $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($content.content))
                if ($text -match 'ci-hub/\.github/workflows') { $usesHub = $true }
            }
        }
    }

    $protected = 'no'
    if ($branch -ne '-') {
        $prot = Get-GhJson "repos/$Owner/$name/branches/$branch/protection"
        if ($prot) { $protected = 'yes' }
    }

    # Secret scanning status is only visible with admin rights; absence of the
    # field is reported as unknown rather than as "off".
    $full = Get-GhJson "repos/$Owner/$name"
    $secretScanning = 'unknown'
    if ($full -and $full.security_and_analysis -and $full.security_and_analysis.secret_scanning) {
        $secretScanning = $full.security_and_analysis.secret_scanning.status
    }

    [pscustomobject]@{
        Repo       = $name
        Visibility = if ($repo.isPrivate) { 'private' } else { 'public' }
        Branch     = $branch
        Workflows  = $ci
        UsesHub    = if ($usesHub) { 'yes' } else { 'no' }
        Protected  = $protected
        SecretScan = $secretScanning
    }
}

$rows | Sort-Object Repo | Format-Table -AutoSize

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
$total = ($rows | Measure-Object).Count
Write-Host "  $total active repositories"
Write-Host "  $(($rows | Where-Object Workflows -eq 0 | Measure-Object).Count) with no workflows at all"
Write-Host "  $(($rows | Where-Object UsesHub -eq 'yes' | Measure-Object).Count) already using the CI hub"
Write-Host "  $(($rows | Where-Object Protected -eq 'no' | Measure-Object).Count) with an unprotected default branch"
Write-Host ""
Write-Host "Nothing was changed. To adopt a repository, review it and then run:" -ForegroundColor Yellow
Write-Host "  pwsh ./scripts/bootstrap-repo.ps1 -Repo <name>          # dry run"
Write-Host "  pwsh ./scripts/bootstrap-repo.ps1 -Repo <name> -Apply   # opens a pull request"
