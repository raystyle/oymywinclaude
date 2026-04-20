#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall SQLite CLI tools
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"

$allExes = @("sqlite3.exe", "sqldiff.exe", "sqlite3_analyzer.exe", "sqlite3_rsync.exe")

Write-Host ""
Write-Host "=== Uninstall SQLite ===" -ForegroundColor Cyan
Write-Host ""

foreach ($exe in $allExes) {
    $exePath = Join-Path $binDir $exe
    if (Test-Path $exePath) {
        try {
            Remove-Item $exePath -Force -ErrorAction Stop
            Write-Host "[OK] Removed: $exe" -ForegroundColor Green
        }
        catch {
            $hresult = $_.Exception.HResult
            if ($hresult -eq -2147024864) {
                Write-Host "[WARN] $exe is locked (in use by another process)." -ForegroundColor Yellow
                Write-Host "       Close all terminals/sessions, then manually delete." -ForegroundColor Yellow
            }
            else {
                Write-Host "[WARN] Could not remove $exe : $_" -ForegroundColor Yellow
            }
        }
    }
    else {
        Write-Host "[SKIP] $exe does not exist" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "[OK] SQLite uninstalled" -ForegroundColor Green
Write-Host "     ~/.local/bin and PATH preserved (other tools may use them)" -ForegroundColor DarkGray
Write-Host ""
