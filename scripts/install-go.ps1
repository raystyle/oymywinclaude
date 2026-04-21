#Requires -Version 5.1

<#
.SYNOPSIS
    Install Go to D:\DevEnvs\Go from golang.google.cn (latest version).
.DESCRIPTION
    Fetches latest version from golang.google.cn API,
    downloads go{Version}.windows-amd64.zip,
    extracts to D:\DevEnvs\Go, adds to PATH,
    configures GO111MODULE and GOPROXY.
    Idempotent — safe to run multiple times.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Stop'

# ---- 0. Fetch latest version from API ----
Write-Host "[INFO] Fetching Go version info from golang.google.cn..." -ForegroundColor Cyan

try {
    $apiUrl = "https://golang.google.cn/dl/?mode=json"
    $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
    $latestVersion = ($response | Where-Object { $_.stable -eq $true } | Select-Object -First 1).version

    if (-not $latestVersion) {
        throw "Failed to determine latest stable version from API"
    }

    Write-Host "[OK] Latest stable version: $latestVersion" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to fetch version info: $_" -ForegroundColor Red
    exit 1
}

# ---- Constants ----
$GoDir = "D:\DevEnvs\Go"

# ---- 1. Find filename and SHA256 from API ----
Write-Host "[INFO] Fetching file info from API..." -ForegroundColor Cyan

try {
    $fileInfo = ($response | Where-Object { $_.version -eq $latestVersion }).files |
                Where-Object { $_.filename -match 'windows-amd64\.zip$' } |
                Select-Object -First 1

    if (-not $fileInfo) {
        throw "Failed to find windows-amd64.zip in API response"
    }

    $ZipName = $fileInfo.filename
    $expectedSha256 = $fileInfo.sha256
    Write-Host "[OK] File: $ZipName" -ForegroundColor Green
    Write-Host "[OK] SHA256: $expectedSha256" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to get file info: $_" -ForegroundColor Red
    exit 1
}

# ---- Constants that depend on API response ----
$DownloadUrl = "https://golang.google.cn/dl/$ZipName"

# ---- 2. Idempotent check ----
$goExe = "$GoDir\bin\go.exe"
if (Test-Path $goExe) {
    $currentVer = (& $goExe version 2>&1 | Out-String).Trim()
    if ($currentVer -match "go(\d+\.\d+\.\d+)") {
        $installedVersion = $matches[1]
        if ("go$installedVersion" -eq $latestVersion) {
            Show-AlreadyInstalled -Tool "Go" -Version $currentVer -Location $GoDir

            # Ensure on current PATH
            if ($env:PATH -notmatch [regex]::Escape("$GoDir\bin")) {
                $env:PATH = "$GoDir\bin;$env:PATH"
            }
            return
        }
    }
    Write-Host "[UPGRADE] Go $currentVer -> $latestVersion" -ForegroundColor Cyan
}

# ---- 3. Download (with cache) ----
$zipFile = "$env:TEMP\$ZipName"
$GoUA = "Go/$latestVersion (Windows; amd64)"
$cacheDir = "golang"
$fullCacheDir = Join-Path $script:DevSetupRoot $cacheDir
$cacheFile = Join-Path $fullCacheDir $ZipName

# Ensure cache directory exists
if (-not (Test-Path $fullCacheDir)) {
    New-Item -ItemType Directory -Path $fullCacheDir -Force | Out-Null
}

# Check cache
$cached = $false
$hashFile = "$cacheFile.sha256"

if ((Test-Path $cacheFile) -and (Test-Path $hashFile) -and $expectedSha256) {
    Write-Host "[INFO] Checking cache..." -ForegroundColor Cyan
    try {
        $storedHash = (Get-Content $hashFile -Raw).Trim()
        if ($storedHash -eq $expectedSha256) {
            $cacheSize = (Get-Item $cacheFile).Length
            $sizeStr = if ($cacheSize -ge 1MB) { "{0:N1} MB" -f ($cacheSize / 1MB) } else { "{0:N0} KB" -f ($cacheSize / 1KB) }
            Write-Host "[OK] Using cached: $ZipName ($sizeStr)" -ForegroundColor Green
            Copy-Item -Path $cacheFile -Destination $zipFile -Force
            $cached = $true
        }
        else {
            Write-Host "[WARN] Cache hash mismatch, will re-download" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[WARN] Cache check failed: $_" -ForegroundColor Yellow
    }
}

# Download if not cached
if (-not $cached) {
    Write-Host "[INFO] Downloading from $DownloadUrl..." -ForegroundColor Cyan
    try {
        $invokeParams = @{
            Uri = $DownloadUrl
            OutFile = $zipFile
            TimeoutSec = 300
            UserAgent = $GoUA
        }
        Invoke-WebRequest @invokeParams -ErrorAction Stop
        Write-Host "[OK] Downloaded to $zipFile" -ForegroundColor Green

        # Cache the downloaded file + SHA256
        try {
            Copy-Item -Path $zipFile -Destination $cacheFile -Force
            if ($expectedSha256) {
                Set-Content -Path $hashFile -Value $expectedSha256 -NoNewline -Encoding UTF8
                Write-Host "[OK] Cached: $ZipName + .sha256 -> $fullCacheDir" -ForegroundColor DarkGray
            }
            else {
                Write-Host "[OK] Cached: $ZipName -> $fullCacheDir" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host "[WARN] Failed to cache file: $_" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Verify SHA256 if we got it from API
if ($expectedSha256) {
    $actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
    if ($actualHash -eq $expectedSha256) {
        Write-Host "[OK] SHA256 verified" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] SHA256 mismatch!" -ForegroundColor Red
        Write-Host "       Expected: $expectedSha256" -ForegroundColor Red
        Write-Host "       Actual:   $actualHash" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# ---- 4. Extract ----
Write-Host "[INFO] Extracting to $GoDir..." -ForegroundColor Cyan

try {
    if (Test-Path $GoDir) {
        try {
            $backupPath = Backup-ToolVersion -ToolName "go" -ExePath $goExe
            Write-Host "[OK] Backed up to: $backupPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
        }
    }

    # Extract to temporary directory first
    $extractDir = Join-Path $env:TEMP "go-extract-$latestVersion"
    if (Test-Path $extractDir) { Remove-Item -Path $extractDir -Recurse -Force }

    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop

    # Go extracts to a "go" subdirectory, move contents to final location
    $extractedGoDir = Join-Path $extractDir "go"
    if (-not (Test-Path $extractedGoDir)) {
        throw "Expected 'go' directory not found in extracted archive"
    }

    # Remove existing installation and move new files
    if (Test-Path $GoDir) {
        Remove-Item -Path $GoDir -Recurse -Force -ErrorAction Stop
    }
    Move-Item -Path $extractedGoDir -Destination $GoDir -Force

    Remove-Item -Path $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Host "[ERROR] Extraction failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

if (-not (Test-Path "$GoDir\bin\go.exe")) {
    Write-Host "[ERROR] go.exe not found after extraction" -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Go $latestVersion extracted to $GoDir" -ForegroundColor Green

# ---- 5. Add to PATH ----
Add-UserPath -Dir "$GoDir\bin"

if ($env:PATH -notmatch [regex]::Escape("$GoDir\bin")) {
    $env:PATH = "$GoDir\bin;$env:PATH"
}

# ---- 6. Configure Go environment variables ----
$env:GO111MODULE = "on"
$env:goproxy = "https://goproxy.cn"

# Set machine-level environment variables
[Environment]::SetEnvironmentVariable("GO111MODULE", "on", "User")
[Environment]::SetEnvironmentVariable("GOPROXY", "https://goproxy.cn", "User")

Write-Host "[OK] GO111MODULE=on" -ForegroundColor Green
Write-Host "[OK] GOPROXY=https://goproxy.cn" -ForegroundColor Green

# ---- 7. Verify installation ----
$installedVer = (& "$GoDir\bin\go.exe" version 2>&1 | Out-String).Trim()
Write-Host "[OK] $installedVer" -ForegroundColor Green
Show-InstallSuccess -Component "Go" -Location $GoDir
