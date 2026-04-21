#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall mq, mq-crawl, mq-lsp and mq-check CLI tools
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

Write-Host ""
Write-Host "--- Uninstalling MQ Tools ---" -ForegroundColor Cyan
Write-Host ""

& pwsh -NoProfile -File "$PSScriptRoot\uninstall-tool.ps1" -ExeName "mq.exe" -Force:$Force
& pwsh -NoProfile -File "$PSScriptRoot\uninstall-tool.ps1" -ExeName "mq-crawl.exe" -Force:$Force
& pwsh -NoProfile -File "$PSScriptRoot\uninstall-tool.ps1" -ExeName "mq-lsp.exe" -Force:$Force
& pwsh -NoProfile -File "$PSScriptRoot\uninstall-tool.ps1" -ExeName "mq-check.exe" -Force:$Force

Write-Host "[OK] MQ tools uninstalled" -ForegroundColor Green
