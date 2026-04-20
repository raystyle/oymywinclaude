#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Playwright CLI (npm global package)
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

if (-not $Force) {
    $answer = Read-Host "Uninstall Playwright CLI? (yes/no)"
    if ($answer -ne 'yes') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# ---- 1. Uninstall via npm ----
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "[INFO] Uninstalling @playwright/cli via npm..." -ForegroundColor Cyan
    try {
        & npm uninstall -g @playwright/cli 2>&1 | Out-Null
        Write-Host "[OK] @playwright/cli removed" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] npm uninstall failed: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] npm not found, skipping npm uninstall" -ForegroundColor Yellow
}

# ---- 2. Remove old .cmd shim (if exists) ----
$oldCmdShim = "$env:USERPROFILE\.local\bin\playwright-cli.cmd"
if (Test-Path $oldCmdShim) {
    Remove-Item -Path $oldCmdShim -Force
    Write-Host "[OK] Removed old .cmd shim: $oldCmdShim" -ForegroundColor Green
}

# ---- 3. Remove shim.exe and .shim config ----
$shimExePath = "$env:USERPROFILE\.local\bin\playwright-cli.exe"
$shimConfigPath = "$env:USERPROFILE\.local\bin\playwright-cli.shim"

if (Test-Path $shimExePath) {
    Remove-Item -Path $shimExePath -Force
    Write-Host "[OK] Removed shim: $shimExePath" -ForegroundColor Green
}

if (Test-Path $shimConfigPath) {
    Remove-Item -Path $shimConfigPath -Force -Force
    Write-Host "[OK] Removed shim config: $shimConfigPath" -ForegroundColor Green
}

# ---- 4. Verify ----
$pwCmd = Get-Command playwright-cli -ErrorAction SilentlyContinue
if ($pwCmd) {
    Write-Host "[WARN] playwright-cli still found at $($pwCmd.Source)" -ForegroundColor Yellow
}
else {
    Write-Host "[OK] Playwright CLI uninstall completed!" -ForegroundColor Green
}
