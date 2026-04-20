#Requires -Version 5.1

<#
.SYNOPSIS
    Unregister Claude Code LSP plugins (plugin only, does NOT remove language servers)
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("all", "typescript", "powershell", "astral", "skill-creator", "")]
    [string]$PluginType = "all"
)

. "$PSScriptRoot\helpers.ps1"

$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"

Write-Host ""
Write-Host "--- Unregister Claude Code Plugins ---" -ForegroundColor Cyan
Write-Host ""

function Test-ClaudeAvailable {
    return [bool](Get-Command claude -ErrorAction SilentlyContinue)
}

function Unregister-Plugin {
    param([string]$PluginId)
    if (-not (Test-ClaudeAvailable)) {
        Write-Host "[INFO] $PluginId : not installed (claude not found)" -ForegroundColor Cyan
        return
    }
    $output = & claude plugin list 2>&1
    if ($output -match [regex]::Escape($PluginId)) {
        & claude plugin uninstall $PluginId *>$null
        Write-Host "[OK] $PluginId : unregistered" -ForegroundColor Green
    }
    else {
        Write-Host "[INFO] $PluginId : not installed" -ForegroundColor Cyan
    }
}

if ($PluginType -eq "all" -or $PluginType -eq "typescript") {
    Unregister-Plugin "typescript-lsp@local-dev"
}

if ($PluginType -eq "all" -or $PluginType -eq "astral") {
    Unregister-Plugin "astral@local-dev"
}

if ($PluginType -eq "all" -or $PluginType -eq "powershell") {
    Unregister-Plugin "powershell-lsp@local-dev"
}

if ($PluginType -eq "all" -or $PluginType -eq "skill-creator") {
    Unregister-Plugin "skill-creator@local-dev"
}

# Remove local-dev marketplace (only when uninstalling all or last plugin)
if ($PluginType -eq "all") {
    # Remove local-dev marketplace
    if (-not (Test-ClaudeAvailable)) {
        Write-Host "[INFO] local-dev marketplace : not found (claude not found)" -ForegroundColor Cyan
    }
    else {
        try {
            $output = & claude plugin list 2>&1
            if ($output -match "local-dev") {
                & claude plugin marketplace remove local-dev *>$null
                Write-Host "[OK] local-dev marketplace : removed" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "[WARN] Could not remove marketplace" -ForegroundColor DarkGray
        }
    }
}

Write-Host ""
