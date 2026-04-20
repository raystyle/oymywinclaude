#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Playwright skills from Claude Code
.DESCRIPTION
    Removes the Playwright CLI skill directory from the current project.
    Idempotent - safe to run multiple times.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

if (-not $Force) {
    $answer = Read-Host "Uninstall Playwright skills from Claude Code? (yes/no)"
    if ($answer -ne 'yes') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# ---- 1. Remove skills directory ----
$skillsDir = Join-Path $PWD ".claude\skills\playwright-cli"

if (-not (Test-Path $skillsDir)) {
    Write-Host "[INFO] Playwright skills not found, nothing to uninstall" -ForegroundColor Cyan
    return
}

Write-Host "[INFO] Removing Playwright skills..." -ForegroundColor Cyan

try {
    Remove-Item -Path $skillsDir -Recurse -Force -ErrorAction Stop
    Write-Host "[OK] Playwright skills removed!" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Failed to remove $skillsDir : $_" -ForegroundColor Yellow
}

# ---- 2. Clean up empty parent directories ----
$skillsParent = Join-Path $PWD ".claude\skills"
if ((Test-Path $skillsParent) -and (Get-ChildItem -Path $skillsParent -Force | Measure-Object).Count -eq 0) {
    Remove-Item -Path $skillsParent -Force -ErrorAction SilentlyContinue
    Write-Host "[INFO] Removed empty skills directory" -ForegroundColor Cyan
}
