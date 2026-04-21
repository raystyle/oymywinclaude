#Requires -Version 5.1

<#
.SYNOPSIS
    Install Claude Code from official GCS distribution
.DESCRIPTION
    Downloads Claude Code binary from Google Cloud Storage, verifies checksum,
    and runs the built-in installer. Supports idempotent installation and
    version-specified installation.
.PARAMETER Target
    Install target: "stable", "latest", or a specific version (e.g. "1.0.0")
.PARAMETER Force
    Force reinstall even if already up to date
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [ValidatePattern('^(stable|latest|\d+\.\d+\.\d+(-[^\s]+)?)$')]
    [string]$Target = "latest",

    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# ---- Constants ----
$GCS_BUCKET = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
$DOWNLOAD_DIR = "$env:USERPROFILE\.claude\downloads"

# ---- 0. Platform check ----
if (-not [Environment]::Is64BitProcess) {
    Write-Host "[ERROR] Claude Code does not support 32-bit Windows" -ForegroundColor Red
    exit 1
}

if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $platform = "win32-arm64"
} else {
    $platform = "win32-x64"
}

# ---- 1. Check existing installation ----
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
$installedVersion = $null

if ($claudeCmd) {
    Write-Host "[INFO] Checking existing Claude Code installation..." -ForegroundColor Cyan
    try {
        $versionOutput = & claude --version 2>&1 | Out-String
        if ($versionOutput -match '(\d+\.\d+\.\d+)') {
            $installedVersion = $Matches[1]
            Write-Host "[OK] Claude Code found: $installedVersion" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[WARN] Claude Code command exists but cannot get version" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[INFO] Claude Code not installed" -ForegroundColor Cyan
}

# ---- 2. Get latest version from GCS ----
Write-Host "[INFO] Checking latest version..." -ForegroundColor Cyan

try {
    $latestVersion = Invoke-RestMethod -Uri "$GCS_BUCKET/latest" -ErrorAction Stop
    Write-Host "[OK] Latest version: $latestVersion" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Could not fetch latest version: $_" -ForegroundColor Yellow
    Write-Host "[INFO] Checking for cached installer..." -ForegroundColor Cyan

    # Try to find cached installer
    if (Test-Path $DOWNLOAD_DIR) {
        $cachedInstallers = Get-ChildItem -Path $DOWNLOAD_DIR -Filter "claude-*-*.exe" |
            Sort-Object LastWriteTime -Descending

        if ($cachedInstallers) {
            $latestInstaller = $cachedInstallers[0]
            if ($latestInstaller.Name -match 'claude-(\d+\.\d+\.\d+)-') {
                $latestVersion = $Matches[1]
                Write-Host "[OK] Found cached installer: $($latestInstaller.Name)" -ForegroundColor Green
            }
        }
    }

    if (-not $latestVersion) {
        Write-Host "[ERROR] No network connection and no cached installer found" -ForegroundColor Red
        Write-Host "       Please connect to internet or download Claude Code installer manually" -ForegroundColor DarkGray
        exit 1
    }
}

# ---- 3. Decide if installation/upgrade is needed ----
$needsInstall = $false

if (-not $installedVersion) {
    Write-Host "[INFO] Claude Code not installed, proceeding with installation..." -ForegroundColor Cyan
    $needsInstall = $true
}
elseif ($Force) {
    Write-Host "[INFO] Force reinstall requested..." -ForegroundColor Cyan
    $needsInstall = $true
}
elseif ($latestVersion -and $installedVersion) {
    $comparison = Compare-SemanticVersion -Current $installedVersion -Latest $latestVersion

    if ($comparison -eq -1) {
        Write-Host "[UPGRADE] $installedVersion -> $latestVersion" -ForegroundColor Cyan
        $needsInstall = $true
    }
    elseif ($comparison -eq 0) {
        Show-AlreadyInstalled -Tool "Claude Code" -Version $installedVersion
    }
    else {
        Write-Host "[OK] Claude Code $installedVersion is newer than latest ($latestVersion)" -ForegroundColor Green
    }
}

if (-not $needsInstall) {
    return
}

# ---- 4. Download binary from GCS ----
$checksum = $null

try {
    Write-Host "[INFO] Fetching manifest for $latestVersion..." -ForegroundColor Cyan
    $manifest = Invoke-RestMethod -Uri "$GCS_BUCKET/$latestVersion/manifest.json" -ErrorAction Stop
    $checksum = $manifest.platforms.$platform.checksum

    if (-not $checksum) {
        Write-Host "[WARN] Platform $platform not found in manifest" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[WARN] Could not fetch manifest, will use cached file without checksum verification" -ForegroundColor Yellow
    Write-Host "       This is safe if you downloaded from official source" -ForegroundColor DarkGray
}

New-Item -ItemType Directory -Force -Path $DOWNLOAD_DIR | Out-Null
$binaryPath = "$DOWNLOAD_DIR\claude-$latestVersion-$platform.exe"
$downloadUrl = "$GCS_BUCKET/$latestVersion/$platform/claude.exe"

# Check if we can reuse the existing download
$needDownload = $true
if (Test-Path $binaryPath) {
    $fileSize = (Get-Item $binaryPath).Length
    if ($fileSize -ge 1MB) {
        $sizeStr = "{0:N1} MB" -f ($fileSize / 1MB)
    } else {
        $sizeStr = "{0:N0} KB" -f ($fileSize / 1KB)
    }

    # If we have checksum, verify it
    if ($checksum) {
        Write-Host "[INFO] Found existing file, verifying checksum..." -ForegroundColor Cyan
        $existingHash = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()

        if ($existingHash -eq $checksum) {
            Write-Host "[OK] Reusing cached: claude-$latestVersion-$platform.exe ($sizeStr)" -ForegroundColor Green
            $needDownload = $false
        } else {
            Write-Host "[WARN] Cached file checksum mismatch, re-downloading..." -ForegroundColor Yellow
            Remove-Item -Force $binaryPath
        }
    }
    else {
        # No checksum available, but file exists and has reasonable size
        Write-Host "[OK] Reusing cached without checksum verification: claude-$latestVersion-$platform.exe ($sizeStr)" -ForegroundColor Green
        $needDownload = $false
    }
}

if ($needDownload) {
    if (-not $checksum) {
        Write-Host "[ERROR] Cannot download: no checksum available and no cached file" -ForegroundColor Red
        Write-Host "       Please check your internet connection or try again later" -ForegroundColor DarkGray
        exit 1
    }

    Write-Host "[INFO] Downloading Claude Code $latestVersion ($platform)..." -ForegroundColor Cyan
    try {
        # Temporarily enable progress bar for download
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'Continue'

        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $binaryPath -ErrorAction Stop
        }
        finally {
            $ProgressPreference = $prevProgress
        }

        Write-Host "[OK] Downloaded to: $binaryPath" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to download binary: $_" -ForegroundColor Red
        if (Test-Path $binaryPath) { Remove-Item -Force $binaryPath }
        exit 1
    }
}

# ---- 5. Verify checksum ----
if ($checksum) {
    $actualChecksum = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()

    if ($actualChecksum -ne $checksum) {
        Write-Host "[ERROR] Checksum verification failed" -ForegroundColor Red
        Write-Host "       Expected: $checksum" -ForegroundColor Red
        Write-Host "       Actual:   $actualChecksum" -ForegroundColor Red
        Remove-Item -Force $binaryPath
        exit 1
    }
    Write-Host "[OK] SHA256 verified" -ForegroundColor Green
}
else {
    Write-Host "[INFO] Skipping checksum verification (offline mode)" -ForegroundColor Cyan
}

# ---- 6. Copy binary to .local/bin ----
Write-Host "[INFO] Installing Claude Code binary..." -ForegroundColor Cyan

$binDir = "$env:USERPROFILE\.local\bin"
$targetExe = "$binDir\claude.exe"

# Ensure .local/bin exists
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

# Copy binary
try {
    Copy-Item -Path $binaryPath -Destination $targetExe -Force -ErrorAction Stop
    Write-Host "[OK] Copied to: $targetExe" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to copy binary: $_" -ForegroundColor Red
    exit 1
}

# Add to PATH
Add-UserPath -Dir $binDir

# Verify installation
Refresh-Environment
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue

if (-not $claudeCmd) {
    Write-Host "[ERROR] claude.exe not found in PATH after installation" -ForegroundColor Red
    Write-Host "       You may need to restart your shell" -ForegroundColor DarkGray
    exit 1
}
Write-Host "[OK] Claude Code binary found at $($claudeCmd.Source)" -ForegroundColor Green

# ---- 7. Setup default configuration from template ----
$settingsDir = Join-Path $env:USERPROFILE ".claude"
$settingsFile = Join-Path $settingsDir "settings.json"

$projectRoot = Split-Path $PSScriptRoot
$templatePath = Join-Path $projectRoot "templates\claude-settings.json"

if (Test-Path $settingsFile) {
    Show-AlreadyInstalled -Tool "Configuration file" -Location $settingsFile
    Write-Host "  Run 'just config-claude' to reset from template" -ForegroundColor DarkGray
}
elseif (Test-Path $templatePath) {
    Write-Host "[INFO] Setting up default configuration..." -ForegroundColor Cyan
    try {
        if (-not (Test-Path $settingsDir)) {
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        }
        Copy-Item -Path $templatePath -Destination $settingsFile -Force -ErrorAction Stop
        Write-Host "[OK] Configuration installed: $settingsFile" -ForegroundColor Green

        # Skip onboarding
        $claudeJson = Join-Path $env:USERPROFILE ".claude.json"
        @{ hasCompletedOnboarding = $true } | ConvertTo-Json | Set-Content -Path $claudeJson -Encoding UTF8
        Write-Host "[OK] Onboarding skipped" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to setup configuration: $_" -ForegroundColor Yellow
    }
}

# ---- 8. Verify installation ----
Write-Host "[INFO] Verifying Claude Code installation..." -ForegroundColor Cyan

# Refresh environment to pick up new PATH
Refresh-Environment

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[ERROR] Claude Code binary not found after installation" -ForegroundColor Red
    Write-Host "       The installation may have failed or PATH not updated" -ForegroundColor Red
    Write-Host "       Try restarting your shell and running: just status-claude-cli" -ForegroundColor DarkGray
    exit 1
}

try {
    $versionOutput = & claude --version 2>&1 | Out-String
    if ($versionOutput -match '(\d+\.\d+\.\d+)') {
        $installedVersion = $Matches[1]
        Write-Host "[OK] Claude Code $installedVersion verified at $($claudeCmd.Source)" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Claude Code found but version check failed" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[WARN] Claude Code found but not executable: $_" -ForegroundColor Yellow
}

# ---- 9. Summary ----
Write-Host "[OK] Claude Code installation completed!" -ForegroundColor Green
Write-Host "  Use 'just setup-claude <key>' to configure API credentials" -ForegroundColor DarkGray
