#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall markdownlint-cli2 (npm global package) and shim
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

if (-not $Force) {
    $answer = Read-Host "Uninstall markdownlint? (yes/no)"
    if ($answer -ne 'yes') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# ---- 1. Uninstall via npm ----
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "[INFO] Uninstalling markdownlint-cli2 via npm..." -ForegroundColor Cyan
    try {
        & npm uninstall -g markdownlint-cli2 2>&1 | Out-Null
        Write-Host "[OK] markdownlint-cli2 removed" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] npm uninstall failed: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] npm not found, skipping npm uninstall" -ForegroundColor Yellow
}

# ---- 2. Remove shim exe and .shim config ----
$binDir       = "$env:USERPROFILE\.local\bin"
$shimExePath  = "$binDir\markdownlint.exe"
$shimConfPath = "$binDir\markdownlint.shim"

if (Test-Path $shimExePath) {
    Remove-Item -Path $shimExePath -Force
    Write-Host "[OK] Removed shim: $shimExePath" -ForegroundColor Green
}

if (Test-Path $shimConfPath) {
    Remove-Item -Path $shimConfPath -Force
    Write-Host "[OK] Removed shim config: $shimConfPath" -ForegroundColor Green
}

# ---- 3. Remove manual shim at D:\DevEnvs\node (legacy) ----
$nodeDir      = "D:\DevEnvs\node"
$oldShimExe   = "$nodeDir\markdownlint.exe"
$oldShimConf  = "$nodeDir\markdownlint.shim"

if (Test-Path $oldShimExe) {
    Remove-Item -Path $oldShimExe -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed legacy shim: $oldShimExe" -ForegroundColor Green
}

if (Test-Path $oldShimConf) {
    Remove-Item -Path $oldShimConf -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed legacy shim config: $oldShimConf" -ForegroundColor Green
}

# ---- 4. Verify ----
$mdCmd = Get-Command markdownlint -ErrorAction SilentlyContinue
if ($mdCmd) {
    Write-Host "[WARN] markdownlint still found at $($mdCmd.Source)" -ForegroundColor Yellow
}
else {
    Write-Host "[OK] markdownlint uninstall completed!" -ForegroundColor Green
}
