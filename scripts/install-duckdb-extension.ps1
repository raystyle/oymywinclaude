#Requires -Version 5.1

<#
.SYNOPSIS
    Install DuckDB extensions via DuckDB REPL INSTALL command.
.DESCRIPTION
    Uses DuckDB's native INSTALL mechanism to fetch extensions.
    Core extensions (httpfs) from core repo, community extensions (shellfs) from community repo.
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
Refresh-Environment

Write-Host ""
Write-Host "--- Installing DuckDB Extensions ---" -ForegroundColor Cyan
Write-Host ""

$duckdbExe = (Get-Command duckdb -ErrorAction SilentlyContinue).Source
if (-not $duckdbExe) {
    Write-Host "[ERROR] duckdb is not installed" -ForegroundColor Red
    Write-Host "       Run 'just install-duckdb' first" -ForegroundColor DarkGray
    exit 1
}

$raw = & $duckdbExe -c "SELECT version();" 2>&1 | Out-String
if ($raw -match 'v(\d+\.\d+\.\d+)') {
    $duckdbVersion = "v$($Matches[1])"
}
else {
    Write-Host "[ERROR] Could not detect DuckDB version" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] DuckDB version: $duckdbVersion" -ForegroundColor Cyan

$communityExtensions = @("shellfs")
$installedCount = 0
$skippedCount = 0

foreach ($ext in $Extensions) {
    if ($ext -in $communityExtensions) {
        $sql = "INSTALL $ext FROM community;"
    }
    else {
        $sql = "INSTALL $ext;"
    }

    if ($Force) {
        $sql = $sql -replace 'INSTALL', 'FORCE INSTALL'
    }

    Write-Host "[INFO] Installing $ext ..." -ForegroundColor Cyan
    $result = & $duckdbExe -c $sql 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $ext installed" -ForegroundColor Green
        $installedCount++
    }
    else {
        # "already installed" is still success
        if ($result -match 'already') {
            Write-Host "[OK] $ext already installed" -ForegroundColor Green
            $skippedCount++
        }
        else {
            Write-Host "[ERROR] Failed to install ${ext}: $result" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "[OK] DuckDB extensions: $installedCount installed, $skippedCount skipped" -ForegroundColor Green
