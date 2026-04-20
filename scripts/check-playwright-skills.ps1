#Requires -Version 5.1

<#
.SYNOPSIS
    Show Playwright skills installation status for Claude Code
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"

Write-Host "--- Playwright Skills ---" -ForegroundColor Cyan

# ---- 1. Check playwright-cli ----
$pwCmd = Get-Command playwright-cli -ErrorAction SilentlyContinue
if (-not $pwCmd) {
    Write-Host "[WARN] playwright-cli: NOT installed" -ForegroundColor Yellow
    Write-Host "  Run 'just install-playwright' first" -ForegroundColor DarkGray
    return
}
Write-Host "[OK] playwright-cli: $($pwCmd.Source)" -ForegroundColor Green

# ---- 2. Check if skills are registered ----
# Fast check: verify skills directory exists instead of calling CLI
$skillsDir = Join-Path $PWD ".claude\skills\playwright-cli"
if (Test-Path $skillsDir) {
    Write-Host "[OK] Playwright skills: registered" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Playwright skills: not registered" -ForegroundColor Yellow
    Write-Host "  Run 'just install-playwright-skills' to install" -ForegroundColor DarkGray
}
