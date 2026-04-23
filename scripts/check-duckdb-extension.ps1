#Requires -Version 5.1

<#
.SYNOPSIS
    Check DuckDB extensions installation status via REPL
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$defaultExtensions = @("shellfs", "httpfs")

Write-Host "--- DuckDB Extensions ---" -ForegroundColor Cyan

$duckdbExe = (Get-Command duckdb -ErrorAction SilentlyContinue).Source
if (-not $duckdbExe) {
    Write-Host "[NOT INSTALLED] duckdb CLI not found" -ForegroundColor Red
    Write-Host "  Run 'just install-duckdb' first" -ForegroundColor DarkGray
    return
}

$raw = & $duckdbExe -c "SELECT version();" 2>&1 | Out-String
$duckdbVersion = $null
if ($raw -match 'v(\d+\.\d+\.\d+)') {
    $duckdbVersion = "v$($Matches[1])"
}

Write-Host "[OK] DuckDB $duckdbVersion" -ForegroundColor Green
Write-Host "  Location:        $duckdbExe" -ForegroundColor DarkGray

# Query REPL for installed extensions
$sql = "SELECT extension_name, installed_from, install_mode FROM duckdb_extensions() WHERE installed AND extension_name IN ('shellfs','httpfs');"
$result = & $duckdbExe -c $sql 2>&1 | Out-String

$installedExts = @{}
if ($result -match 'shellfs') { $installedExts["shellfs"] = $true }
if ($result -match 'httpfs') { $installedExts["httpfs"] = $true }

foreach ($ext in $defaultExtensions) {
    if ($installedExts.ContainsKey($ext)) {
        Write-Host "  [OK] $ext" -ForegroundColor Green
    }
    else {
        Write-Host "  [MISSING] $ext" -ForegroundColor Yellow
    }
}

# Show extra community extensions not in default list
$sqlAll = "SELECT extension_name FROM duckdb_extensions() WHERE installed AND extension_name NOT IN ('autocomplete','core_functions','icu','json','parquet','shell','shellfs','httpfs');"
$resultAll = & $duckdbExe -c $sqlAll 2>&1 | Out-String
$extraNames = [regex]::Matches($resultAll, '(?m)^\s*(\w+)\s*$') |
    Where-Object { $_.Groups[1].Value -notin $defaultExtensions } |
    ForEach-Object { $_.Groups[1].Value }

foreach ($ext in $extraNames) {
    Write-Host "  [OK] $ext (extra)" -ForegroundColor DarkGray
}

Write-Host "  Extension dir:   $env:USERPROFILE\.duckdb\extensions\$duckdbVersion\windows_amd64" -ForegroundColor DarkGray
