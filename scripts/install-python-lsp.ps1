#Requires -Version 5.1

<#
.SYNOPSIS
    Install Python LSP (Pyright) for Claude Code [DEPRECATED]
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ""
Write-Host "--- DEPRECATED ---" -ForegroundColor Yellow
Write-Host ""
Write-Host "This script is deprecated. Python LSP is now provided by the Astral plugin (ty)." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Recommended action:" -ForegroundColor Cyan
Write-Host "  just install-claude-plugin-astral" -ForegroundColor DarkGray
Write-Host ""
Write-Host "This will install:" -ForegroundColor DarkGray
Write-Host "  - ty (Python LSP)" -ForegroundColor DarkGray
Write-Host "  - uv (Python package manager)" -ForegroundColor DarkGray
Write-Host "  - ruff (Python linter/formatter)" -ForegroundColor DarkGray
Write-Host ""
