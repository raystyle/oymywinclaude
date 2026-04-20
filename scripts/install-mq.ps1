#Requires -Version 5.1

<#
.SYNOPSIS
    Install mq, mq-crawl, mq-lsp and mq-check from GitHub releases
.DESCRIPTION
    Installs mq (query language), mq-crawl (crawler), mq-lsp
    (Language Server Protocol) and mq-check (syntax checker) from
    harehare/mq releases.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

if (-not (Test-Path (Join-Path $PSScriptRoot "helpers.ps1"))) {
    throw "Required file helpers.ps1 not found"
}
. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

$binDir = "$env:USERPROFILE\.local\bin"
$mqExePath = "$binDir\mq.exe"
$mqCrawlExePath = "$binDir\mq-crawl.exe"

Write-Host ""
Write-Host "--- Installing MQ Tools ---" -ForegroundColor Cyan
Write-Host ""

# Helper function to install a single tool
function Install-MQTool {
    param(
        [string]$ToolName,
        [string]$ExeName,
        [string]$ArchiveName
    )

    $exePath = "$binDir\$ExeName"
    $tagPrefix = "v"

    Write-Host "[INFO] Installing $ToolName..." -ForegroundColor Cyan

    # ---- 1. Resolve version ----
    Write-Host "[INFO] Fetching latest release for harehare/mq..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo "harehare/mq"
        $rawTag = $release.tag_name
        $version = if ($rawTag.StartsWith($tagPrefix)) {
            $rawTag.Substring($tagPrefix.Length)
        } else {
            $rawTag -replace '^v', ''
        }
        Write-Host "[OK] Latest version: $version" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow

        if (Test-Path $exePath) {
            Write-Host "[INFO] $ToolName already installed, skipping..." -ForegroundColor Cyan
            return
        }
        else {
            Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
            Write-Host "       Please try again later" -ForegroundColor DarkGray
            throw "Cannot determine version"
        }
    }

    # Ensure we have a version before proceeding
    if (-not $version) {
        Write-Host "[ERROR] Version is null, cannot proceed" -ForegroundColor Red
        throw "Version cannot be null"
    }

    $tag = "${tagPrefix}${version}"

    # ---- 2. Check if upgrade needed ----
    if (Test-Path $exePath) {
        # Get current version safely
        $installedVersion = $null
        try {
            $job = Start-Job -ScriptBlock {
                param($exePath)
                & $exePath "--version"
            } -ArgumentList $exePath

            $versionOutput = Wait-Job $job | Receive-Job
            Remove-Job $job

            if ($versionOutput -match '(\d+\.\d+\.\d+)') {
                $installedVersion = $matches[1]
            }
        }
        catch {
            # Version detection failed, will proceed with install
        }

        if ($installedVersion -eq $version) {
            Write-Host "[OK] $ToolName $version already installed" -ForegroundColor Green
            return
        }

        if (-not $Force) {
            # Check if version is locked
            $lockCheck = Test-VersionLocked -ToolName $ExeName -CurrentVersion $installedVersion -LatestVersion $version
            if ($lockCheck.Locked) {
                Write-Host "[INFO] $ToolName version is locked to $($lockCheck.Reason)" -ForegroundColor Cyan
                Write-Host "[INFO] Use -Force to upgrade anyway" -ForegroundColor DarkGray
                return
            }

            if ($installedVersion) {
                $upgradeRequired = Test-UpgradeRequired -CurrentVersion $installedVersion -LatestVersion $version -ToolName $ToolName
                if (-not $upgradeRequired.Required) {
                    Write-Host "[OK] $ToolName $($upgradeRequired.Reason) is up to date" -ForegroundColor Green
                    return
                }

                Write-Host "[UPGRADE] New version available: $version (current: $($upgradeRequired.Reason))" -ForegroundColor Yellow
                $response = Read-Host "Upgrade to $version? (y/N)"
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Write-Host "[INFO] Upgrade cancelled by user" -ForegroundColor Cyan
                    return
                }
            }
        }

        # Backup current version
        Write-Host "[INFO] Backing up current version..." -ForegroundColor Cyan
        try {
            $backupPath = Backup-ToolVersion -ToolName $ExeName -ExePath $exePath
            Write-Host "[OK] Backed up to: $backupPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
        }

        # Uninstall old version
        Write-Host "[INFO] Uninstalling old version..." -ForegroundColor Cyan
        Remove-Item $exePath -Force -ErrorAction SilentlyContinue
    }

    # ---- 3. Download ----
    $downloadUrl = "https://github.com/harehare/mq/releases/download/$tag/$ArchiveName"
    $outputFile = "$binDir\$ExeName"

    Write-Host "[INFO] Downloading $ArchiveName ..." -ForegroundColor Cyan
    try {
        Save-WithCache -Url $downloadUrl -OutFile $outputFile -CacheDir "mq"

        if (-not (Test-Path $outputFile)) {
            throw "Download failed - file not found"
        }

        $fileSize = (Get-Item $outputFile).Length / 1MB
        Write-Host "[OK] Downloaded ($('{0:N2}' -f $fileSize) MB)" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        throw "Download failed"
    }

    # ---- 4. Verify executable ----
    try {
        $job = Start-Job -ScriptBlock {
            param($outputFile)
            & $outputFile "--version"
        } -ArgumentList $outputFile

        Wait-Job $job | Receive-Job | Out-Null
        $exitCode = (Get-Job $job).State
        Remove-Job $job

        Write-Host "[OK] $ToolName is working correctly" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not verify $ToolName functionality: $_" -ForegroundColor Yellow
    }

    # ---- 5. Update PATH ----
    Add-UserPath -Dir $binDir

    Write-Host "[OK] $ToolName $version installed successfully" -ForegroundColor Green
    Write-Host ""
}

# Install mq.exe
Install-MQTool -ToolName "mq" -ExeName "mq.exe" -ArchiveName "mq-x86_64-pc-windows-msvc.exe"

# Install mq-crawl.exe
Install-MQTool -ToolName "mq-crawl" -ExeName "mq-crawl.exe" -ArchiveName "mq-crawl-x86_64-pc-windows-msvc.exe"

# Install mq-lsp.exe
Install-MQTool -ToolName "mq-lsp" -ExeName "mq-lsp.exe" -ArchiveName "mq-lsp-x86_64-pc-windows-msvc.exe"

# Install mq-check.exe
Install-MQTool -ToolName "mq-check" -ExeName "mq-check.exe" -ArchiveName "mq-check-x86_64-pc-windows-msvc.exe"

Write-Host "[OK] MQ tools installation complete" -ForegroundColor Green
