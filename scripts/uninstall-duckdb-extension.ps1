#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall DuckDB extensions by removing .duckdb_extension files.
.DESCRIPTION
    DuckDB has no UNINSTALL command, so this removes extension binaries from the extension directory.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Extensions = @("shellfs", "httpfs"),

    [switch]$Force
)

if (-not (Test-Path (Join-Path $PSScriptRoot "helpers.ps1"))) {
    throw "Required file helpers.ps1 not found"
}
. "$PSScriptRoot\helpers.ps1"

Write-Host ""
Write-Host "--- Uninstalling DuckDB Extensions ---" -ForegroundColor Cyan
Write-Host ""

$duckdbExe = (Get-Command duckdb -ErrorAction SilentlyContinue).Source
if (-not $duckdbExe) {
    Write-Host "[INFO] duckdb is not installed, cannot detect extension directory" -ForegroundColor Cyan
    return
}

$raw = & $duckdbExe -c "SELECT version();" 2>&1 | Out-String
$duckdbVersion = $null
if ($raw -match 'v(\d+\.\d+\.\d+)') {
    $duckdbVersion = "v$($Matches[1])"
}

if (-not $duckdbVersion) {
    Write-Host "[WARN] Could not detect DuckDB version" -ForegroundColor Yellow
    return
}

$extDir = "$env:USERPROFILE\.duckdb\extensions\$duckdbVersion\windows_amd64"
$removedCount = 0

foreach ($ext in $Extensions) {
    $extFile = "$extDir\$ext.duckdb_extension"
    if (Test-Path $extFile) {
        Remove-Item $extFile -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $extFile)) {
            Write-Host "[OK] Removed $ext" -ForegroundColor Green
            $removedCount++
        }
        else {
            Write-Host "[WARN] Could not remove $ext" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[SKIP] $ext not found" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "[OK] DuckDB extensions: $removedCount removed" -ForegroundColor Green
