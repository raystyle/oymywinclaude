#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Nushell and remove all registered plugins
.DESCRIPTION
    Removes plugin registrations via `nu plugin rm`, deletes all
    nu_plugin_*.exe files, then removes nu.exe via uninstall-tool.ps1.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"
$nuExe  = "$binDir\nu.exe"

# ---- 1. Remove plugin registrations ----
if (Test-Path $nuExe) {
    Write-Host "[INFO] Removing plugin registrations..." -ForegroundColor Cyan
    $pluginJson = & $nuExe -c "plugin list | to json" 2>&1
    if ($LASTEXITCODE -eq 0 -and $pluginJson) {
        try {
            $plugins = $pluginJson | ConvertFrom-Json
            foreach ($p in $plugins) {
                $output = & $nuExe -c "plugin rm $($p.name)" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Removed plugin: $($p.name)" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] Failed to remove plugin $($p.name): $output" -ForegroundColor Yellow
                }
            }
            if ($plugins.Count -eq 0) {
                Write-Host "[INFO] No plugins registered" -ForegroundColor Cyan
            }
        } catch {
            Write-Host "[WARN] Could not parse plugin list" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[INFO] nu.exe not found, skipping plugin removal" -ForegroundColor Cyan
}

# ---- 2. Remove plugin executables ----
Write-Host "[INFO] Removing plugin executables..." -ForegroundColor Cyan
$pluginExes = Get-ChildItem -Path $binDir -Filter "nu_plugin_*.exe" -File -ErrorAction SilentlyContinue
foreach ($pluginExe in $pluginExes) {
    try {
        Remove-Item -Path $pluginExe.FullName -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $($pluginExe.Name)" -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Could not remove $($pluginExe.Name): $_" -ForegroundColor Yellow
    }
}

# ---- 3. Remove nu.exe via generic uninstaller ----
Write-Host "[INFO] Uninstalling nu.exe..." -ForegroundColor Cyan
& pwsh -NoProfile -File "$PSScriptRoot\uninstall-tool.ps1" -ExeName "nu.exe" -Force:$Force

Write-Host "[OK] Nushell uninstalled" -ForegroundColor Green
