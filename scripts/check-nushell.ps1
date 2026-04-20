#Requires -Version 5.1

<#
.SYNOPSIS
    Check Nushell installation status and registered plugins
.DESCRIPTION
    Shows nu.exe version, PATH status, and lists all registered plugins.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"
$nuExe  = "$binDir\nu.exe"

Write-Host "--- Nushell ---" -ForegroundColor Cyan

if (-not (Test-Path $nuExe)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-nushell' to install" -ForegroundColor DarkGray
    return
}

# Current version
$raw = & $nuExe --version 2>&1 | Out-String
$current = 'unknown'
if ($raw -match '(\d+\.\d+\.\d+)') {
    $current = $Matches[1]
}
Write-Host "[OK] $current" -ForegroundColor Green
Write-Host "  Location: $nuExe" -ForegroundColor DarkGray

# PATH scope
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:     $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:     not configured" -ForegroundColor Yellow }

# Registered plugins
Write-Host "  Plugins:" -ForegroundColor DarkGray
$pluginJson = & $nuExe -c "plugin list | to json" 2>&1
$pluginNames = @()
if ($LASTEXITCODE -eq 0 -and $pluginJson) {
    try {
        $plugins = $pluginJson | ConvertFrom-Json
        foreach ($p in $plugins) {
            $pluginNames += $p.name
            $pluginExe = Get-ChildItem -Path $binDir -Filter "nu_plugin_$($p.name).exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($pluginExe) {
                Write-Host "    [OK] $($p.name)" -ForegroundColor Green
            } else {
                Write-Host "    [WARN] $($p.name) (exe not found)" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "    (parse error)" -ForegroundColor DarkGray
    }
    if ($pluginNames.Count -eq 0) {
        Write-Host "    (none registered)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "    (could not query)" -ForegroundColor DarkGray
}

# Plugin executables not yet registered
$pluginExes = Get-ChildItem -Path $binDir -Filter "nu_plugin_*.exe" -File -ErrorAction SilentlyContinue
$unregistered = $pluginExes | Where-Object {
    $name = $_.BaseName -replace '^nu_plugin_', ''
    $pluginNames -notcontains $name
}
if ($unregistered) {
    Write-Host "  Unregistered:" -ForegroundColor Yellow
    foreach ($exe in $unregistered) {
        Write-Host "    $($_.BaseName)" -ForegroundColor Yellow
    }
    Write-Host "  Run 'just install-nushell' to register" -ForegroundColor DarkGray
}

# Claude MCP status
$settingsPath = "$env:USERPROFILE\.claude.json"
if ((Test-Path $settingsPath)) {
    $settings = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($settings.mcpServers.nushell) {
        Write-Host "  Claude MCP: [OK] nushell" -ForegroundColor Green
    } else {
        Write-Host "  Claude MCP: not configured" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Claude MCP: not configured" -ForegroundColor DarkGray
}
