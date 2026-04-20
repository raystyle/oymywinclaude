#Requires -Version 5.1

<#
.SYNOPSIS
    Check ripgrep installation status, PATH, and available updates
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\rg.exe"

Write-Host "--- ripgrep ---" -ForegroundColor Cyan

if (-not (Test-Path $exePath)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    return
}

# Current version
$raw = & $exePath --version 2>&1 | Out-String
$current = 'unknown'
if ($raw -match 'ripgrep ([\d.]+)') {
    $current = $Matches[1]
}
Write-Host "[OK] $current" -ForegroundColor Green
Write-Host "  Location:        $exePath" -ForegroundColor DarkGray

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }
