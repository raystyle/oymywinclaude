#Requires -Version 5.1

<#
.SYNOPSIS
    Show Git for Windows installation status.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

# ---- Constants ----
$GitDir    = "D:\DevEnvs\Git"
$GitCmd    = "$GitDir\cmd"
$GitExe    = "$GitCmd\git.exe"
$GitUsrBin = "$GitDir\usr\bin"
$RegKey    = "HKCU:\Software\GitForWindows"

$installed     = $false
$installedVer  = $null

# ---- 1. Check installed version ----
if (Test-Path $GitExe) {
    if ($env:PATH -notmatch [regex]::Escape($GitCmd)) {
        $env:PATH = "$GitCmd;$env:PATH"
    }

    $raw = (& $GitExe --version 2>$null | Out-String).Trim()
    if ($raw -match 'git version\s+(.+)') {
        $installedVer = $Matches[1].Trim()
        $installed = $true
    }
}

# ---- 2. Check registry ----
$regOk          = $false
$regInstallPath = $null
if (Test-Path $RegKey) {
    $regInstallPath = (Get-ItemProperty -Path $RegKey -Name "InstallPath" -ErrorAction SilentlyContinue).InstallPath
    if ($regInstallPath -eq $GitDir) { $regOk = $true }
}

# ---- 4. Check .bashrc Chinese environment configuration ----
$bashrcPath = "$env:USERPROFILE\.bashrc"
$bashrcConfigured = $false
$bashrcExists = Test-Path $bashrcPath

if ($bashrcExists) {
    $bashrcContent = Get-Content $bashrcPath -Raw -ErrorAction SilentlyContinue
    if ($bashrcContent -match 'PYTHONIOENCODING=utf-8' -and
        $bashrcContent -match 'LANG=zh_CN\.UTF-8' -and
        $bashrcContent -match 'LC_ALL=zh_CN\.UTF-8') {
        $bashrcConfigured = $true
    }
}

# ---- 5. Display status ----
Write-Host ""
Write-Host "--- Git for Windows ---" -ForegroundColor Cyan

if ($installed) {
    Write-Host "[OK] $installedVer" -ForegroundColor Green
    Write-Host "  Location:        $GitDir" -ForegroundColor DarkGray
    Write-Host "  git.exe:         $GitExe" -ForegroundColor DarkGray

    if (Test-Path "$GitUsrBin\ssh.exe") {
        Write-Host "  ssh.exe:         $GitUsrBin\ssh.exe" -ForegroundColor DarkGray
    }

    if (Test-Path "$GitUsrBin\bash.exe") {
        Write-Host "  bash.exe:         $GitUsrBin\bash.exe" -ForegroundColor DarkGray
    }

    # Registry
    if ($regOk) {
        Write-Host "  Registry:        OK (HKCU\Software\GitForWindows)" -ForegroundColor DarkGray
    }
    elseif (Test-Path $RegKey) {
        Write-Host "  Registry:        Mismatch (InstallPath=$regInstallPath)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Registry:        Missing" -ForegroundColor DarkGray
    }

    # .bashrc Chinese environment configuration
    if ($bashrcConfigured) {
        Write-Host "  .bashrc:         OK (Chinese env configured)" -ForegroundColor DarkGray
    }
    elseif ($bashrcExists) {
        Write-Host "  .bashrc:         Found (Chinese env NOT configured)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  .bashrc:         Missing" -ForegroundColor DarkGray
    }

    # Compare versions
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-git' to install" -ForegroundColor DarkGray
}
