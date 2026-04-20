#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$DistroName,

    [string]$TargetDir = "",

    [switch]$RemoveBackup
)

# Error action preference
$ErrorActionPreference = "Stop"

# Helper functions for logging
function Write-OK { param([string]$msg); Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info { param([string]$msg); Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$msg); Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-ErrLog { param([string]$msg); Write-Host "[ERROR] $msg" -ForegroundColor Red }

Write-Host "🗑️  Starting WSL distro uninstallation: $DistroName" -ForegroundColor Cyan

# 0. Check if distro exists
$wslList = wsl.exe -l -q 2>$null
$distroExists = $wslList | Where-Object { $_.Replace("`0","").Trim() -eq $DistroName }

if (-not $distroExists) {
    Write-Warn "WSL distro '$DistroName' does not exist"
} else {
    Write-OK "Found WSL distro '$DistroName'"

    # 1. Stop WSL instance
    Write-Info "Stopping WSL instance..."
    wsl --terminate $DistroName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Stopped WSL instance"
    } else {
        Write-Warn "Failed to stop WSL instance or instance not running"
    }
    Start-Sleep -Seconds 1

    # 2. Unregister distro
    Write-Info "Unregistering WSL distro..."
    wsl --unregister $DistroName 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Unregistered WSL distro '$DistroName'"
    } else {
        Write-ErrLog "Failed to unregister WSL distro, error code: $LASTEXITCODE"
        exit 1
    }
}

# 3. Delete installation directory
if ($TargetDir -and (Test-Path $TargetDir)) {
    Write-Info "Removing installation directory: $TargetDir"

    try {
        Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction Stop
        Write-OK "Removed installation directory"
    } catch {
        Write-Warn "PowerShell removal failed, trying cmd..."
        cmd /c "rd /s /q `"$TargetDir`"" 2>$null
        if (-not (Test-Path $TargetDir)) {
            Write-OK "Removed installation directory (cmd)"
        } else {
            Write-ErrLog "Failed to remove installation directory: $($_.Exception.Message)"
            exit 1
        }
    }

    # 4. Delete backup files
    if ($RemoveBackup) {
        Write-Info "Cleaning up backup files..."

        $backupFiles = Get-ChildItem -Path (Split-Path $TargetDir) -Filter "$($TargetDir | Split-Path -Leaf)*.bak*" -ErrorAction SilentlyContinue

        if ($backupFiles) {
            foreach ($backup in $backupFiles) {
                try {
                    Remove-Item -Path $backup.FullName -Force -ErrorAction Stop
                    Write-OK "Removed backup: $($backup.Name)"
                } catch {
                    Write-Warn "Failed to remove backup: $($backup.Name)"
                }
            }
        } else {
            Write-Info "No backup files found"
        }
    }
} elseif ($TargetDir) {
    Write-Info "Installation directory does not exist: $TargetDir"
} else {
    Write-Info "No installation directory specified, skipping directory cleanup"
}

# 5. Final verification
Write-Host "`n=== Verifying uninstallation results ===" -ForegroundColor Cyan

# Check if distro is unregistered
$wslList = wsl.exe -l -q 2>$null
$distroExists = $wslList | Where-Object { $_.Replace("`0","").Trim() -eq $DistroName }

if (-not $distroExists) {
    Write-OK "WSL distro '$DistroName' completely removed"
} else {
    Write-Warn "WSL distro '$DistroName' still exists"
}

# Check if directory is removed
if ($TargetDir) {
    if (-not (Test-Path $TargetDir)) {
        Write-OK "Installation directory '$TargetDir' completely removed"
    } else {
        Write-Warn "Installation directory '$TargetDir' still exists"
    }
}

Write-Host "`n✅ WSL distro '$DistroName' uninstallation completed!" -ForegroundColor Green
