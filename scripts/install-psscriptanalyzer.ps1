#Requires -Version 5.1

<#
.SYNOPSIS
    Install PSScriptAnalyzer module from GitHub Releases.
.DESCRIPTION
    Downloads PSScriptAnalyzer nupkg from GitHub Releases, extracts and
    installs to both PS5 and PS7 user module directories.
    Version is resolved via GitHub API (consistent with install-tool.ps1).
#>

[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

$Repo       = "PowerShell/PSScriptAnalyzer"
$ModuleName = "PSScriptAnalyzer"

# ---- Helper: Validate module installation ----
function Test-ModuleValid {
    param([string]$ModDir, [string]$Name)

    $psd1 = Join-Path $ModDir "$Name.psd1"
    if (-not (Test-Path $psd1)) { return $false }

    try {
        $content = Get-Content -Path $psd1 -Raw -ErrorAction Stop
        $rootModule = $null
        if ($content -match "RootModule\s*=\s*['""]([^'""]+)['""]") {
            $rootModule = $Matches[1]
        }
        if ($rootModule) {
            $entryPath = Join-Path $ModDir $rootModule
            if (-not (Test-Path $entryPath)) { return $false }
        }
    }
    catch { return $false }
    return $true
}

# ---- 1. Resolve version via GitHub API ----
if (-not $Version) {
    Write-Host "[INFO] Fetching latest version for $Repo..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo
        $rawTag  = $release.tag_name
        $Version = $rawTag -replace '^v', ''
        $tag     = $rawTag
        Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow

        # Check if any version is already installed
        $myDocs = [Environment]::GetFolderPath('MyDocuments')
        foreach ($modBase in @(
            "$myDocs\WindowsPowerShell\Modules\$ModuleName",
            "$myDocs\PowerShell\Modules\$ModuleName"
        )) {
            if (Test-Path $modBase) {
                $latest = Get-ChildItem $modBase -Directory -ErrorAction SilentlyContinue |
                    Sort-Object Name -Descending | Select-Object -First 1
                if ($latest) {
                    Write-Host "[INFO] $ModuleName $($latest.Name) already installed, skipping." -ForegroundColor Cyan
                    return
                }
            }
        }

        Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
        exit 1
    }
}
else {
    $tag = "v$Version"
}

Write-Host "[INFO] Target: $ModuleName $Version" -ForegroundColor Cyan

# ---- 2. Determine module paths ----
$myDocs   = [Environment]::GetFolderPath('MyDocuments')
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
if ($allInstalled -and -not $Force) {
    Write-Host "[OK] $ModuleName $Version already installed in both PS5 and PS7, skipping." -ForegroundColor Green
    return
}

# ---- 4. Download nupkg from GitHub Releases ----
$nupkgName  = "$ModuleName.$Version.nupkg"
$downloadUrl = "https://github.com/$Repo/releases/download/$tag/$nupkgName"
$zipFile    = "$env:TEMP\$nupkgName"

Write-Host "[INFO] Downloading $nupkgName from GitHub Releases..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "modules/$ModuleName"
}
catch {
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}

# ---- 5. Verify SHA256 ----
try {
    Test-FileHash -FilePath $zipFile -Release $release -AssetName $nupkgName
}
catch {
    Write-Host "[WARN] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ---- 6. Extract to temp ----
$extractDir = "$env:TEMP\$ModuleName-extract"
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force
}
try {
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 7. Validate module manifest ----
$manifestPath = Join-Path $extractDir "$ModuleName.psd1"
if (-not (Test-Path $manifestPath)) {
    Write-Host "[ERROR] $ModuleName.psd1 not found in nupkg" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 8. Filter out NuGet packaging metadata ----
$excludeNames = @('_rels', 'package', '[Content_Types].xml')
$moduleItems = Get-ChildItem -Path $extractDir | Where-Object {
    $name = $_.Name
    if ($name -like '*.nuspec') { return $false }
    if ($name -in $excludeNames) { return $false }
    return $true
}

# ---- 9. Install to both module paths ----
$failCount = 0
foreach ($t in $targets) {
    if (Test-ModuleValid -ModDir $t.Path -Name $ModuleName) {
        Write-Host "[OK] $($t.Label) : already installed" -ForegroundColor Green
        continue
    }

    if (Test-Path $t.Path) {
        Write-Host "[INFO] $($t.Label) : removing invalid installation..." -ForegroundColor Cyan
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

# ---- 10. Cleanup ----
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- 11. Verify ----
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

Write-Host ""
Show-InstallComplete -Tool $ModuleName -Version $Version
