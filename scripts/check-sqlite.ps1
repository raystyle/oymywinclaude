#Requires -Version 5.1

<#
.SYNOPSIS
    Check SQLite CLI tools installation status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\sqlite3.exe"

$allExes = @(
    @{ Name = "sqlite3.exe";          Desc = "CLI" },
    @{ Name = "sqldiff.exe";          Desc = "Diff" },
    @{ Name = "sqlite3_analyzer.exe"; Desc = "Analyzer" },
    @{ Name = "sqlite3_rsync.exe";    Desc = "Rsync" }
)

Write-Host "--- SQLite ---" -ForegroundColor Cyan

if (-not (Test-Path $exePath)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-sqlite' to install" -ForegroundColor DarkGray
    return
}

# Current version
$raw = & $exePath --version 2>&1 | Out-String
$current = "unknown"
if ($raw -match '(\d+\.\d+\.\d+)') {
    $current = $Matches[1]
}
Write-Host "[OK] $current" -ForegroundColor Green

# Show all tool paths
foreach ($tool in $allExes) {
    $path = Join-Path $binDir $tool.Name
    if (Test-Path $path) {
        Write-Host "  $($tool.Desc.PadRight(12)) $path" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  $($tool.Desc.PadRight(12)) not found" -ForegroundColor Yellow
    }
}

# PATH scope
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }
