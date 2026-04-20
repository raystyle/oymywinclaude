#Requires -Version 5.1

<#
.SYNOPSIS
    Check Python LSP (Pyright) binary status [DEPRECATED]
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ""
Write-Host "--- Python LSP (Pyright) - DEPRECATED ---" -ForegroundColor Yellow
Write-Host ""
Write-Host "This check is deprecated. Python LSP is now provided by the Astral plugin (ty)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Recommended command:" -ForegroundColor Cyan
Write-Host "  just status-claude-plugin-astral" -ForegroundColor DarkGray
Write-Host ""
