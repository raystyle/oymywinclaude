#Requires -Version 5.1

<#
.SYNOPSIS
    Display all version locks.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$lockFile = "$script:DevSetupRoot\version-lock.json"

Write-Host ""
Write-Host "=== Version Locks ===" -ForegroundColor Cyan

if (-not (Test-Path $lockFile)) {
    Write-Host "[INFO] No locks configured" -ForegroundColor DarkGray
    Write-Host "  Use 'just lock <tool>' to lock a tool version" -ForegroundColor DarkGray
    Write-Host ""
    return
}

try {
    $lockData = Get-Content -Path $lockFile -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Failed to read lock file: $_" -ForegroundColor Red
    Write-Host ""
    return
}

if ($lockData.Count -eq 0) {
    Write-Host "[INFO] No locks configured" -ForegroundColor DarkGray
    Write-Host ""
    return
}

foreach ($key in ($lockData.Keys | Sort-Object)) {
    Write-Host "  $key = $($lockData[$key])" -ForegroundColor Green
}

Write-Host ""
Write-Host "[INFO] Lock file: $lockFile" -ForegroundColor DarkGray
Write-Host "[INFO] Use 'just unlock <tool>' to remove a lock" -ForegroundColor DarkGray
Write-Host ""
