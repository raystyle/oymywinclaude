#Requires -Version 5.1

<#
.SYNOPSIS
    Show Python + uv installation status.
.PARAMETER InstallDir
    Installation directory. Default: D:\DevEnvs\Python
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "D:\DevEnvs\Python"
)

$pythonExe = "$InstallDir\python.exe"
$pipExe    = "$InstallDir\Scripts\pip.exe"
$uvExe     = "$InstallDir\Scripts\uv.exe"

Write-Host "--- Python + uv ---" -ForegroundColor Cyan

# Python
if (Test-Path $pythonExe) {
    $ver = & $pythonExe --version 2>&1 | Out-String
    Write-Host "[OK] $($ver.Trim())" -ForegroundColor Green
    Write-Host "  Location:        $InstallDir" -ForegroundColor DarkGray
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Expected:        $InstallDir" -ForegroundColor DarkGray
    Write-Host "  Run 'just install-python' to install" -ForegroundColor DarkGray
    return
}

# pip
if (Test-Path $pipExe) {
    $ver = & $pipExe --version 2>&1 | Out-String
    Write-Host "  pip:             $($ver.Trim())" -ForegroundColor DarkGray
}
else {
    Write-Host "  pip:             not installed" -ForegroundColor DarkGray
}

# pip mirror
$pipConfig = "$env:APPDATA\pip\pip.ini"
if (Test-Path $pipConfig) {
    $content = Get-Content -Path $pipConfig -Raw -ErrorAction SilentlyContinue
    if ($content -match 'index-url\s*=\s*(.+)') {
        Write-Host "  pip mirror:      $($Matches[1].Trim())" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  pip mirror:      not configured" -ForegroundColor DarkGray
}

# uv
if (Test-Path $uvExe) {
    $ver = & $uvExe --version 2>&1 | Out-String
    Write-Host "  uv:              $($ver.Trim())" -ForegroundColor DarkGray
}
else {
    Write-Host "  uv:              not installed" -ForegroundColor DarkGray
}

# uv mirror
$uvConfig = "$env:APPDATA\uv\uv.toml"
if (Test-Path $uvConfig) {
    $content = Get-Content -Path $uvConfig -Raw -ErrorAction SilentlyContinue
    if ($content -match 'url\s*=\s*"(.+)"') {
        Write-Host "  uv mirror:       $($Matches[1])" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  uv mirror:       not configured" -ForegroundColor DarkGray
}

# ruff
$ruffExe = "$env:USERPROFILE\.local\bin\ruff.exe"
if (Test-Path $ruffExe) {
    $ver = & $ruffExe --version 2>&1 | Out-String
    Write-Host "  ruff:            $($ver.Trim())" -ForegroundColor DarkGray
}
else {
    Write-Host "  ruff:            not installed" -ForegroundColor DarkGray
}

# ty
$tyExe = "$env:USERPROFILE\.local\bin\ty.exe"
if (Test-Path $tyExe) {
    $ver = & $tyExe --version 2>&1 | Out-String
    Write-Host "  ty:              $($ver.Trim())" -ForegroundColor DarkGray
}
else {
    Write-Host "  ty:              not installed" -ForegroundColor DarkGray
}
