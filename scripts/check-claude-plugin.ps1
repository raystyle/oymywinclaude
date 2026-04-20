#Requires -Version 5.1

<#
.SYNOPSIS
    Check Claude Code LSP plugin status (registration + language server availability)
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("all", "typescript", "powershell", "astral", "mq-lsp", "nushell", "processing-markdown", "skill-creator", "")]
    [string]$PluginType = "all"
)

. "$PSScriptRoot\helpers.ps1"

$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"

function Show-PluginStatus {
    param(
        [string]$Label,
        [string]$PluginId,
        [string]$BinaryCheck,
        [string]$ModuleCheck
    )

    Write-Host "[$Label]" -ForegroundColor Cyan

    # Check binary / module
    if ($BinaryCheck) {
        $cmd = Get-Command $BinaryCheck -ErrorAction SilentlyContinue
        if ($cmd) {
            Write-Host "  Binary   : $($cmd.Source)" -ForegroundColor Green
        }
        else {
            Write-Host "  Binary   : NOT found" -ForegroundColor Yellow
        }
    }
    if ($ModuleCheck) {
        $m = Get-Module -ListAvailable $ModuleCheck -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
        if ($m) {
            Write-Host "  Module   : $($m.Version)" -ForegroundColor Green
        }
        else {
            Write-Host "  Module   : NOT found" -ForegroundColor Yellow
        }
    }

    # Check plugin registration
    $output = & claude plugin list 2>&1
    if ($output -match [regex]::Escape($PluginId)) {
        Write-Host "  Plugin   : enabled" -ForegroundColor Green
    }
    else {
        Write-Host "  Plugin   : NOT registered" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($PluginType -eq "all" -or $PluginType -eq "typescript") {
    Show-PluginStatus -Label "TypeScript LSP" -PluginId "typescript-lsp@local-dev" -BinaryCheck "typescript-language-server"
}

if ($PluginType -eq "all" -or $PluginType -eq "powershell") {
    Show-PluginStatus -Label "PowerShell LSP (PES)" -PluginId "powershell-lsp@local-dev" -ModuleCheck "PowerShellEditorServices"
}

if ($PluginType -eq "all" -or $PluginType -eq "astral") {
    Show-PluginStatus -Label "Astral (uv, ruff, ty)" -PluginId "astral@local-dev" -BinaryCheck "uvx"
}

if ($PluginType -eq "all" -or $PluginType -eq "skill-creator") {
    Show-PluginStatus -Label "Skill Creator" -PluginId "skill-creator@local-dev"
}

if ($PluginType -eq "all" -or $PluginType -eq "mq-lsp") {
    Show-PluginStatus -Label "mq-lsp" -PluginId "mq-lsp@local-dev" -BinaryCheck "mq-lsp"
}

if ($PluginType -eq "all" -or $PluginType -eq "nushell") {
    Show-PluginStatus -Label "Nushell LSP" -PluginId "nushell-lsp@local-dev" -BinaryCheck "nu"
}

if ($PluginType -eq "all" -or $PluginType -eq "processing-markdown") {
    Show-PluginStatus -Label "Processing Markdown" -PluginId "processing-markdown@local-dev" -BinaryCheck "mq"
}
