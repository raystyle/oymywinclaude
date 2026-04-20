#Requires -Version 5.1

<#
.SYNOPSIS
    Generic GitHub Release tool installer
.DESCRIPTION
    Downloads a zip from GitHub Release, extracts to ~/.local/bin.
    Supports idempotent install, upgrade, and SHA256 integrity verification.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repo,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExeName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ArchiveName,

    [AllowEmptyString()]
    [string]$Version = "",

    [string]$TagPrefix = "",

    [switch]$Force,

    [switch]$NoBackup,

    [string]$CacheDir = "",

    [switch]$DirectExe
)

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\$ExeName"

# ---- 1. Resolve version & release metadata ----
if (-not $Version) {
    Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo
        $rawTag  = $release.tag_name
        $Version = if ($TagPrefix -and $rawTag.StartsWith($TagPrefix)) {
            $rawTag.Substring($TagPrefix.Length)
        } else {
            $rawTag -replace '^v', ''
        }
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
    $tag = "${TagPrefix}${Version}"
    Write-Host "[INFO] Fetching release metadata for $Repo@$tag..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo -Tag $tag
    }
    catch {
        Write-Host "[WARN] Could not fetch release metadata, hash verification will be skipped" -ForegroundColor Yellow
        $release = $null
    }
}

$tag = "${TagPrefix}${Version}"
Write-Host "[INFO] Target: $ExeName $Version (tag: $tag)" -ForegroundColor Cyan

# ---- 2. Idempotent check ----
$backupPath = $null
if (Test-Path $exePath) {
    $raw = & $exePath --version 2>&1 | Out-String
    $installed = ''
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $installed = $Matches[1]
    }

    # Check if upgrade is required using semantic version comparison
    $toolName = $ExeName -replace '\.exe$', ''
    $upgradeCheck = Test-UpgradeRequired -Current $installed -Target $Version -ToolName $toolName -Force:$Force

    if (-not $upgradeCheck.Required) {
        Write-Host "[OK] $ExeName $Version already installed, skipping." -ForegroundColor Green
        Write-Host "[INFO] $($upgradeCheck.Reason)" -ForegroundColor Cyan
        Add-UserPath -Dir $binDir
        exit 0
    }

    # Upgrade needed
    if ($installed) {
        Write-Host "[UPGRADE] $installed -> $Version" -ForegroundColor Cyan
        Write-Host "     Reason: $($upgradeCheck.Reason)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[WARN] $ExeName exists but version unreadable, reinstalling" -ForegroundColor Yellow
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
            $backupPath = Backup-ToolVersion -ToolName $ExeName -ExePath $exePath
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
    $uninstallScript = "$PSScriptRoot\uninstall-tool.ps1"
    if (Test-Path $uninstallScript) {
        try {
            & $uninstallScript -ExeName $ExeName -Force
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
$resolvedArchive = $ArchiveName -replace '\{version\}', $Version -replace '\{tag\}', $tag
$downloadUrl = "https://github.com/$Repo/releases/download/$tag/$resolvedArchive"
$zipFile = "$env:TEMP\$resolvedArchive"

Write-Host "[INFO] Downloading $resolvedArchive ..." -ForegroundColor Cyan
try {
    if ($CacheDir) {
        Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir $CacheDir
    } else {
        Save-WithProxy -Url $downloadUrl -OutFile $zipFile
    }
}
catch {
    Write-Host "[ERROR] Failed to download $resolvedArchive" -ForegroundColor Red
    Write-Host "       URL: $downloadUrl" -ForegroundColor DarkGray
    exit 1
}

# ---- 4. Verify SHA256 digest ----
try {
    Test-FileHash -FilePath $zipFile -Release $release -AssetName $resolvedArchive
}
catch {
    Write-Host "[ERROR] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. Extract / Copy ----
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Write-Host "[OK] Created: $binDir" -ForegroundColor Green
}

if ($DirectExe) {
    # Direct exe download — no archive to extract
    try {
        Copy-Item -Path $zipFile -Destination $exePath -Force -ErrorAction Stop
    }
    catch {
        Write-Host "[ERROR] Failed to copy $resolvedArchive" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}
else {
    # Zip archive — extract to binDir
    try {
        Expand-Archive -Path $zipFile -DestinationPath $binDir -Force -ErrorAction Stop
    }
    catch {
        Write-Host "[ERROR] Failed to extract $resolvedArchive" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        exit 1
    }

    # Handle nested directory: some zips put exe inside a subfolder
    if (-not (Test-Path $exePath)) {
        $found = Get-ChildItem -Path $binDir -Filter $ExeName -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            Move-Item -Path $found.FullName -Destination $exePath -Force
            Write-Host "[OK] Moved $ExeName from nested directory" -ForegroundColor Green
        }
        else {
            Write-Host "[ERROR] $ExeName not found after extraction" -ForegroundColor Red
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
}

# ---- 6. PATH + cleanup ----
Add-UserPath -Dir $binDir
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

# ---- 7. Verify ----
Write-Host "[INFO] Verifying..." -ForegroundColor Cyan
$result = & $exePath --version 2>&1 | Out-String
if ($result -match '(\d+\.\d+\.\d+)') {
    $installedVersion = $Matches[1]
    if ($installedVersion -eq $Version) {
        Write-Host "[OK] Installed: $($result.Trim())" -ForegroundColor Green
        Write-Host "[INFO] Path: $exePath" -ForegroundColor Cyan

        # Clean up backup on successful upgrade
        if ($backupPath -and (Test-Path (Split-Path $backupPath -Parent))) {
            try {
                Remove-Item (Split-Path $backupPath -Parent) -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "[INFO] Cleaned up backup" -ForegroundColor Cyan
            }
            catch {
                # Cleanup failed, but installation succeeded — log and continue
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
                Restore-ToolVersion -ToolName $ExeName -BackupPath $backupPath -TargetPath $exePath
                Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Rollback failed: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "[ERROR] Tool may be in inconsistent state" -ForegroundColor Red
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
            Restore-ToolVersion -ToolName $ExeName -BackupPath $backupPath -TargetPath $exePath
            Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            Write-Host "[INFO] Backup retained at: $backupPath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[ERROR] Rollback failed: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[ERROR] Tool may be in inconsistent state" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[ERROR] No backup available, cannot rollback" -ForegroundColor Red
    }
    exit 1
}
