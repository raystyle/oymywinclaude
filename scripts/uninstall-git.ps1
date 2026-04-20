#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Git for Windows (Portable) from D:\DevEnvs\Git.
.DESCRIPTION
    Removes registry keys (HKCU\Software\GitForWindows), cleans PATH entries,
    removes Git directory with three-tier fallback for locked files.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

# ---- Constants ----
$GitDir    = "D:\DevEnvs\Git"
$GitCmd    = "$GitDir\cmd"
$GitUsrBin = "$GitDir\usr\bin"
$RegKey    = "HKCU:\Software\GitForWindows"

Write-Host ""
Write-Host "=== Uninstall Git for Windows ===" -ForegroundColor Cyan

# ---- 1. Remove registry entries ----
if (Test-Path $RegKey) {
    Remove-Item -Path $RegKey -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $RegKey)) {
        Write-Host "[OK] Removed registry key: HKCU\Software\GitForWindows" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Failed to remove registry key" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[OK] Registry key not found (already clean)" -ForegroundColor DarkGray
}

# ---- 2. Remove from PATH ----
Remove-UserPath -Dir $GitCmd
Remove-UserPath -Dir $GitUsrBin

# Clean current session PATH
$env:PATH = ($env:PATH -split ';' | Where-Object {
    $n = $_.TrimEnd('\')
    ($n -ne $GitCmd) -and ($n -ne $GitUsrBin) -and
    (-not $n.StartsWith("$GitDir\", [StringComparison]::OrdinalIgnoreCase))
}) -join ';'

# ---- 3. Remove Git directory ----
if (Test-Path $GitDir) {
    Write-Host "[INFO] Removing $GitDir ..." -ForegroundColor Cyan

    # Tier 1: PowerShell Remove-Item
    $removed = $false
    try {
        Remove-Item -Path $GitDir -Recurse -Force -ErrorAction Stop
        $removed = $true
    }
    catch {
        Write-Host "[WARN] Direct removal failed: $_" -ForegroundColor Yellow
    }

    # Tier 2: cmd.exe rd /s /q
    if (-not $removed -and (Test-Path $GitDir)) {
        Write-Host "[INFO] Trying cmd.exe fallback..." -ForegroundColor DarkGray
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "rd /s /q `"$GitDir`"" `
            -NoNewWindow -PassThru -Wait | Out-Null
        if (-not (Test-Path $GitDir)) {
            $removed = $true
        }
    }

    # Tier 3: Rename to .pending-delete
    if (-not $removed -and (Test-Path $GitDir)) {
        $pendingName = "$GitDir.pending-delete.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        try {
            Rename-Item -Path $GitDir -NewName (Split-Path $pendingName -Leaf) -Force -ErrorAction Stop
            Write-Host "[WARN] Could not fully delete Git directory (files locked)." -ForegroundColor Yellow
            Write-Host "       Renamed to: $pendingName" -ForegroundColor Yellow
            Write-Host "       Delete it manually after closing all terminals." -ForegroundColor Yellow
            $removed = $true
        }
        catch {
            Write-Host "[ERROR] Failed to remove or rename Git directory." -ForegroundColor Red
            Write-Host "        Close all terminals/editors using Git and retry." -ForegroundColor Red
            Write-Host "        Or run from cmd.exe: rd /s /q `"$GitDir`"" -ForegroundColor Cyan
        }
    }

    if ($removed -and -not (Test-Path $GitDir)) {
        Write-Host "[OK] Removed $GitDir" -ForegroundColor Green
    }
}
else {
    Write-Host "[OK] $GitDir does not exist (already removed)" -ForegroundColor DarkGray
}

# ---- 4. Summary ----
Write-Host ""
if (-not (Test-Path $GitDir) -and -not (Test-Path $RegKey)) {
    Write-Host "[OK] Git for Windows uninstalled successfully." -ForegroundColor Green
}
else {
    Write-Host "[WARN] Partial cleanup, manual intervention may be needed." -ForegroundColor Yellow
}
Write-Host ""
