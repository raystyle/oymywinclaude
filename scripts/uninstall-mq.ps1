#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall mq, mq-crawl, mq-lsp and mq-check CLI tools
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"
$mqExePath = "$binDir\mq.exe"
$mqCrawlExePath = "$binDir\mq-crawl.exe"
$mqLspExePath = "$binDir\mq-lsp.exe"
$mqCheckExePath = "$binDir\mq-check.exe"

Write-Host ""
Write-Host "--- Uninstalling MQ Tools ---" -ForegroundColor Cyan
Write-Host ""

function Remove-MQTool {
    param(
        [string]$ToolName,
        [string]$ExePath
    )

    if (Test-Path $ExePath) {
        try {
            Remove-Item $ExePath -Force -ErrorAction Stop
            Write-Host "[OK] $ToolName : uninstalled" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] $ToolName : failed to remove: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[INFO] $ToolName : not installed" -ForegroundColor Cyan
    }
}

Remove-MQTool -ToolName "mq" -ExePath $mqExePath
Remove-MQTool -ToolName "mq-crawl" -ExePath $mqCrawlExePath
Remove-MQTool -ToolName "mq-lsp" -ExePath $mqLspExePath
Remove-MQTool -ToolName "mq-check" -ExePath $mqCheckExePath

Write-Host ""
Write-Host "[INFO] Note: $binDir may remain in PATH if other tools are installed there" -ForegroundColor Cyan
Write-Host ""
