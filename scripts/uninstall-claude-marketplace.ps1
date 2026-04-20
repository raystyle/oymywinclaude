#Requires -Version 5.1

<#
.SYNOPSIS
    Remove official Claude Code plugins marketplace
.DESCRIPTION
    Removes the official GitHub-based plugin marketplace from Claude Code.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "--- Remove Official Claude Plugins Marketplace ---" -ForegroundColor Cyan
Write-Host ""

$possibleNames = @("anthropics/claude-plugins-official", "claude-plugins-official")

# Check if marketplace exists
Write-Host "[INFO] Checking if marketplace exists..." -ForegroundColor Cyan

try {
    $marketplaceList = & claude plugin marketplace list 2>&1
    $removed = $false

    foreach ($name in $possibleNames) {
        if ($marketplaceList -match [regex]::Escape($name)) {
            Write-Host "[INFO] Removing official marketplace: $name" -ForegroundColor Cyan

            & claude plugin marketplace remove $name 2>&1 | Out-Null

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Official marketplace removed successfully" -ForegroundColor Green
                $removed = $true
                break
            }
            else {
                Write-Host "[WARN] Failed to remove marketplace $name (exit code $LASTEXITCODE)" -ForegroundColor Yellow
            }
        }
    }

    if (-not $removed) {
        Write-Host "[INFO] Official marketplace not found" -ForegroundColor Cyan
    }
}
catch {
    Write-Host "[WARN] Could not verify marketplace status: $_" -ForegroundColor Yellow
}

Write-Host ""
