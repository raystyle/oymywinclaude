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
    $latestVersion = $null
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
Write-Host "[INFO] Fetching manifest for $latestVersion..." -ForegroundColor Cyan

try {
    $manifest = Invoke-RestMethod -Uri "$GCS_BUCKET/$latestVersion/manifest.json" -ErrorAction Stop
    $checksum = $manifest.platforms.$platform.checksum

    if (-not $checksum) {
        Write-Host "[ERROR] Platform $platform not found in manifest" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Failed to get manifest: $_" -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Force -Path $DOWNLOAD_DIR | Out-Null
$binaryPath = "$DOWNLOAD_DIR\claude-$latestVersion-$platform.exe"
$downloadUrl = "$GCS_BUCKET/$latestVersion/$platform/claude.exe"

# Check if we can reuse the existing download
$needDownload = $true
if (Test-Path $binaryPath) {
    Write-Host "[INFO] Found existing file, verifying checksum..." -ForegroundColor Cyan
    $existingHash = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()

    if ($existingHash -eq $checksum) {
        $fileSize = (Get-Item $binaryPath).Length
        if ($fileSize -ge 1MB) {
            $sizeStr = "{0:N1} MB" -f ($fileSize / 1MB)
        } else {
            $sizeStr = "{0:N0} KB" -f ($fileSize / 1KB)
        }
        Write-Host "[OK] Reusing cached: claude-$latestVersion-$platform.exe ($sizeStr)" -ForegroundColor Green
        $needDownload = $false
    } else {
        Write-Host "[WARN] Cached file checksum mismatch, re-downloading..." -ForegroundColor Yellow
        Remove-Item -Force $binaryPath
    }
}

if ($needDownload) {
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
$actualChecksum = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()

if ($actualChecksum -ne $checksum) {
    Write-Host "[ERROR] Checksum verification failed" -ForegroundColor Red
    Write-Host "       Expected: $checksum" -ForegroundColor Red
    Write-Host "       Actual:   $actualChecksum" -ForegroundColor Red
    Remove-Item -Force $binaryPath
    exit 1
}
Write-Host "[OK] SHA256 verified" -ForegroundColor Green

# ---- 6. Run built-in installer ----
Write-Host "[INFO] Running Claude Code installer (target: $Target)..." -ForegroundColor Cyan
try {
    & $binaryPath install $Target
}
catch {
    Write-Host "[ERROR] Installation failed: $_" -ForegroundColor Red
    exit 1
}

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

# ---- 8. Summary ----
Write-Host "[OK] Claude Code installation completed!" -ForegroundColor Green
Write-Host "  Use 'just setup-claude <key>' to configure API credentials" -ForegroundColor DarkGray
