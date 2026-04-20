#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall PowerShell 7 (pwsh) via MSI product code.
.DESCRIPTION
    Finds PowerShell 7 MSI product code from Windows registry,
    runs msiexec /x for clean uninstall, then removes any
    leftover files with three-tier fallback.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

$PwshDir = "$Env:ProgramFiles\PowerShell\7"

Write-Host ""
Write-Host "=== Uninstall PowerShell 7 ===" -ForegroundColor Cyan

# ---- 1. Find MSI product code ----
$productCode = $null
$displayName = $null

$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $uninstallPaths) {
    $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*PowerShell 7*' -and $_.PSChildName -match '^\{' } |
        Select-Object -First 1
    if ($entry) {
        $productCode = $entry.PSChildName
        $displayName = $entry.DisplayName
        break
    }
}

if (-not $productCode) {
    Write-Host "[INFO] PowerShell 7 not found in installed programs (MSI)" -ForegroundColor Cyan

    if (Test-Path $PwshDir) {
        Write-Host "[INFO] But $PwshDir exists, removing manually..." -ForegroundColor Yellow
    }
    else {
        Write-Host "[OK] PowerShell 7 not installed, nothing to do." -ForegroundColor Green
        return
    }
}
else {
    Write-Host "[INFO] Found: $displayName (code: $productCode)" -ForegroundColor Cyan

    # ---- 2. Run msiexec /x ----
    Write-Host "[INFO] Running msiexec /x $productCode /quiet /norestart ..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList @(
        "/x", $productCode, "/quiet", "/norestart"
    ) -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010 -or $proc.ExitCode -eq 1605) {
        Write-Host "[OK] MSI uninstall completed (exit code: $($proc.ExitCode))" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] msiexec exit code: $($proc.ExitCode)" -ForegroundColor Yellow
    }
}

# ---- 3. Remove install directory (if MSI left files) ----
if (Test-Path $PwshDir) {
    Write-Host "[INFO] Cleaning up $PwshDir ..." -ForegroundColor Cyan

    # Tier 1
    $removed = $false
    try {
        Remove-Item -Path $PwshDir -Recurse -Force -ErrorAction Stop
        $removed = $true
    }
    catch {
        Write-Host "[WARN] Direct removal failed: $_" -ForegroundColor Yellow
    }

    # Tier 2
    if (-not $removed -and (Test-Path $PwshDir)) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "rd /s /q `"$PwshDir`"" `
            -NoNewWindow -PassThru -Wait | Out-Null
        if (-not (Test-Path $PwshDir)) { $removed = $true }
    }

    # Tier 3
    if (-not $removed -and (Test-Path $PwshDir)) {
        $pendingName = "$PwshDir.pending-delete.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        try {
            Rename-Item -Path $PwshDir -NewName (Split-Path $pendingName -Leaf) -Force -ErrorAction Stop
            Write-Host "[WARN] Renamed to: $pendingName" -ForegroundColor Yellow
            $removed = $true
        }
        catch {
            Write-Host "[ERROR] Could not remove or rename: $PwshDir" -ForegroundColor Red
        }
    }

    if ($removed -and -not (Test-Path $PwshDir)) {
        Write-Host "[OK] Removed $PwshDir" -ForegroundColor Green
    }
}
else {
    Write-Host "[OK] $PwshDir does not exist (already clean)" -ForegroundColor DarkGray
}

# ---- 4. Summary ----
Write-Host ""
Write-Host "[OK] PowerShell 7 uninstalled." -ForegroundColor Green
Write-Host ""
