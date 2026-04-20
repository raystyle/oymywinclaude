#Requires -Version 5.1

<#
.SYNOPSIS
    Install jq - Command-line JSON processor
.DESCRIPTION
    Downloads jq executable from GitHub Releases and installs to ~/.local/bin.
    Supports idempotent install, upgrade, and SHA256 integrity verification.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force,
    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\jq.exe"
$repo    = "jqlang/jq"

# ---- 1. Resolve version ----
if (-not $Version) {
    Write-Host "[INFO] Fetching latest release for $repo..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $repo
        $rawTag  = $release.tag_name
        # jq tags are like "jq-1.8.1", remove "jq-" prefix
        $Version = $rawTag -replace '^jq-', ''
        Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow

        # If tool already exists, skip version check and continue
        if (Test-Path $exePath) {
            Write-Host "[INFO] Tool already installed, skipping version check..." -ForegroundColor Cyan
            Add-UserPath -Dir $binDir
            exit 0
        }
        else {
            Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
            Write-Host "       Please try again later or specify version with -Version parameter" -ForegroundColor DarkGray
            exit 1
        }
    }
}
else {
    # Version specified explicitly — still need release metadata for digest
    $tag = "jq-$Version"
    Write-Host "[INFO] Fetching release metadata for $repo@$tag..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $repo -Tag $tag
    }
    catch {
        Write-Host "[WARN] Could not fetch release metadata, hash verification will be skipped" -ForegroundColor Yellow
        $release = $null
    }
}

$tag = "jq-$Version"
Write-Host "[INFO] Target: jq $Version (tag: $tag)" -ForegroundColor Cyan

# ---- 2. Idempotent check ----
$backupPath = $null
if (Test-Path $exePath) {
    $raw = & $exePath --version 2>&1 | Out-String
    if ($raw -match 'jq-([\d.]+)') {
        $installed = $Matches[1]
    }
    else {
        $installed = ''
    }

    # Check if upgrade is required using semantic version comparison
    $upgradeCheck = Test-UpgradeRequired -Current $installed -Target $Version -ToolName "jq" -Force:$Force

    if (-not $upgradeCheck.Required) {
        Write-Host "[OK] jq $Version already installed, skipping." -ForegroundColor Green
        Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
        Add-UserPath -Dir $binDir
        exit 0
    }

    # Upgrade needed
    if ($installed) {
        Write-Host "[UPGRADE] $installed -> $Version" -ForegroundColor Cyan
        Write-Host "     Reason: $($upgradeCheck.Reason)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[WARN] jq.exe exists but version unreadable, reinstalling" -ForegroundColor Yellow
    }

    # User confirmation for upgrade (skip in Force mode)
    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor Cyan
        Write-Host "    • Backup current version" -ForegroundColor DarkGray
        Write-Host "    • Uninstall old version" -ForegroundColor DarkGray
        Write-Host "    • Install new version" -ForegroundColor DarkGray
        Write-Host "    • Verify installation" -ForegroundColor DarkGray
        Write-Host "    • Rollback on failure" -ForegroundColor DarkGray
        Write-Host ""
        $response = Read-Host "  Continue? [Y/n]"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Upgrade cancelled by user" -ForegroundColor Cyan
            exit 0
        }
    }

    # Backup current version (unless NoBackup is set)
    if (-not $NoBackup) {
        try {
            Write-Host "[INFO] Backing up current version..." -ForegroundColor Cyan
            $backupPath = Backup-ToolVersion -ToolName "jq" -ExePath $exePath
            Write-Host "[OK] Backed up to: $backupPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
            Write-Host "[WARN] Proceeding without backup" -ForegroundColor Yellow
            $backupPath = $null
        }
    }

    # Uninstall old version
    Write-Host "[INFO] Uninstalling old version..." -ForegroundColor Cyan
    $uninstallScript = "$PSScriptRoot\uninstall-jq.ps1"
    if (Test-Path $uninstallScript) {
        try {
            & $uninstallScript -Force
            Write-Host "[OK] Uninstalled old version" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Uninstall script failed: $_" -ForegroundColor Yellow
            Write-Host "[INFO] Manually removing $exePath" -ForegroundColor Cyan
            Remove-Item $exePath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Remove-Item $exePath -Force -ErrorAction SilentlyContinue
    }
}

# ---- 3. Download ----
# jq releases use naming: jq-windows-amd64.exe
$fileName = "jq-windows-amd64.exe"
$downloadUrl = "https://github.com/$repo/releases/download/$tag/$fileName"
$tempFile = "$env:TEMP\$fileName"

Write-Host "[INFO] Downloading $fileName ..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $downloadUrl -OutFile $tempFile -CacheDir "jq"
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    exit 1
}

# ---- 4. Verify SHA256 digest ----
try {
    Test-FileHash -FilePath $tempFile -Release $release -AssetName $fileName
}
catch {
    Write-Host "[ERROR] $_" -ForegroundColor Red
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. Install ----
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Write-Host "[OK] Created: $binDir" -ForegroundColor Green
}

try {
    Move-Item -Path $tempFile -Destination $exePath -Force -ErrorAction Stop
    Write-Host "[OK] Installed: $exePath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Install failed: $_" -ForegroundColor Red
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 6. PATH configuration ----
Add-UserPath -Dir $binDir

# ---- 7. Verify ----
Write-Host "[INFO] Verifying..." -ForegroundColor Cyan
$result = & $exePath --version 2>&1 | Out-String
if ($result -match 'jq-([\d.]+)') {
    $installedVersion = $Matches[1]
    if ($installedVersion -eq $Version) {
        Write-Host "[OK] Installed: $($result.Trim())" -ForegroundColor Green
        Write-Host "[INFO] Path: $exePath" -ForegroundColor Cyan

        # Clean up backup on successful upgrade
        if ($backupPath -and (Test-Path (Split-Path $backupPath -Parent))) {
            try {
                Remove-Item (Split-Path $backupPath -Parent) -Recurse -Force -ErrorAction Stop
                Write-Host "[INFO] Cleaned up backup" -ForegroundColor Cyan
            }
            catch {
                # Cleanup failed, but installation succeeded — ignore to avoid masking the real success
                Write-Verbose "Failed to clean up backup: $_"
            }
        }
    }
    else {
        Write-Host "[ERROR] Version mismatch! Expected: $Version, Got: $installedVersion" -ForegroundColor Red

        # Rollback from backup
        if ($backupPath -and (Test-Path $backupPath)) {
            Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
            try {
                Restore-ToolVersion -ToolName "jq" -BackupPath $backupPath -TargetPath $exePath
                Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Rollback failed: $_" -ForegroundColor Red
            }
        }
        exit 1
    }
}
else {
    Write-Host "[ERROR] Verification failed, executable not responding" -ForegroundColor Red

    # Rollback from backup
    if ($backupPath -and (Test-Path $backupPath)) {
        Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
        try {
            Restore-ToolVersion -ToolName "jq" -BackupPath $backupPath -TargetPath $exePath
            Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            Write-Host "[INFO] Backup retained at: $backupPath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[ERROR] Rollback failed: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[ERROR] No backup available, cannot rollback" -ForegroundColor Red
    }
    exit 1
}
