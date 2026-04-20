#Requires -Version 5.1

<#
.SYNOPSIS
    Check markdownlint shim status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir       = "$env:USERPROFILE\.local\bin"
$shimExePath  = "$binDir\markdownlint.exe"
$shimConfPath = "$binDir\markdownlint.shim"

Write-Host "--- markdownlint ---" -ForegroundColor Cyan

if (Test-Path $shimExePath) {
    $output  = & $shimExePath --version 2>&1 | Out-String
    $version = if ($output -match 'v([\d.]+)') { $Matches[1] } else { "unknown" }
    Write-Host "[OK] $version" -ForegroundColor Green
    Write-Host "  Shim:            $shimExePath" -ForegroundColor DarkGray

    if (Test-Path $shimConfPath) {
        $shimContent = Get-Content $shimConfPath -Raw
        if ($shimContent -match 'path\s*=\s*(.+)') {
            Write-Host "  Target:          $($Matches[1].Trim())" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  Location:        .shim config not found" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-markdownlint' to install" -ForegroundColor DarkGray
}
