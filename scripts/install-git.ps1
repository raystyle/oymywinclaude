#Requires -Version 5.1

<#
.SYNOPSIS
    Install Git for Windows (Portable) to D:\DevEnvs\Git.
.DESCRIPTION
    Automatically fetches latest release from GitHub API (with releases/latest
    redirect fallback), finds the PortableGit 64-bit 7z SFX asset, downloads
    (with gh-proxy fallback), verifies SHA256, extracts, writes registry keys,
    and adds to PATH.
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

# ---- Constants ----
$GitDir       = "D:\DevEnvs\Git"
$GitCmd       = "$GitDir\cmd"
$GitExe       = "$GitCmd\git.exe"
$GitUsrBin    = "$GitDir\usr\bin"
$Repo         = "git-for-windows/git"
$AssetPattern = '^PortableGit-.*-64-bit\.7z\.exe$'
$RegKey       = "HKCU:\Software\GitForWindows"

# ---- 0. Idempotent check & .bashrc configuration ----
$gitInstalled = $false
$installedVersion = $null
$backupPath = $null

if (Test-Path $GitExe) {
    if ($env:PATH -notmatch [regex]::Escape($GitCmd)) {
        $env:PATH = "$GitCmd;$env:PATH"
    }

    $currentVer = (& $GitExe --version 2>$null | Out-String).Trim()
    if ($currentVer) {
        # Extract version from "git version 2.53.0.windows.2" format
        if ($currentVer -match 'git version\s+(.+)') {
            $verStr = $Matches[1].Trim()
            # Convert "2.53.0.windows.2" → "2.53.0.2", "2.53.0.windows.1" → "2.53.0"
            if ($verStr -match '^(.+)\.windows\.(\d+)$') {
                $base  = $Matches[1]
                $patch = $Matches[2]
                $installedVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
            }
            else {
                $installedVersion = $verStr
            }
        }
        $gitInstalled = $true
    }
}

# Check if .bashrc needs configuration (even if Git is already installed)
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

# If Git is installed but .bashrc is not configured, configure it now
if ($gitInstalled -and -not $bashrcConfigured) {
    Write-Host "[INFO] Git installed but .bashrc needs Chinese environment configuration..." -ForegroundColor Cyan

    $bashrcConfig = @"
export PYTHONIOENCODING=utf-8
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
"@

    try {
        # Create .bashrc if it doesn't exist
        if (-not (Test-Path $bashrcPath)) {
            New-Item -Path $bashrcPath -ItemType File -Force | Out-Null
        }

        # Append our configuration
        Add-Content -Path $bashrcPath -Value $bashrcConfig -Encoding UTF8
        Write-Host "[OK] Added Chinese environment variables to $bashrcPath" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to configure .bashrc: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Return since we only needed to update .bashrc
    return
}

# If Git is already installed and .bashrc is configured, check version
if ($gitInstalled -and $bashrcConfigured) {
    Write-Host "[OK] Git already installed: $currentVer" -ForegroundColor Green
    Write-Host "[INFO] Location: $GitDir" -ForegroundColor Cyan
    Write-Host "[INFO] Version: $installedVersion" -ForegroundColor Cyan
}

# ---- 0.5. Version upgrade check ----
if ($gitInstalled -and $bashrcConfigured) {
    # Get latest version first to compare
    Write-Host "[INFO] Checking for updates..." -ForegroundColor Cyan

    $release = $null
    $tag     = $null
    $latestVersion = $null

    try {
        $release = Get-GitHubRelease -Repo $Repo
        $tag = $release.tag_name
        # Parse version from tag (v2.53.0.windows.2 → 2.53.0.2)
        if ($tag -match '^v?(.+)\.windows\.(\d+)$') {
            $base  = $Matches[1]
            $patch = $Matches[2]
            $latestVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
        }
        elseif ($tag -match '^v?(.+)$') {
            $latestVersion = $Matches[1]
        }
        Write-Host "[INFO] Latest version: $latestVersion" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[WARN] Could not check for updates: $_" -ForegroundColor Yellow
        Write-Host "[OK] Git and .bashrc Chinese environment already configured" -ForegroundColor Green
        return
    }

    # Check if upgrade is required
    $upgradeCheck = Test-UpgradeRequired -Current $installedVersion -Target $latestVersion -ToolName "git" -Force:$Force

    if (-not $upgradeCheck.Required) {
        Write-Host "[OK] Git and .bashrc Chinese environment already configured" -ForegroundColor Green
        Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
        return
    }

    # Upgrade needed
    Write-Host "[UPGRADE] $installedVersion -> $latestVersion" -ForegroundColor Cyan
    Write-Host "     Reason: $($upgradeCheck.Reason)" -ForegroundColor DarkGray

    # User confirmation for upgrade (skip in Force mode)
    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor Cyan
        Write-Host "    • Backup current Git directory" -ForegroundColor DarkGray
        Write-Host "    • Uninstall old version" -ForegroundColor DarkGray
        Write-Host "    • Install new version" -ForegroundColor DarkGray
        Write-Host "    • Verify installation" -ForegroundColor DarkGray
        Write-Host "    • Rollback on failure" -ForegroundColor DarkGray
        Write-Host ""
        $response = Read-Host "  Continue? [Y/n]"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Upgrade cancelled by user" -ForegroundColor Cyan
            return
        }
    }

    # Backup current version (unless NoBackup is set)
    if (-not $NoBackup) {
        try {
            Write-Host "[INFO] Backing up current Git directory..." -ForegroundColor Cyan
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupDir = Join-Path $env:TEMP "Git-backup-$timestamp"
            $backupPath = Join-Path $backupDir "Git"

            # Create backup directory and copy entire Git directory
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            Copy-Item -Path $GitDir -Destination $backupPath -Recurse -Force

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
    $uninstallScript = "$PSScriptRoot\uninstall-git.ps1"
    if (Test-Path $uninstallScript) {
        try {
            & $uninstallScript -Force
            Write-Host "[OK] Uninstalled old version" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Uninstall script failed: $_" -ForegroundColor Yellow
            Write-Host "[INFO] Manually removing $GitDir" -ForegroundColor Cyan
            Remove-Item $GitDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Remove-Item $GitDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Continue with installation (fall through to section 1)
}
elseif ($gitInstalled -and -not $bashrcConfigured) {
    # This case is handled above, but we should not continue
    return
}
elseif (-not $gitInstalled) {
    # Fresh installation, continue normal flow
    Write-Host "[INFO] Git not installed, proceeding with installation..." -ForegroundColor Cyan
}

# ---- 1. Resolve latest release ----
Write-Host "[INFO] Resolving latest Git for Windows release..." -ForegroundColor Cyan

$release = $null
$tag     = $null

try {
    $release = Get-GitHubRelease -Repo $Repo
    $tag = $release.tag_name
}
catch {
    Write-Host "[WARN] GitHub API failed: $_" -ForegroundColor Yellow
}

if (-not $tag) {
    try {
        $resp = Invoke-WebRequest -Uri "https://github.com/$Repo/releases/latest" `
            -MaximumRedirection 0 -UseBasicParsing -ErrorAction SilentlyContinue
    }
    catch {
        $resp = $_.Exception.Response
    }
    if ($resp -and $resp.Headers.Location) {
        $loc = $resp.Headers.Location
        if ($loc -is [array]) { $loc = $loc[0] }
        $tag = ($loc -split '/')[-1]
    }
}

if (-not $tag) {
    Write-Host "[ERROR] Could not determine latest Git for Windows version" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Latest release: $tag" -ForegroundColor Cyan

# ---- 2. Find PortableGit asset ----
$downloadUrl = $null
$assetName   = $null

# If we have the full release object, match from assets array
if ($release -and $release.assets) {
    $asset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
    if ($asset) {
        $assetName   = $asset.name
        $downloadUrl = $asset.browser_download_url
    }
}

# If we only got tag from redirect, try releases/tags API
if (-not $downloadUrl -and $tag) {
    try {
        $tagRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$tag" `
            -Headers @{ Accept = 'application/vnd.github+json' } -UseBasicParsing -ErrorAction Stop
        $release = $tagRelease
        $asset = $tagRelease.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
        if ($asset) {
            $assetName   = $asset.name
            $downloadUrl = $asset.browser_download_url
        }
    }
    catch {
        Write-Host "[WARN] releases/tags API failed: $_" -ForegroundColor Yellow
    }
}

# Ultimate fallback: convert tag to asset name manually
# v2.53.0.windows.2 → PortableGit-2.53.0.2-64-bit.7z.exe
# v2.53.0.windows.1 → PortableGit-2.53.0-64-bit.7z.exe (patch .1 is omitted)
if (-not $downloadUrl -and $tag) {
    Write-Host "[INFO] Falling back to URL construction from tag..." -ForegroundColor Yellow

    $cleanTag = $tag -replace '^v', ''
    if ($cleanTag -match '^(.+)\.windows\.(\d+)$') {
        $base  = $Matches[1]
        $patch = $Matches[2]
        if ($patch -eq '1') {
            $verStr = $base
        }
        else {
            $verStr = "$base.$patch"
        }
    }
    else {
        $verStr = $cleanTag
    }

    $assetName   = "PortableGit-$verStr-64-bit.7z.exe"
    $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$assetName"
    Write-Host "[INFO] Constructed URL: $downloadUrl" -ForegroundColor Cyan
}

if (-not $downloadUrl) {
    Write-Host "[ERROR] Could not determine download URL for PortableGit" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Asset: $assetName" -ForegroundColor Cyan

# ---- 3. Download ----
$sfxFile = "$env:TEMP\$assetName"

Write-Host "[INFO] Downloading..." -ForegroundColor Cyan
Save-WithCache -Url $downloadUrl -OutFile $sfxFile -CacheDir "git" -TimeoutSec 120

# ---- 4. SHA256 verification ----
if ($release) {
    Test-FileHash -FilePath $sfxFile -Release $release -AssetName $assetName
}
else {
    Write-Host "[WARN] Skipping SHA256 verification (no release metadata)" -ForegroundColor Yellow
}

# Sanity check file size (PortableGit SFX > 30MB)
$fileSize = (Get-Item $sfxFile).Length
if ($fileSize -lt 30MB) {
    $sizeMB = [Math]::Round($fileSize / 1MB, 1)
    Write-Host "[ERROR] Downloaded file too small (${sizeMB}MB), likely not a valid archive" -ForegroundColor Red
    Remove-Item $sfxFile -Force -ErrorAction SilentlyContinue
    exit 1
}

$sizeMB = [Math]::Round($fileSize / 1MB, 1)
Write-Host "[OK] Downloaded PortableGit (${sizeMB}MB)" -ForegroundColor Green

# ---- 5. Extract (7z SFX self-extracting) ----
Write-Host "[INFO] Extracting to $GitDir ..." -ForegroundColor Cyan

if (Test-Path $GitDir) {
    Write-Host "[INFO] Removing existing Git directory..." -ForegroundColor Cyan
    Remove-Item -Path $GitDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $GitDir) {
        cmd /c "rd /s /q `"$GitDir`"" 2>$null
    }
}

$parentDir = Split-Path $GitDir -Parent
if (-not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

# 7z SFX: -y (no prompt) -o"path" (output dir, NO space between -o and path)
$extractProc = Start-Process -FilePath $sfxFile -ArgumentList "-y", "-o`"$GitDir`"" `
    -NoNewWindow -PassThru -Wait

if ($extractProc.ExitCode -ne 0) {
    Write-Host "[ERROR] Extraction failed (exit code: $($extractProc.ExitCode))" -ForegroundColor Red
    Remove-Item $sfxFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $sfxFile -Force -ErrorAction SilentlyContinue

if (-not (Test-Path $GitExe)) {
    Write-Host "[ERROR] git.exe not found after extraction at $GitExe" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] PortableGit extracted to $GitDir" -ForegroundColor Green

# ---- 6. Run post-install script ----
$postInstall = "$GitDir\post-install.bat"
if (Test-Path $postInstall) {
    Write-Host "[INFO] Running post-install.bat..." -ForegroundColor Cyan
    $postProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$postInstall`"" `
        -NoNewWindow -PassThru -Wait
    if ($postProc.ExitCode -eq 0) {
        Write-Host "[OK] post-install.bat completed" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] post-install.bat exited with code $($postProc.ExitCode)" -ForegroundColor Yellow
    }
}

# ---- 7. Registry (third-party tool discovery) ----
# Mirrors official installer: HKCU\Software\GitForWindows
# CurrentVersion, InstallPath, LibexecPath

$gitVerRaw = (& $GitExe --version 2>$null | Out-String).Trim()
$gitVersion = $null
if ($gitVerRaw -match 'git version\s+(.+)') {
    $verStr = $Matches[1].Trim()
    # "2.53.0.windows.2" → "2.53.0.2", "2.53.0.windows.1" → "2.53.0"
    if ($verStr -match '^(.+)\.windows\.(\d+)$') {
        $base  = $Matches[1]
        $patch = $Matches[2]
        $gitVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
    }
    else {
        $gitVersion = $verStr
    }
}

$LibexecPath = "$GitDir\mingw64\libexec\git-core"

if (-not (Test-Path $RegKey)) {
    New-Item -Path $RegKey -Force | Out-Null
}

if ($gitVersion) {
    Set-ItemProperty -Path $RegKey -Name "CurrentVersion" -Value $gitVersion -Type String
}
Set-ItemProperty -Path $RegKey -Name "InstallPath" -Value $GitDir -Type String
if (Test-Path $LibexecPath) {
    Set-ItemProperty -Path $RegKey -Name "LibexecPath" -Value $LibexecPath -Type String
}

Write-Host "[OK] Registry: HKCU\Software\GitForWindows" -ForegroundColor Green
if ($gitVersion) {
    Write-Host "     CurrentVersion: $gitVersion" -ForegroundColor DarkGray
}
Write-Host "     InstallPath:    $GitDir" -ForegroundColor DarkGray
Write-Host "     LibexecPath:    $LibexecPath" -ForegroundColor DarkGray

# ---- 8. Add to PATH ----
Add-UserPath -Dir $GitCmd

if (Test-Path $GitUsrBin) {
    Add-UserPath -Dir $GitUsrBin
}

if ($env:PATH -notmatch [regex]::Escape($GitCmd)) {
    $env:PATH = "$GitCmd;$env:PATH"
}

# ---- 9. Configure Chinese environment variables for Git Bash ----
Write-Host "[INFO] Configuring Chinese environment variables for Git Bash..." -ForegroundColor Cyan

$bashrcPath = "$env:USERPROFILE\.bashrc"
$bashrcConfig = @"
export PYTHONIOENCODING=utf-8
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
"@

# Check if .bashrc exists and if our config is already there
$configExists = $false
if (Test-Path $bashrcPath) {
    $bashrcContent = Get-Content $bashrcPath -Raw -ErrorAction SilentlyContinue
    if ($bashrcContent -match 'PYTHONIOENCODING=utf-8') {
        $configExists = $true
    }
}

if (-not $configExists) {
    try {
        # Create .bashrc if it doesn't exist
        if (-not (Test-Path $bashrcPath)) {
            New-Item -Path $bashrcPath -ItemType File -Force | Out-Null
        }

        # Append our configuration
        Add-Content -Path $bashrcPath -Value $bashrcConfig -Encoding UTF8
        Write-Host "[OK] Added Chinese environment variables to $bashrcPath" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to configure .bashrc: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "[OK] Chinese environment variables already configured in .bashrc" -ForegroundColor Green
}

# ---- 10. Verify ----
Write-Host ""
Write-Host "--- Verification ---" -ForegroundColor Cyan

$gitVer = (& $GitExe --version 2>$null | Out-String).Trim()
$installedGitVersion = $null

if ($gitVer) {
    # Extract version for comparison
    if ($gitVer -match 'git version\s+(.+)') {
        $verStr = $Matches[1].Trim()
        if ($verStr -match '^(.+)\.windows\.(\d+)$') {
            $base  = $Matches[1]
            $patch = $Matches[2]
            $installedGitVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
        }
        else {
            $installedGitVersion = $verStr
        }
    }

    # Get expected version from tag
    $expectedVersion = $null
    if ($tag -match '^v?(.+)\.windows\.(\d+)$') {
        $base  = $Matches[1]
        $patch = $Matches[2]
        $expectedVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
    }
    elseif ($tag -match '^v?(.+)$') {
        $expectedVersion = $Matches[1]
    }

    if ($installedGitVersion -eq $expectedVersion) {
        Write-Host "[OK] $gitVer" -ForegroundColor Green
        Write-Host "     git.exe: $GitExe" -ForegroundColor DarkGray
        Write-Host "     ssh:     $GitUsrBin\ssh.exe" -ForegroundColor DarkGray

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

        Write-Host ""
        Write-Host "[OK] Git for Windows (Portable) installation complete!" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Version mismatch! Expected: $expectedVersion, Got: $installedGitVersion" -ForegroundColor Red

        # Rollback from backup
        if ($backupPath -and (Test-Path $backupPath)) {
            Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
            try {
                # Remove failed installation
                Remove-Item $GitDir -Recurse -Force -ErrorAction SilentlyContinue

                # Restore from backup
                Copy-Item -Path $backupPath -Destination $GitDir -Recurse -Force

                # Restore registry keys
                $oldVerRaw = (& $GitExe --version 2>$null | Out-String).Trim()
                $oldGitVersion = $null
                if ($oldVerRaw -match 'git version\s+(.+)') {
                    $verStr = $Matches[1].Trim()
                    if ($verStr -match '^(.+)\.windows\.(\d+)$') {
                        $base  = $Matches[1]
                        $patch = $Matches[2]
                        $oldGitVersion = if ($patch -eq '1') { $base } else { "$base.$patch" }
                    }
                    else {
                        $oldGitVersion = $verStr
                    }
                }

                $OldLibexecPath = "$GitDir\mingw64\libexec\git-core"
                if (-not (Test-Path $RegKey)) {
                    New-Item -Path $RegKey -Force | Out-Null
                }
                if ($oldGitVersion) {
                    Set-ItemProperty -Path $RegKey -Name "CurrentVersion" -Value $oldGitVersion -Type String
                }
                Set-ItemProperty -Path $RegKey -Name "InstallPath" -Value $GitDir -Type String
                if (Test-Path $OldLibexecPath) {
                    Set-ItemProperty -Path $RegKey -Name "LibexecPath" -Value $OldLibexecPath -Type String
                }

                Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
                Write-Host "[INFO] Backup retained at: $backupPath" -ForegroundColor Cyan
            }
            catch {
                Write-Host "[ERROR] Rollback failed: $_" -ForegroundColor Red
                Write-Host "[ERROR] Git installation may be in inconsistent state" -ForegroundColor Red
            }
        }
        else {
            Write-Host "[ERROR] No backup available, cannot rollback" -ForegroundColor Red
        }
        exit 1
    }
}
else {
    Write-Host "[ERROR] git --version failed" -ForegroundColor Red

    # Rollback from backup
    if ($backupPath -and (Test-Path $backupPath)) {
        Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
        try {
            # Remove failed installation
            Remove-Item $GitDir -Recurse -Force -ErrorAction SilentlyContinue

            # Restore from backup
            Copy-Item -Path $backupPath -Destination $GitDir -Recurse -Force

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
