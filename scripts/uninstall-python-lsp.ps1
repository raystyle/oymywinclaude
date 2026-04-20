#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Python LSP (Pyright): remove pip package and Claude plugin [DEPRECATED]
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ""
Write-Host "--- DEPRECATED ---" -ForegroundColor Yellow
Write-Host ""
Write-Host "This script is deprecated. Python LSP is now provided by the Astral plugin (ty)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "To uninstall Astral plugin (uv, ruff, ty):" -ForegroundColor Cyan
Write-Host "  just uninstall-claude-plugin-astral" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To also remove pyright if you still have it installed:" -ForegroundColor DarkGray
Write-Host "  pip uninstall pyright -y" -ForegroundColor DarkGray
Write-Host ""
