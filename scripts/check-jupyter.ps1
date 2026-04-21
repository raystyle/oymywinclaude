#Requires -Version 5.1

<#
.SYNOPSIS
    Check jupyter-core installation status via uv tool list
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

Write-Host "--- Jupyter ---" -ForegroundColor Cyan

# ---- 1. Check uv ----
if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "[WARN] uv not installed" -ForegroundColor Yellow
    Write-Host "       Run 'just install-python' to install" -ForegroundColor DarkGray
    exit 0
}

# ---- 2. Check jupyter-core via uv tool list ----
$uvList = & uv tool list 2>&1
$jupyterBlock = @()
$inBlock = $false
$found = $false

foreach ($line in $uvList) {
    if ($line -match "^\s*$") {
        if ($inBlock) { break }
        continue
    }
    if ($line -match "jupyter-core") {
        $found = $true
        $inBlock = $true
        $jupyterBlock += $line
        continue
    }
    if ($inBlock) {
        if ($line -match "^- ") {
            $jupyterBlock += $line
        }
        else {
            break
        }
    }
}

if ($found) {
    Write-Host "[OK] $($jupyterBlock[0])" -ForegroundColor Green
    foreach ($cmd in $jupyterBlock[1..($jupyterBlock.Length - 1)]) {
        Write-Host "     $cmd" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[WARN] jupyter-core not installed" -ForegroundColor Yellow
    Write-Host "       Run 'just install-jupyter' to install" -ForegroundColor DarkGray
}
