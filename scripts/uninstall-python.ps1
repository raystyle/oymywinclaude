#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Python (full zip distribution) + uv + ruff + ty, and clean up configurations.
.DESCRIPTION
    Removes the Python installation directory, uninstalls ruff and ty,
    cleans up pip and uv mirror configurations, and removes PATH entries.
.PARAMETER InstallDir
    Installation directory. Default: D:\DevEnvs\Python
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "D:\DevEnvs\Python"
)

. "$PSScriptRoot\helpers.ps1"

$pythonExe = "$InstallDir\python.exe"

# ---- 1. Check if installed ----
if (-not (Test-Path $InstallDir)) {
    Write-Host "[OK] Python not found at $InstallDir, nothing to do." -ForegroundColor Green
    exit 0
}

if (Test-Path $pythonExe) {
    $raw = & $pythonExe --version 2>&1 | Out-String
    Write-Host "[INFO] Found: $($raw.Trim())" -ForegroundColor Cyan
    Write-Host "       Path:  $InstallDir" -ForegroundColor Cyan
}

# ---- 2. Remove PATH entries (before deleting files) ----
Remove-UserPath -Dir $InstallDir
Remove-UserPath -Dir "$InstallDir\Scripts"

# ---- 3. Remove installation directory ----
Write-Host "[INFO] Removing $InstallDir ..." -ForegroundColor Cyan
try {
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction Stop
    Write-Host "[OK] Removed $InstallDir" -ForegroundColor Green
}
catch {
    $hresult = $_.Exception.HResult
    if ($hresult -eq -2147024864) {
        Write-Host "[WARN] Some files are locked (likely python.exe or DLLs in use)." -ForegroundColor Yellow
        Write-Host "       Close all Python/PowerShell processes and manually delete:" -ForegroundColor Yellow
        Write-Host "       $InstallDir" -ForegroundColor White
        Write-Host "       Or run: cmd /c rd /s /q `"$InstallDir`"" -ForegroundColor Cyan
    }
    else {
        Write-Host "[WARN] Could not fully remove directory: $_" -ForegroundColor Yellow
        Write-Host "       Manually delete: $InstallDir" -ForegroundColor White
    }
}

# ---- 4. Clean up pip config ----
$pipConfigFile = "$env:APPDATA\pip\pip.ini"
if (Test-Path $pipConfigFile) {
    $content = Get-Content -Path $pipConfigFile -Raw -ErrorAction SilentlyContinue
    if ($content -match 'ustc\.edu\.cn') {
        Remove-Item -Path $pipConfigFile -Force
        Write-Host "[OK] Removed pip.ini" -ForegroundColor Green
    }
    else {
        Write-Host "[SKIP] pip.ini exists but was not created by us, leaving untouched." -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[OK] No pip.ini to clean up" -ForegroundColor Green
}

$pipConfigDir = "$env:APPDATA\pip"
if (Test-Path $pipConfigDir) {
    Remove-Item -Path $pipConfigDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 5. Clean up uv config ----
$uvConfigFile = "$env:APPDATA\uv\uv.toml"
if (Test-Path $uvConfigFile) {
    $content = Get-Content -Path $uvConfigFile -Raw -ErrorAction SilentlyContinue
    if ($content -match 'ustc\.edu\.cn') {
        Remove-Item -Path $uvConfigFile -Force
        Write-Host "[OK] Removed uv.toml" -ForegroundColor Green
    }
    else {
        Write-Host "[SKIP] uv.toml exists but was not created by us, leaving untouched." -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[OK] No uv.toml to clean up" -ForegroundColor Green
}

$uvConfigDir = "$env:APPDATA\uv"
if (Test-Path $uvConfigDir) {
    Remove-Item -Path $uvConfigDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ---- 6. Clean up uv cache ----
$uvCacheDir = "$env:LOCALAPPDATA\uv\cache"
if (Test-Path $uvCacheDir) {
    Write-Host "[INFO] Removing uv cache at $uvCacheDir ..." -ForegroundColor Cyan
    Remove-Item -Path $uvCacheDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] uv cache removed" -ForegroundColor Green
}

# ---- 7. Uninstall ruff and ty via uv ----
Write-Host "[INFO] Uninstalling ruff and ty via uv..." -ForegroundColor Cyan

$uvExe = "$InstallDir\Scripts\uv.exe"
if (Test-Path $uvExe) {
    try {
        & $uvExe tool uninstall ruff 2>&1 | Out-Null
        Write-Host "[OK] ruff uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] ruff uninstallation failed: $_" -ForegroundColor Yellow
    }

    try {
        & $uvExe tool uninstall ty 2>&1 | Out-Null
        Write-Host "[OK] ty uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] ty uninstallation failed: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] uv not found, skipping ruff and ty uninstallation" -ForegroundColor Yellow
}

# ---- Done ----
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Python + uv + ruff + ty uninstalled." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
