#Requires -Version 5.1

<#
.SYNOPSIS
    Check Go installation status, PATH, and environment variables
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host "--- Go ---" -ForegroundColor Cyan

$GoDir = "D:\DevEnvs\Go"
$goExe = "$GoDir\bin\go.exe"

if (-not (Test-Path $goExe)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-go' to install" -ForegroundColor DarkGray
    return
}

# Get version
$raw = & $goExe version 2>&1 | Out-String
if ($raw -match 'go version (go[\d.]+)') {
    $current = $Matches[1]
    Write-Host "[OK] $current" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Version detection failed" -ForegroundColor Yellow
}

Write-Host "  Location:        $GoDir" -ForegroundColor DarkGray

# PATH check
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$goBinDir = "$GoDir\bin"
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $goBinDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $goBinDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }

# Environment variables
$go111Module = [Environment]::GetEnvironmentVariable("GO111MODULE", "User")
if ($go111Module) {
    Write-Host "  GO111MODULE:     $go111Module" -ForegroundColor DarkGray
}
else {
    Write-Host "  GO111MODULE:     not set" -ForegroundColor Yellow
}

$goProxy = [Environment]::GetEnvironmentVariable("GOPROXY", "User")
if ($goProxy) {
    Write-Host "  GOPROXY:         $goProxy" -ForegroundColor DarkGray
}
else {
    Write-Host "  GOPROXY:         not set" -ForegroundColor Yellow
}
