#Requires -Version 5.1

<#
.SYNOPSIS
    Install Node.js to D:\DevEnvs\node from USTC mirror (fixed version).
.DESCRIPTION
    Downloads node-v{Version}-win-x64.zip from mirrors.ustc.edu.cn,
    extracts to D:\DevEnvs\node, adds to PATH, configures npmmirror registry.
    Idempotent — safe to run multiple times.
#>

[CmdletBinding()]
param(
    [string]$Version = "24.14.1"
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

# ---- Constants ----
$NodeDir      = "D:\DevEnvs\node"
$ZipName      = "node-v$Version-win-x64.zip"
$DownloadUrl  = "https://mirrors.ustc.edu.cn/node/v$Version/$ZipName"
$NpmRegistry  = "https://registry.npmmirror.com/"
$NpmrcPath    = "$env:USERPROFILE\.npmrc"

# ---- 0. Idempotent check ----
$nodeExe = "$NodeDir\node.exe"
if (Test-Path $nodeExe) {
    $currentVer = (& $nodeExe --version 2>$null | Out-String).Trim()
    if ($currentVer -eq "v$Version") {
        Show-AlreadyInstalled -Tool "Node.js" -Version $currentVer -Location $NodeDir

        # Ensure on current PATH
        if ($env:PATH -notmatch [regex]::Escape($NodeDir)) {
            $env:PATH = "$NodeDir;$env:PATH"
        }
        return
    }
    Write-Host "[UPGRADE] Node.js $currentVer -> v$Version" -ForegroundColor Cyan
}

# ---- 1. Download (with cache) ----
$zipFile = "$env:TEMP\$ZipName"
$NodeUA  = "node/$Version (Windows; x64)"
$cacheFile = Join-Path $script:DevSetupRoot "node\$ZipName"
$cacheHit = (Test-Path $cacheFile) -and (Test-Path "$cacheFile.sha256")

Save-WithCache -Url $DownloadUrl -OutFile $zipFile -CacheDir "node" -TimeoutSec 180 -UserAgent $NodeUA

# ---- 2. Verify SHA256 (first download only, cache hit uses Save-WithCache's own .sha256) ----
if (-not $cacheHit) {
    $majorVer    = ($Version -split '\.')[0]
    $shasumsUrl  = "https://mirrors.ustc.edu.cn/node/v$Version/SHASUMS256.txt"
    $expectedHash = $null

    Write-Host "[INFO] Fetching SHASUMS256.txt for verification..." -ForegroundColor Cyan
    try {
        $shasums = Invoke-RestMethod -Uri $shasumsUrl -UserAgent $NodeUA -ErrorAction Stop
        if ($shasums -match "([a-fA-F0-9]{64})\s{2}$([Regex]::Escape($ZipName))") {
            $expectedHash = $Matches[1].ToUpper()
            Write-Host "[OK] Expected SHA256: $expectedHash" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "[WARN] Could not fetch SHASUMS256.txt: $_" -ForegroundColor Yellow
    }

    if ($expectedHash) {
        $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
        if ($actualHash -eq $expectedHash) {
            Write-Host "[OK] SHA256 verified" -ForegroundColor Green
        }
        else {
            Write-Host "[FAIL] SHA256 mismatch!" -ForegroundColor Red
            Write-Host "       Expected: $expectedHash" -ForegroundColor Red
            Write-Host "       Actual:   $actualHash" -ForegroundColor Red
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }
    else {
        Write-Host "[WARN] Hash verification skipped (no SHASUMS256 available)" -ForegroundColor Yellow
    }
}

# ---- 3. Backup existing installation ----
if (Test-Path $NodeDir) {
    try {
        $backupPath = Backup-ToolVersion -ToolName "node" -ExePath $nodeExe
        Write-Host "[OK] Backed up to: $backupPath" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
    }
}

# ---- 4. Extract ----
Write-Host "[INFO] Extracting to $NodeDir..." -ForegroundColor Cyan

try {
    if (Test-Path $NodeDir) {
        Remove-Item -Path $NodeDir -Recurse -Force -ErrorAction Stop
    }

    $extractDir = Join-Path $env:TEMP "node-extract-$Version"
    if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force }

    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop

    # Move nested directory (node-v{Version}-win-x64) to final location
    $srcDir = Get-ChildItem $extractDir -Directory | Select-Object -First 1
    if (-not $srcDir) {
        throw "No directory found in extracted archive"
    }
    Move-Item -Path $srcDir.FullName -Destination $NodeDir -Force

    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "[ERROR] Extraction failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

if (-not (Test-Path "$NodeDir\node.exe")) {
    Write-Host "[ERROR] node.exe not found after extraction" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Node.js v$Version extracted to $NodeDir" -ForegroundColor Green

# ---- 5. Add to PATH ----
Add-UserPath -Dir $NodeDir

if ($env:PATH -notmatch [regex]::Escape($NodeDir)) {
    $env:PATH = "$NodeDir;$env:PATH"
}

# ---- 6. Configure npm mirror ----
$npmrcContent = "registry=$NpmRegistry"

if (Test-Path $NpmrcPath) {
    $existing = Get-Content $NpmrcPath -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'registry\s*=\s*https://registry\.npmmirror\.com') {
        Write-Host "[OK] npm registry mirror already configured" -ForegroundColor Green
    }
    else {
        $backupPath = "$NpmrcPath.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $NpmrcPath -Destination $backupPath -Force
        Write-Host "[INFO] Backed up .npmrc -> $backupPath" -ForegroundColor Cyan

        if ($existing -match '(?m)^registry\s*=') {
            $newContent = $existing -replace '(?m)^registry\s*=.*$', $npmrcContent
            Set-Content -Path $NpmrcPath -Value $newContent -NoNewline -Encoding UTF8
        }
        else {
            Add-Content -Path $NpmrcPath -Value "`n$npmrcContent" -Encoding UTF8
        }
        Write-Host "[OK] npm registry mirror configured" -ForegroundColor Green
    }
}
else {
    Set-Content -Path $NpmrcPath -Value $npmrcContent -Encoding UTF8
    Write-Host "[OK] Created .npmrc with npmmirror registry" -ForegroundColor Green
}

# ---- 7. Verify ----
Write-Host ""
Write-Host "--- Verification ---" -ForegroundColor Cyan

$nodeVer = (& "$NodeDir\node.exe" --version 2>$null | Out-String).Trim()
$npmVer  = (& "$NodeDir\npm.cmd" --version 2>$null | Out-String).Trim()
$npmReg  = (& "$NodeDir\npm.cmd" config get registry 2>$null | Out-String).Trim()

if ($nodeVer) { Write-Host "[OK] node: $nodeVer" -ForegroundColor Green }
else          { Write-Host "[WARN] node verification failed" -ForegroundColor Yellow }

if ($npmVer)  { Write-Host "[OK] npm:  v$npmVer" -ForegroundColor Green }
else          { Write-Host "[WARN] npm verification failed" -ForegroundColor Yellow }

if ($npmReg)  { Write-Host "[OK] npm registry: $npmReg" -ForegroundColor Green }
else          { Write-Host "[WARN] npm registry check failed" -ForegroundColor Yellow }

Write-Host ""
Write-Host "[OK] Node.js v$Version installation complete!" -ForegroundColor Green
