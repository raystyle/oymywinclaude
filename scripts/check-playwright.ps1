#Requires -Version 5.1

<#
.SYNOPSIS
    Show Playwright CLI installation status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

Write-Host "--- Playwright CLI ---" -ForegroundColor Cyan

$shimExePath = "$env:USERPROFILE\.local\bin\playwright-cli.exe"
$shimConfigPath = "$env:USERPROFILE\.local\bin\playwright-cli.shim"

if (-not (Test-Path $shimExePath)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-playwright' to install" -ForegroundColor DarkGray
    return
}

# Try to get version
$ver = (& playwright-cli --version 2>$null | Out-String).Trim()
if ($ver) {
    Write-Host "[OK] $ver" -ForegroundColor Green
    Write-Host "  Shim:            $shimExePath" -ForegroundColor DarkGray

    # Show actual target from .shim config
    if (Test-Path $shimConfigPath) {
        $shimContent = Get-Content $shimConfigPath -Raw
        if ($shimContent -match 'args\s*=\s*(.+)') {
            $jsFile = $Matches[1].Trim()
        }

        if ($jsFile) {
            Write-Host "  Location:        $jsFile" -ForegroundColor DarkGray
        }
        else {
            Write-Host "  Location:        NOT FOUND" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  Location:        .shim config not found" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] playwright-cli shim found but version check failed" -ForegroundColor Yellow
    Write-Host "  Shim:            $shimExePath" -ForegroundColor DarkGray
}
