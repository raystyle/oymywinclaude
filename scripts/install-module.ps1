#Requires -Version 5.1

<#
.SYNOPSIS
    Install a PowerShell module from PSGallery nupkg to user-level module directories.
    Installs to both PS5 and PS7 module paths.
    Version is resolved via GitHub API (consistent with install-tool.ps1),
    package is downloaded from PSGallery (pre-built, ready to use).
.PARAMETER Repo
    GitHub repo (owner/name) for version lookup
.PARAMETER ModuleName
    Module name (must match .psd1 base name and PSGallery package ID)
.PARAMETER Version
    Version number. Leave empty to fetch latest from GitHub
.PARAMETER TagPrefix
    Tag prefix for GitHub releases, e.g. "v"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repo,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName,

    [AllowEmptyString()]
    [string]$Version = "",

    [string]$TagPrefix = "v"
)

. "$PSScriptRoot\helpers.ps1"

# ---- Helper: Validate module installation ----
function Test-ModuleValid {
    param([string]$ModDir, [string]$Name)

    $psd1 = Join-Path $ModDir "$Name.psd1"
    if (-not (Test-Path $psd1)) { return $false }

    # Extract RootModule from manifest using regex (works on both PS5 and PS7)
    try {
        $content = Get-Content -Path $psd1 -Raw -ErrorAction Stop
        $rootModule = $null
        if ($content -match "RootModule\s*=\s*['""]([^'""]+)['""]") {
            $rootModule = $Matches[1]
        }
        elseif ($content -match "ModuleToProcess\s*=\s*['""]([^'""]+)['""]") {
            $rootModule = $Matches[1]
        }
        if ($rootModule) {
            $entryPath = Join-Path $ModDir $rootModule
            if (-not (Test-Path $entryPath)) {
                Write-Host "[WARN] RootModule missing: $rootModule" -ForegroundColor Yellow
                return $false
            }
        }
    }
    catch {
        Write-Host "[WARN] Failed to read manifest: $_" -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ---- 1. Resolve version via GitHub API ----
if (-not $Version) {
    Write-Host "[INFO] Fetching latest version for $Repo..." -ForegroundColor Cyan
    try {
        $Version = Get-LatestGitHubVersion -Repo $Repo -StripVPrefix
        Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not fetch latest version (API rate limit)" -ForegroundColor Yellow

        # Check if any version of the module is already installed
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
                    break
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

# ---- 4. Download nupkg from PSGallery ----
$nupkgUrl = "https://www.powershellgallery.com/api/v2/package/$ModuleName/$Version"
$zipFile = "$env:TEMP\$ModuleName-$Version.zip"

Write-Host "[INFO] Downloading $ModuleName $Version from PSGallery..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $nupkgUrl -OutFile $zipFile -CacheDir "modules/$ModuleName"
}
catch {
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}

# ---- 5. Extract to temp ----
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

# ---- 6. Validate module manifest ----
$manifestPath = Join-Path $extractDir "$ModuleName.psd1"
if (-not (Test-Path $manifestPath)) {
    Write-Host "[ERROR] $ModuleName.psd1 not found in nupkg" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 7. Filter out NuGet packaging metadata ----
$excludeNames = @('_rels', 'package', '[Content_Types].xml')
$moduleItems = Get-ChildItem -Path $extractDir | Where-Object {
    $name = $_.Name
    if ($name -like '*.nuspec') { return $false }
    if ($name -in $excludeNames) { return $false }
    return $true
}

# ---- 8. Install to both module paths ----
$failCount = 0
foreach ($t in $targets) {
    if (Test-ModuleValid -ModDir $t.Path -Name $ModuleName) {
        Write-Host "[OK] $($t.Label) : already installed" -ForegroundColor Green
        continue
    }

    # If directory exists but invalid, clean it first
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

# ---- 9. Cleanup ----
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- 10. Verify ----
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
