#Requires -Version 5.1

<#
.SYNOPSIS
    Show Node.js installation status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$NodeDir = "D:\DevEnvs\node"
$nodeExe = "$NodeDir\node.exe"

Write-Host "--- Node.js ---" -ForegroundColor Cyan

# ---- 1. Check if installed ----
if (-not (Test-Path $nodeExe)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-node' to install" -ForegroundColor DarkGray
    return
}

$nodeVer = (& $nodeExe --version 2>$null | Out-String).Trim()
Write-Host "[OK] $nodeVer" -ForegroundColor Green
Write-Host "  Location:        $NodeDir" -ForegroundColor DarkGray

# ---- 2. Check npm ----
$npmVer = (& "$NodeDir\npm.cmd" --version 2>$null | Out-String).Trim()
if ($npmVer) {
    Write-Host "  npm:             v$npmVer" -ForegroundColor DarkGray
}
else {
    Write-Host "  npm:             NOT FOUND" -ForegroundColor Yellow
}

# ---- 3. Check npm registry ----
$npmReg = (& "$NodeDir\npm.cmd" config get registry 2>$null | Out-String).Trim()
if ($npmReg) {
    Write-Host "  npm registry:    $npmReg" -ForegroundColor DarkGray
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $NodeDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $NodeDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }

