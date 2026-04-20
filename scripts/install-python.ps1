#Requires -Version 5.1

<#
.SYNOPSIS
    Install Python (full zip distribution) + uv + ruff + ty with USTC mirror support.
.DESCRIPTION
    Downloads Python zip from USTC mirror, verifies SHA256 against
    the official metadata JSON, extracts to D:\DevEnvs\Python,
    bootstraps pip, installs uv, ruff, and ty, configures USTC PyPI mirror for
    both pip and uv.
.PARAMETER PythonVersion
    Python version to install. Default: 3.14.4
.PARAMETER InstallDir
    Installation directory. Default: D:\DevEnvs\Python
.PARAMETER Mirror
    Mirror base URL. Default: https://mirrors.ustc.edu.cn
#>

[CmdletBinding()]
param(
    [string]$PythonVersion = "3.14.4",
    [string]$InstallDir    = "D:\DevEnvs\Python",
    [string]$Mirror        = "https://mirrors.ustc.edu.cn"
)

. "$PSScriptRoot\helpers.ps1"

# Defensive fallback: ensure version is never empty
if (-not $PythonVersion) { $PythonVersion = "3.14.4" }

$pythonExe  = "$InstallDir\python.exe"
$majorMinor = ($PythonVersion -split '\.')[0..1] -join '.'
$pipMirror  = "$Mirror/pypi/simple/"
$uvMirror   = "$Mirror/pypi/simple"

# User-Agent that passes USTC mirror's JS challenge
$UserAgent = "Python/$majorMinor (Windows; CPython) urllib/$majorMinor"

# ---- 1. Idempotent check ----
if (Test-Path $pythonExe) {
    $raw = & $pythonExe --version 2>&1 | Out-String
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $installed = $Matches[1]
        if ($installed -eq $PythonVersion) {
            Show-AlreadyInstalled -Tool "Python" -Version $PythonVersion -Location $InstallDir

            $uvExe = "$InstallDir\Scripts\uv.exe"
            if (Test-Path $uvExe) {
                Show-AlreadyInstalled -Tool "uv"
                Add-UserPath -Dir $InstallDir
                Add-UserPath -Dir "$InstallDir\Scripts"
                exit 0
            }
            else {
                Write-Host "[INFO] uv not found, will install..." -ForegroundColor Cyan
            }
        }
        else {
            Write-Host "[UPGRADE] Python $installed -> $PythonVersion" -ForegroundColor Cyan
        }
    }
}

# ---- 2. Check cache ----
$archiveName = "python-$PythonVersion-amd64.zip"
$targetId    = "pythoncore-$majorMinor-64"
$hashJsonUrl = "$Mirror/python/$PythonVersion/windows-$PythonVersion.json"
$cacheFile   = Join-Path $script:DevSetupRoot "python\$archiveName"
$hashFile    = "$cacheFile.sha256"
$cacheHit    = (Test-Path $cacheFile) -and (Test-Path $hashFile)

# ---- 3. Download Python zip ----
$mirrorUrl   = "$Mirror/python/$PythonVersion/$archiveName"
$officialUrl = "https://www.python.org/ftp/python/$PythonVersion/$archiveName"
$zipFile     = "$env:TEMP\$archiveName"

# Download with cache, multi-source fallback (mirror -> official)
$downloaded = $false
foreach ($url in @($mirrorUrl, $officialUrl)) {
    try {
        Save-WithCache -Url $url -OutFile $zipFile -CacheDir "python" -TimeoutSec 180 -UserAgent $UserAgent

        # USTC mirror may return JS challenge page (tiny response)
        $fileSize = (Get-Item $zipFile -ErrorAction Stop).Length
        if ($fileSize -lt 1MB) {
            Write-Host "[WARN] Response too small ($fileSize bytes), mirror may require browser verification. Trying next source..." -ForegroundColor Yellow
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
            Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
            continue
        }

        $downloaded = $true
        break
    }
    catch {
        Write-Host "[WARN] Failed from $url : $_" -ForegroundColor Yellow
    }
}

if (-not $downloaded) {
    Write-Host "[ERROR] All download sources failed." -ForegroundColor Red
    exit 1
}

# ---- 4. Verify SHA256 ----
$actualHash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash

if (-not $cacheHit) {
    # First download: verify against upstream metadata
    Write-Host "[INFO] Fetching hash metadata (id: $targetId)..." -ForegroundColor Cyan
    try {
        $metadata = Invoke-RestMethod -Uri $hashJsonUrl -UserAgent $UserAgent -ErrorAction Stop
        $asset = $metadata.versions | Where-Object { $_.id -eq $targetId } | Select-Object -First 1
        if ($asset -and $asset.hash -and $asset.hash.sha256) {
            $expectedHash = $asset.hash.sha256.ToUpper()
            if ($actualHash -eq $expectedHash) {
                Write-Host "[OK] SHA256 verified against metadata" -ForegroundColor Green
                # Save authoritative hash to .sha256 for future cache hits
                Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8
            }
            else {
                Write-Host "[FAIL] SHA256 mismatch!" -ForegroundColor Red
                Write-Host "       Expected: $expectedHash" -ForegroundColor Red
                Write-Host "       Actual:   $actualHash" -ForegroundColor Red
                Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
                Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
                Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
                exit 1
            }
        }
        else {
            Write-Host "[WARN] No hash in metadata, saving computed hash" -ForegroundColor Yellow
            Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8
        }
    }
    catch {
        Write-Host "[WARN] Could not fetch metadata: $_" -ForegroundColor Yellow
        Set-Content -Path $hashFile -Value $actualHash -NoNewline -Encoding UTF8
    }
}
else {
    # Cache hit: verify against saved .sha256
    $expectedHash = (Get-Content $hashFile -Raw).Trim().ToUpper()
    if ($actualHash -eq $expectedHash) {
        Write-Host "[OK] SHA256 verified against cache" -ForegroundColor Green
    }
    else {
        Write-Host "[FAIL] SHA256 mismatch (cache corrupted)!" -ForegroundColor Red
        Write-Host "       Expected: $expectedHash" -ForegroundColor Red
        Write-Host "       Actual:   $actualHash" -ForegroundColor Red
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
        Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# ---- 5. Extract ----
Write-Host "[INFO] Extracting to $InstallDir ..." -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

try {
    Expand-Archive -Path $zipFile -DestinationPath $InstallDir -Force -ErrorAction Stop
    Write-Host "[OK] Extracted" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

# ---- 6. Configure pip mirror (BEFORE bootstrapping pip) ----
# Must be done first so that any pip network operations in step 7
# (e.g. --force-reinstall to fix cpython#133626) use the mirror.
$pipConfigDir  = "$env:APPDATA\pip"
$pipConfigFile = "$pipConfigDir\pip.ini"

if (-not (Test-Path $pipConfigDir)) {
    New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
}

$needPipConfig = $true
if (Test-Path $pipConfigFile) {
    $existing = Get-Content -Path $pipConfigFile -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'ustc\.edu\.cn') {
        Write-Host "[OK] pip.ini already configured with USTC mirror" -ForegroundColor Green
        $needPipConfig = $false
    }
    else {
        $backupPath = "$pipConfigFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $pipConfigFile -Destination $backupPath -Force
        Write-Host "[WARN] Existing pip.ini backed up to: $backupPath" -ForegroundColor Yellow
    }
}

if ($needPipConfig) {
    $pipConfig = @"
[global]
index-url = $pipMirror
trusted-host = mirrors.ustc.edu.cn
"@
    Set-Content -Path $pipConfigFile -Value $pipConfig -Encoding UTF8
    Write-Host "[OK] pip.ini written with USTC mirror" -ForegroundColor Green
}

# ---- 7. Bootstrap pip ----
# Three-tier fallback strategy:
#   1. ensurepip --upgrade         (standard, offline — uses bundled wheel)
#   2. pip install --force pip     (ensurepip installed package but not exe: cpython#133626)
#   3. get-pip.py                  (full bootstrap from scratch, last resort)
# pip.ini is already in place, so attempts 2 & 3 use the USTC mirror.
$pipExe = "$InstallDir\Scripts\pip.exe"
if (-not (Test-Path $pipExe)) {
    Write-Host "[INFO] Bootstrapping pip..." -ForegroundColor Cyan

    # Attempt 1: ensurepip (offline, uses bundled wheel)
    & $pythonExe -m ensurepip --upgrade 2>&1 | Out-Null

    # Attempt 2: pip package present but Scripts/pip.exe missing — regenerate entry points
    if (-not (Test-Path $pipExe)) {
        $hasPipPkg = & $pythonExe -c "import pip; print('ok')" 2>&1 | Out-String
        if ($hasPipPkg -match 'ok') {
            Write-Host "[INFO] pip package present but Scripts/pip.exe missing (cpython#133626), regenerating..." -ForegroundColor Cyan
            & $pythonExe -m pip install --force-reinstall --no-deps pip 2>&1 | Out-Null
        }
    }

    # Attempt 3: get-pip.py
    if (-not (Test-Path $pipExe)) {
        Write-Host "[INFO] Using get-pip.py as fallback..." -ForegroundColor Cyan
        $getPip = "$env:TEMP\get-pip.py"
        Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip -UseBasicParsing -ErrorAction Stop
        & $pythonExe $getPip 2>&1 | Out-Null
        Remove-Item $getPip -Force -ErrorAction SilentlyContinue
    }

    # Final check
    if (Test-Path $pipExe) {
        Write-Host "[OK] pip installed" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] Failed to install pip" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "[OK] pip already exists" -ForegroundColor Green
}

# ---- 8. Install uv ----
$uvExe = "$InstallDir\Scripts\uv.exe"
if (-not (Test-Path $uvExe)) {
    Write-Host "[INFO] Installing uv via pip..." -ForegroundColor Cyan
    try {
        & $pythonExe -m pip install uv -q --disable-pip-version-check 2>&1 | Out-String | Out-Null
        if (Test-Path $uvExe) {
            Write-Host "[OK] uv installed" -ForegroundColor Green
        }
        else {
            Write-Host "[ERROR] uv installation failed" -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host "[ERROR] uv installation failed: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Show-AlreadyInstalled -Tool "uv"
}

# ---- 9. Configure uv mirror ----
$uvConfigDir  = "$env:APPDATA\uv"
$uvConfigFile = "$uvConfigDir\uv.toml"

if (-not (Test-Path $uvConfigDir)) {
    New-Item -ItemType Directory -Path $uvConfigDir -Force | Out-Null
}

$needUvConfig = $true
if (Test-Path $uvConfigFile) {
    $existing = Get-Content -Path $uvConfigFile -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'ustc\.edu\.cn') {
        Write-Host "[OK] uv.toml already configured with USTC mirror" -ForegroundColor Green
        $needUvConfig = $false
    }
    else {
        $backupPath = "$uvConfigFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $uvConfigFile -Destination $backupPath -Force
        Write-Host "[WARN] Existing uv.toml backed up to: $backupPath" -ForegroundColor Yellow
    }
}

if ($needUvConfig) {
    $uvConfig = @"
[[index]]
url = "$uvMirror"
default = true
"@
    Set-Content -Path $uvConfigFile -Value $uvConfig -Encoding UTF8
    Write-Host "[OK] uv.toml written with USTC mirror" -ForegroundColor Green
}

# ---- 10. Install ruff and ty via uv ----
Write-Host "[INFO] Installing ruff and ty via uv..." -ForegroundColor Cyan

try {
    & $uvExe tool install ruff -q 2>&1 | Out-Null
    Write-Host "[OK] ruff installed" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] ruff installation failed: $_" -ForegroundColor Yellow
}

try {
    & $uvExe tool install ty -q 2>&1 | Out-Null
    Write-Host "[OK] ty installed" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] ty installation failed: $_" -ForegroundColor Yellow
}

# ---- 11. Update PATH ----
Add-UserPath -Dir $InstallDir
Add-UserPath -Dir "$InstallDir\Scripts"

# ---- Done ----
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Python $PythonVersion + uv + ruff + ty installed" -ForegroundColor Green
Write-Host "  Location : $InstallDir" -ForegroundColor DarkGray
Write-Host "  pip mirror: $pipMirror" -ForegroundColor DarkGray
Write-Host "  uv mirror : $uvMirror" -ForegroundColor DarkGray
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Restart your shell, then verify:" -ForegroundColor DarkGray
Write-Host "    python --version" -ForegroundColor DarkGray
Write-Host "    pip --version" -ForegroundColor DarkGray
Write-Host "    uv --version" -ForegroundColor DarkGray
Write-Host "    ruff --version" -ForegroundColor DarkGray
Write-Host "    ty --version" -ForegroundColor DarkGray
Write-Host ""
