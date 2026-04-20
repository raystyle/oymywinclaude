#Requires -Version 5.1

<#
.SYNOPSIS
    Configure Claude Code plugins marketplace (local only)
.DESCRIPTION
    Checks marketplace configuration but skips adding the official GitHub-based plugin
    marketplace (anthropics/claude-plugins-official). Uses local marketplace only.
    Idempotent - safe to run multiple times.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "--- Configure Claude Plugins Marketplace ---" -ForegroundColor Cyan
Write-Host ""

$officialMarketplace = "anthropics/claude-plugins-official"
$marketplaceName = "claude-plugins-official"

# Check if marketplace is already added
Write-Host "[INFO] Checking current marketplaces..." -ForegroundColor Cyan

try {
    $marketplaceList = & claude plugin marketplace list 2>&1

    # Check for either the full GitHub path or just the marketplace name
    if ($marketplaceList -match [regex]::Escape($marketplaceName) -or $marketplaceList -match [regex]::Escape($officialMarketplace)) {
        Write-Host "[OK] Official marketplace already added: $officialMarketplace" -ForegroundColor Green
    }
    else {
        # Skip adding official marketplace - use local marketplace only
        Write-Host "[INFO] Skipping official marketplace installation" -ForegroundColor Cyan
        Write-Host "[INFO] Using local marketplace only" -ForegroundColor Cyan
    }

    # Show current marketplaces
    Write-Host ""
    Write-Host "[INFO] Current marketplaces:" -ForegroundColor Cyan
    & claude plugin marketplace list 2>&1 | ForEach-Object {
        if ($_ -match "^\s*(.+)$") {
            Write-Host "     $($Matches[1])" -ForegroundColor DarkGray
        }
    }
}
catch {
    Write-Host "[WARN] Could not verify marketplace status: $_" -ForegroundColor Yellow
}

Write-Host ""
