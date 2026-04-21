#Requires -Version 5.1

<#
.SYNOPSIS
    Install Nushell from raystyle/nushell-evo GitHub releases
.DESCRIPTION
    Downloads Nushell from GitHub, extracts nu.exe and plugins,
    then registers all nu_plugin_*.exe plugins with `nu plugin add`.
#>

[CmdletBinding()]
param(
    [switch]$Force,

    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$nuExe   = "$binDir\nu.exe"
$Repo    = "raystyle/nushell-evo"
$AssetPattern = '-x86_64-pc-windows-msvc\.zip$'
$CacheDir = "nushell"

# ---- 1. Resolve version & release metadata ----
Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
try {
    $release = Get-GitHubRelease -Repo $Repo
    $rawTag  = $release.tag_name
    $Version = $rawTag -replace '^v', ''
    Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow
    if (Test-Path $nuExe) {
        Write-Host "[INFO] Tool already installed, skipping version check..." -ForegroundColor Cyan
        Add-UserPath -Dir $binDir
        exit 0
    }
    else {
        Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
        exit 1
    }
}

# Match the Windows zip asset from the release
$windowsAsset = $release.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
if (-not $windowsAsset) {
    Write-Host "[ERROR] No matching Windows asset found in release $rawTag" -ForegroundColor Red
    Write-Host "       Expected pattern: *$AssetPattern" -ForegroundColor DarkGray
    exit 1
}

$resolvedArchive = $windowsAsset.name
$downloadUrl = $windowsAsset.browser_download_url
Write-Host "[INFO] Target: nu.exe $Version (asset: $resolvedArchive)" -ForegroundColor Cyan

# ---- 2. Idempotent check ----
if (Test-Path $nuExe) {
    $raw = & $nuExe --version 2>&1 | Out-String
    $installed = ''
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $installed = $Matches[1]
    }

    $upgradeCheck = Test-UpgradeRequired -Current $installed -Target $Version -ToolName "nushell" -Force:$Force

    if (-not $upgradeCheck.Required) {
        Write-Host "[OK] nu.exe $Version already installed, skipping." -ForegroundColor Green
        Write-Host "[INFO] $($upgradeCheck.Reason)" -ForegroundColor Cyan
        Add-UserPath -Dir $binDir
        exit 0
    }

    if ($installed) {
        Write-Host "[UPGRADE] $installed -> $Version" -ForegroundColor Cyan
        Write-Host "     Reason: $($upgradeCheck.Reason)" -ForegroundColor DarkGray
    }

    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor Cyan
        Write-Host "    * Backup current version" -ForegroundColor DarkGray
        Write-Host "    * Install new version" -ForegroundColor DarkGray
        Write-Host ""
        $response = Read-Host "  Continue? [Y/n]"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Upgrade cancelled by user" -ForegroundColor Cyan
            exit 0
        }
    }

    if (-not $NoBackup) {
        try {
            Write-Host "[INFO] Backing up current version..." -ForegroundColor Cyan
            Backup-ToolVersion -ToolName "nushell" -ExePath $nuExe
            Write-Host "[OK] Backup complete" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
        }
    }
}

# ---- 3. Download ----
$zipFile = "$env:TEMP\$resolvedArchive"

Write-Host "[INFO] Downloading $resolvedArchive ..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir $CacheDir
}
catch {
    Write-Host "[ERROR] Failed to download $resolvedArchive" -ForegroundColor Red
    Write-Host "       URL: $downloadUrl" -ForegroundColor DarkGray
    exit 1
}

# ---- 4. Verify SHA256 digest ----
try {
    Test-FileHash -FilePath $zipFile -Release $release -AssetName $resolvedArchive | Out-Null
}
catch {
    Write-Host "[ERROR] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. Extract ----
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
}

$extractDir = Join-Path $env:TEMP "nushell-evo-install"
if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force }

try {
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Failed to extract $resolvedArchive" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# Move nu.exe to binDir
$extractedExe = Get-ChildItem -Path $extractDir -Filter "nu.exe" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $extractedExe) {
    Write-Host "[ERROR] nu.exe not found in archive" -ForegroundColor Red
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Copy-Item -Path $extractedExe.FullName -Destination $nuExe -Force

if (-not (Test-Path $nuExe)) {
    Write-Host "[ERROR] nu.exe not found after extraction" -ForegroundColor Red
    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 6. PATH ----
Add-UserPath -Dir $binDir
Write-Host "[OK] Nushell installed: $nuExe" -ForegroundColor Green

# Move plugin executables from extracted directory
$pluginExes = Get-ChildItem -Path $extractDir -Filter "nu_plugin_*.exe" -Recurse -File -ErrorAction SilentlyContinue

# Get list of already registered plugins using -c flag
$pluginListOutput = & $nuExe -c "plugin list" 2>&1
$registeredPlugins = @($pluginListOutput | ForEach-Object { $_.Trim() } | Where-Object { $_ -match 'nu_plugin_' })

foreach ($plugin in $pluginExes) {
    $destPath = Join-Path $binDir $plugin.Name
    Copy-Item -Path $plugin.FullName -Destination $destPath -Force
    Write-Host "[OK] Copied $($plugin.Name) to $binDir" -ForegroundColor Green

    if ($registeredPlugins -notcontains $plugin.Name) {
        # Use -c flag to run plugin add command within Nushell
        $addOutput = & $nuExe -c "plugin add '$destPath'" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Registered plugin: $($plugin.Name)" -ForegroundColor Green
        }
        else {
            Write-Host "[WARN] Failed to register plugin: $($plugin.Name)" -ForegroundColor Yellow
            Write-Host "       $addOutput" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "[OK] Plugin already registered: $($plugin.Name)" -ForegroundColor Green
    }
}

# Clean up
Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

