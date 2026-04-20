#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall jupyter-core and related tools via uv
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = "Stop"

$uvList = & uv tool list 2>&1 | Out-String
if ($uvList -notmatch "jupyter-core") {
    Write-Host "[INFO] jupyter-core not installed" -ForegroundColor Cyan
    exit 0
}

Write-Host "[INFO] Uninstalling jupyter-core..." -ForegroundColor Cyan
& uv tool uninstall jupyter-core 2>$null

# Clean up residual executables
$uvBin = "$env:USERPROFILE\.local\bin"
if (Test-Path $uvBin) {
    Get-ChildItem $uvBin -Filter "jupyter*.exe" -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
}
Write-Host "[OK] jupyter-core uninstalled" -ForegroundColor Green
