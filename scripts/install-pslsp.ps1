#Requires -Version 5.1

<#
.SYNOPSIS
    Install PowerShellEditorServices module from GitHub Releases to both PS5 and PS7.
.DESCRIPTION
    Downloads the release zip from GitHub, extracts the module, and installs to both
    WindowsPowerShell and PowerShell module directories. Uses shared helpers for
    version resolution, caching, and validation.
.PARAMETER Version
    Version number. Leave empty to fetch latest from GitHub
#>

[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Version = ""
)

. "$PSScriptRoot\helpers.ps1"

$Repo = "PowerShell/PowerShellEditorServices"
$ModuleName = "PowerShellEditorServices"
$ArchiveName = "PowerShellEditorServices.zip"

# ---- Helper: Validate module installation ----
function Test-ModuleValid {
    param([string]$ModDir, [string]$Name)

    $psd1 = Join-Path $ModDir "$Name.psd1"
    if (-not (Test-Path $psd1)) { return $false }

    try {
        $content = Get-Content -Path $psd1 -Raw -ErrorAction Stop
        $rootModule = $null
        if ($content -match "RootModule\s*=\s*['`"]([^'`"]+)['`"]") {
            $rootModule = $Matches[1]
        }
        elseif ($content -match "ModuleToProcess\s*=\s*['`"]([^'`"]+)['`"]") {
            $rootModule = $Matches[1]
        }
        if ($rootModule) {
            $entryPath = Join-Path $ModDir $rootModule
            if (-not (Test-Path $entryPath)) {
                return $false
            }
        }
    }
    catch {
        return $false
    }
    return $true
}

# ---- 1. Resolve version via GitHub API ----
if (-not $Version) {
    Write-Host "[INFO] Fetching latest version for $Repo..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo
        $Version = $release.tag_name -replace '^v', ''
        Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow

        # Check if any version is already installed in either path
        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        $anyInstalled = $false
        foreach ($modBase in @(
            "$myDocs\WindowsPowerShell\Modules\$ModuleName",
            "$myDocs\PowerShell\Modules\$ModuleName"
        )) {
            if (Test-Path $modBase) {
                $latest = Get-ChildItem $modBase -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) {
                    Write-Host "[INFO] $ModuleName $($latest.Name) already installed, skipping." -ForegroundColor Cyan
                    $anyInstalled = $true
                }
            }
        }

        if ($anyInstalled) { return }

        Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
        Write-Host "       Please try again later or specify version with -Version parameter" -ForegroundColor DarkGray
        exit 1
    }
}

Write-Host "[INFO] Target: $ModuleName $Version" -ForegroundColor Cyan

# ---- 2. Determine module paths ----
$myDocs = [Environment]::GetFolderPath('MyDocuments')
$ps5ModDir = "$myDocs\WindowsPowerShell\Modules\$ModuleName\$Version"
$ps7ModDir = "$myDocs\PowerShell\Modules\$ModuleName\$Version"

$targets = @(
    @{ Path = $ps5ModDir; Label = "PS5" }
    @{ Path = $ps7ModDir; Label = "PS7" }
)

# ---- 3. Idempotent check ----
$allInstalled = $true
foreach ($t in $targets) {
    if (-not (Test-ModuleValid -ModDir $t.Path -Name $ModuleName)) {
        $allInstalled = $false
        break
    }
}
if ($allInstalled) {
    Write-Host "[OK] $ModuleName $Version already installed in both PS5 and PS7, skipping." -ForegroundColor Green
    return
}

# ---- 4. Download release zip from GitHub ----
$downloadUrl = "https://github.com/$Repo/releases/download/v$Version/$ArchiveName"
$zipFile = Join-Path $env:TEMP "$ModuleName-$Version.zip"

Write-Host "[INFO] Downloading $ArchiveName..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "modules/$ModuleName"
}
catch {
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}

# ---- 5. Extract to temp ----
$extractDir = Join-Path $env:TEMP "$ModuleName-$Version-extract"
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force
}
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $extractDir)
}
catch {
    Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 6. Validate extracted module ----
# GitHub release zip contains a top-level PowerShellEditorServices directory
$extractedModuleDir = Join-Path $extractDir $ModuleName
if (-not (Test-Path $extractedModuleDir)) {
    Write-Host "[ERROR] $ModuleName directory not found in archive" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

$manifestPath = Join-Path $extractedModuleDir "$ModuleName.psd1"
if (-not (Test-Path $manifestPath)) {
    Write-Host "[ERROR] $ModuleName.psd1 not found in archive" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Collect items from the extracted module directory
$moduleItems = Get-ChildItem -Path $extractedModuleDir

# ---- 7. Install to both module paths ----
$failCount = 0
foreach ($t in $targets) {
    if (Test-ModuleValid -ModDir $t.Path -Name $ModuleName) {
        Write-Host "[OK] $($t.Label) : already installed" -ForegroundColor Green
        continue
    }

    if (Test-Path $t.Path) {
        Remove-Item -Path $t.Path -Recurse -Force -ErrorAction SilentlyContinue
    }

    try {
        New-Item -ItemType Directory -Path $t.Path -Force | Out-Null
        foreach ($item in $moduleItems) {
            if ($item.PSIsContainer) {
                Copy-Item -Path $item.FullName -Destination "$($t.Path)\$($item.Name)" -Recurse -Force -ErrorAction Stop
            }
            else {
                Copy-Item -Path $item.FullName -Destination $t.Path -Force -ErrorAction Stop
            }
        }
        Write-Host "[OK] $($t.Label) : installed to $($t.Path)" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] $($t.Label) : install failed - $_" -ForegroundColor Red
        $failCount++
    }
}

# ---- 8. Cleanup ----
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- 9. Verify ----
foreach ($t in $targets) {
    if (Test-ModuleValid -ModDir $t.Path -Name $ModuleName) {
        Write-Host "[OK] $($t.Label) verified: $($t.Path)" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] $($t.Label) verification failed: $($t.Path)" -ForegroundColor Red
        $failCount++
    }
}

if ($failCount -gt 0) {
    Write-Host "[WARN] $failCount target(s) failed. Re-run to retry." -ForegroundColor Yellow
    exit 1
}
