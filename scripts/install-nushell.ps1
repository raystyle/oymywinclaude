#Requires -Version 5.1

<#
.SYNOPSIS
    Install Nushell and register all bundled plugins
.DESCRIPTION
    Downloads Nushell from GitHub Release via install-tool.ps1,
    moves plugin executables from nested directories, then registers
    all nu_plugin_*.exe plugins with `nu plugin add`.
#>

[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force,

    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"
$nuExe  = "$binDir\nu.exe"

# ---- 1. Install nu.exe via generic installer (subprocess) ----
$installArgs = @(
    "-NoProfile",
    "-File", "$PSScriptRoot\install-tool.ps1",
    "-Repo", "nushell/nushell",
    "-ExeName", "nu.exe",
    "-ArchiveName", "nu-{version}-x86_64-pc-windows-msvc.zip",
    "-CacheDir", "nushell"
)
if ($Version)  { $installArgs += @("-Version", $Version) }
if ($Force)    { $installArgs += "-Force" }
if ($NoBackup) { $installArgs += "-NoBackup" }

Write-Host "[INFO] Installing Nushell..." -ForegroundColor Cyan
& pwsh @installArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Nushell installation failed (exit code: $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $nuExe)) {
    Write-Host "[ERROR] nu.exe not found after installation" -ForegroundColor Red
    exit 1
}

# ---- 2. Move plugin executables from nested directories ----
$nestedPlugins = Get-ChildItem -Path $binDir -Filter "nu_plugin_*.exe" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -ne $binDir }

foreach ($plugin in $nestedPlugins) {
    $destPath = Join-Path $binDir $plugin.Name
    Move-Item -Path $plugin.FullName -Destination $destPath -Force
    Write-Host "[OK] Moved $($plugin.Name) to $binDir" -ForegroundColor Green
}

# Clean up empty nested directories created by zip extraction
Get-ChildItem -Path $binDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "^nu-" } |
    ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

# ---- 3. Register all plugins ----
$pluginExes = Get-ChildItem -Path $binDir -Filter "nu_plugin_*.exe" -File -ErrorAction SilentlyContinue
if ($pluginExes.Count -eq 0) {
    Write-Host "[WARN] No plugin executables found in $binDir" -ForegroundColor Yellow
    Write-Host "[OK] Nushell installed (no plugins)" -ForegroundColor Green
    exit 0
}

Write-Host "[INFO] Registering $($pluginExes.Count) plugin(s)..." -ForegroundColor Cyan
$registered = 0
$failed = 0

foreach ($pluginExe in $pluginExes) {
    $pluginName = $pluginExe.BaseName -replace '^nu_plugin_', ''
    $pluginPath = $pluginExe.FullName -replace '\\', '/'
    $output = & $nuExe -c "plugin add '$pluginPath'" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Plugin registered: $pluginName" -ForegroundColor Green
        $registered++
    } else {
        Write-Host "[WARN] Failed to register $pluginName`: $output" -ForegroundColor Yellow
        $failed++
    }
}

Write-Host "[OK] Nushell installed: $registered plugin(s) registered" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "[WARN] $failed plugin(s) failed to register" -ForegroundColor Yellow
}
