#Requires -Version 5.1

<#
.SYNOPSIS
    Install mq, mq-crawl, mq-lsp and mq-check from GitHub releases
.DESCRIPTION
    Installs mq (query language), mq-crawl (crawler), mq-lsp
    (Language Server Protocol) and mq-check (syntax checker) from
    harehare/mq releases.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseUsingScopeModifierInNewRunspaces', '',
    Justification = 'Variables passed via -ArgumentList param()')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Force', Justification = 'Used in Install-MQTool function via script scope')]
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

Write-Host ""
Write-Host "--- Installing MQ Tools ---" -ForegroundColor Cyan
Write-Host ""

# Helper function to install a single tool
function Install-MQTool {
    param(
        [string]$ToolName,
        [string]$ExeName,
        [string]$ArchiveName,
        [string]$VersionFlag = "--version",
        [string]$Repo = "harehare/mq",
        [switch]$IsZip,
        [string]$DirectUrl = ""
    )

    $exePath = "$binDir\$ExeName"

    Write-Host "[INFO] Installing $ToolName..." -ForegroundColor Cyan

    # ---- 1. Resolve version (skip when DirectUrl is provided) ----
    if ($DirectUrl) {
        if ($DirectUrl -match '/v(\d+\.\d+\.\d+)/') {
            $version = $matches[1]
        } else {
            $version = "direct"
        }
        $downloadUrl = $DirectUrl
    }
    else {
        $tagPrefix = "v"
        Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
        try {
            $release = Get-GitHubRelease -Repo $Repo
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

        if (-not $version) {
            Write-Host "[ERROR] Version is null, cannot proceed" -ForegroundColor Red
            throw "Version cannot be null"
        }

        $tag = if ($rawTag.StartsWith($tagPrefix)) { $rawTag } else { $version }
        $downloadUrl = "https://github.com/$Repo/releases/download/$tag/$ArchiveName"
    }

    # ---- 2. Check if upgrade needed ----
    if (Test-Path $exePath) {
        # Get current version safely (skip if tool has no version flag)
        $installedVersion = $null
        if ($VersionFlag) {
            try {
                $job = Start-Job -ScriptBlock {
                    param($exePath, $VersionFlag)
                    & $exePath $VersionFlag
                } -ArgumentList $exePath, $VersionFlag

                $versionOutput = Wait-Job $job | Receive-Job
                Remove-Job $job

                if ($versionOutput -match '(\d+\.\d+\.\d+)') {
                    $installedVersion = $matches[1]
                }
            }
            catch {
                Write-Verbose "Version detection failed: $_"
            }
        }

        if ($installedVersion -eq $version) {
            Write-Host "[OK] $ToolName $version already installed" -ForegroundColor Green
            return
        }

        # Tool has no version flag — assume up to date if binary exists
        if ((-not $VersionFlag) -and (-not $Force)) {
            Write-Host "[OK] $ToolName already installed (no --version support)" -ForegroundColor Green
            return
        }

        if (-not $Force) {
            if ($installedVersion) {
                $upgradeRequired = Test-UpgradeRequired -Current $installedVersion -Target $version -ToolName $ExeName
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

    Write-Host "[INFO] Downloading $ArchiveName ..." -ForegroundColor Cyan
    try {
        if ($IsZip) {
            $zipFile = "$binDir\${ToolName}.zip"
            Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "mq"

            if (-not (Test-Path $zipFile)) {
                throw "Download failed - file not found"
            }

            $tempDir = Join-Path $env:TEMP "mq-install-$ToolName"
            if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
            Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force
            $extractedExe = Get-ChildItem -Path $tempDir -Filter $ExeName -Recurse | Select-Object -First 1
            if (-not $extractedExe) {
                throw "Could not find $ExeName in the archive"
            }
            Copy-Item $extractedExe.FullName -Destination "$binDir\$ExeName" -Force
            Remove-Item $tempDir -Recurse -Force
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
            $outputFile = "$binDir\$ExeName"
        }
        else {
            $outputFile = "$binDir\$ExeName"
            Save-WithCache -Url $downloadUrl -OutFile $outputFile -CacheDir "mq"

            if (-not (Test-Path $outputFile)) {
                throw "Download failed - file not found"
            }
        }
    }
    catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        throw "Download failed"
    }

    # ---- 4. Verify executable ----
    if ($VersionFlag) {
        try {
            $job = Start-Job -ScriptBlock {
                param($outputFile, $VersionFlag)
                & $outputFile $VersionFlag
            } -ArgumentList $outputFile, $VersionFlag

            Wait-Job $job | Receive-Job | Out-Null
            Remove-Job $job
        }
        catch {
            Write-Host "[WARN] Could not verify $ToolName functionality: $_" -ForegroundColor Yellow
        }
    }
    Write-Host "[OK] $ToolName is working correctly" -ForegroundColor Green

    # ---- 5. Update PATH ----
    Add-UserPath -Dir $binDir

    Write-Host "[OK] $ToolName $version installed successfully" -ForegroundColor Green
    Write-Host ""
}

# Install mq.exe
Install-MQTool -ToolName "mq" -ExeName "mq.exe" -ArchiveName "mq-x86_64-pc-windows-msvc.exe"

# Install mq-crawl.exe (direct URL, zip archive)
Install-MQTool -ToolName "mq-crawl" -ExeName "mq-crawl.exe" -IsZip -DirectUrl "https://github.com/raystyle/mq-crawl/releases/download/v0.1.0/mq-crawl-x86_64-pc-windows-msvc.zip"

# Install mq-lsp.exe
Install-MQTool -ToolName "mq-lsp" -ExeName "mq-lsp.exe" -ArchiveName "mq-lsp-x86_64-pc-windows-msvc.exe"

# Install mq-check.exe (no --version support)
Install-MQTool -ToolName "mq-check" -ExeName "mq-check.exe" -ArchiveName "mq-check-x86_64-pc-windows-msvc.exe" -VersionFlag ""

Write-Host "[OK] MQ tools installation complete" -ForegroundColor Green
