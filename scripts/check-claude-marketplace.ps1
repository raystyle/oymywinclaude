#Requires -Version 5.1

<#
.SYNOPSIS
    Check official Claude plugins marketplace status
.DESCRIPTION
    Checks if the official GitHub-based plugin marketplace is registered.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

Write-Host ""
Write-Host "=== Official Claude Plugins Marketplace Status ===" -ForegroundColor Cyan
Write-Host ""

$officialMarketplace = "anthropics/claude-plugins-official"
$marketplaceName = "claude-plugins-official"

try {
    $marketplaceList = & claude plugin marketplace list 2>&1

    # Check for either the full GitHub path or just the marketplace name
    if ($marketplaceList -match [regex]::Escape($marketplaceName) -or $marketplaceList -match [regex]::Escape($officialMarketplace)) {
        Write-Host "[OK] Official marketplace: $officialMarketplace" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Official marketplace not registered" -ForegroundColor Yellow
        Write-Host "       Run 'just install-claude-marketplace' to add it" -ForegroundColor DarkGray
    }

    # Show all marketplaces
    Write-Host ""
    Write-Host "[INFO] All registered marketplaces:" -ForegroundColor Cyan
    $marketplaceList | ForEach-Object {
        if ($_ -match "^\s*(.+)$") {
            Write-Host "     $($Matches[1])" -ForegroundColor DarkGray
        }
    }
}
catch {
    Write-Host "[ERROR] Could not check marketplace status: $_" -ForegroundColor Red
}

Write-Host ""
