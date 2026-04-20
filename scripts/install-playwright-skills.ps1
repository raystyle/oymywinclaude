#Requires -Version 5.1

<#
.SYNOPSIS
    Install Playwright skills for Claude Code
.DESCRIPTION
    Runs 'playwright-cli install --skills' to register Playwright skills
    with Claude Code. Requires playwright-cli to be installed first.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

# ---- 1. Check playwright-cli ----
$pwCmd = Get-Command playwright-cli -ErrorAction SilentlyContinue
if (-not $pwCmd) {
    Write-Host "[ERROR] playwright-cli not found" -ForegroundColor Red
    Write-Host "       Run 'just install-playwright' to install Playwright CLI" -ForegroundColor DarkGray
    exit 1
}

Write-Host "[OK] playwright-cli found at $($pwCmd.Source)" -ForegroundColor Green

# ---- 2. Install skills ----
Write-Host "[INFO] Installing Playwright skills for Claude Code..." -ForegroundColor Cyan

try {
    & playwright-cli install --skills 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host "[OK] Playwright skills installed!" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to install Playwright skills: $_" -ForegroundColor Red
    exit 1
}
