#Requires -Version 5.1

<#
.SYNOPSIS
    Register Claude Code LSP plugins (plugin only, no binary installation)
.DESCRIPTION
    Checks if language server binaries exist (warn only), then registers
    plugins via 'claude plugin install'. Does NOT install language servers.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("all", "typescript", "powershell", "astral", "mq-lsp", "nushell", "skill-creator")]
    [string]$PluginType = "all"
)

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"

Write-Host ""
Write-Host "--- Register Claude Code Plugins ---" -ForegroundColor Cyan
Write-Host ""

function Test-Binary {
    param([string]$Label, [string]$Command)
    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK] $Label : $($cmd.Source)" -ForegroundColor Green
        return $true
    }
    Write-Host "[WARN] $Label not found — plugin won't work without it" -ForegroundColor Yellow
    return $false
}

function Enable-Plugin {
    param([string]$PluginId, [string[]]$ListOutput)
    $output = if ($ListOutput) { $ListOutput -join "`n" } else { & claude plugin list 2>&1 }
    $escaped = [regex]::Escape($PluginId)

    # Check if plugin is present in list (registered = enabled)
    if ($output -match $escaped) {
        Write-Host "[OK] $PluginId : already enabled" -ForegroundColor Green
        return $true
    }

    # Try to enable the plugin
    $enableOutput = & claude plugin enable $PluginId 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] $PluginId : enabled" -ForegroundColor Green
        return $true
    }
    else {
        # Check if it was actually enabled despite the exit code
        $checkOutput = & claude plugin list 2>&1
        if ($checkOutput -match $escaped) {
            Write-Host "[OK] $PluginId : enabled" -ForegroundColor Green
            return $true
        }
        Write-Host "[WARN] $PluginId : enable failed" -ForegroundColor Yellow
        return $false
    }
}

function Register-Plugin {
    param([string]$PluginId)
    $output = & claude plugin list 2>&1
    $escaped = [regex]::Escape($PluginId)
    if ($output -match $escaped) {
        Write-Host "[OK] $PluginId : already registered" -ForegroundColor Green
        [void](Enable-Plugin $PluginId -ListOutput $output)
        return $true
    }
    else {
        $installOutput = & claude plugin install $PluginId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] $PluginId : registered" -ForegroundColor Green
            [void](Enable-Plugin $PluginId)
            return $true
        }
        elseif ($installOutput -match "not found in marketplace") {
            Write-Host "[WARN] $PluginId : plugin not available in marketplace (skipped)" -ForegroundColor Yellow
            return $false
        }
        else {
            Write-Host "[ERROR] $PluginId : install failed (exit code $LASTEXITCODE)" -ForegroundColor Red
            Write-Host "       Output: $installOutput" -ForegroundColor DarkGray
            return $false
        }
    }
}

# ---- TypeScript LSP ----
if ($PluginType -eq "all" -or $PluginType -eq "typescript") {
    Write-Host "[INFO] TypeScript LSP..." -ForegroundColor Cyan
    [void](Test-Binary "typescript-language-server" "typescript-language-server")

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "typescript-lsp@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "typescript-lsp@local-dev")
        }
        else {
            Write-Host "[OK] typescript-lsp@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- PowerShell LSP ----
if ($PluginType -eq "all" -or $PluginType -eq "powershell") {
    Write-Host "[INFO] PowerShell LSP..." -ForegroundColor Cyan

    # Check PES module
    $pes = Get-Module -ListAvailable PowerShellEditorServices -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending | Select-Object -First 1
    if ($pes) {
        Write-Host "[OK] PowerShellEditorServices $($pes.Version)" -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] PowerShellEditorServices not found — plugin won't work" -ForegroundColor Yellow
        Write-Host "       Run 'just install-pses' to install." -ForegroundColor DarkGray
    }

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "powershell-lsp@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "powershell-lsp@local-dev")
        }
        else {
            Write-Host "[OK] powershell-lsp@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- Astral (uv, ruff, ty) ----
if ($PluginType -eq "all" -or $PluginType -eq "astral") {
    Write-Host "[INFO] Astral (uv, ruff, ty)..." -ForegroundColor Cyan
    [void](Test-Binary "uvx" "uvx")
    [void](Test-Binary "ruff" "ruff")

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "astral@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "astral@local-dev")
        }
        else {
            Write-Host "[OK] astral@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- Skill Creator ----
if ($PluginType -eq "all" -or $PluginType -eq "skill-creator") {
    Write-Host "[INFO] Skill Creator (skills for creating skills)..." -ForegroundColor Cyan

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "skill-creator@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "skill-creator@local-dev")
        }
        else {
            Write-Host "[OK] skill-creator@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- Nushell LSP ----
if ($PluginType -eq "all" -or $PluginType -eq "nushell") {
    Write-Host "[INFO] Nushell LSP..." -ForegroundColor Cyan
    [void](Test-Binary "nu" "nu")

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "nushell-lsp@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "nushell-lsp@local-dev")
        }
        else {
            Write-Host "[OK] nushell-lsp@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- mq-lsp ----
if ($PluginType -eq "all" -or $PluginType -eq "mq-lsp") {
    Write-Host "[INFO] mq-lsp..." -ForegroundColor Cyan
    [void](Test-Binary "mq-lsp" "mq-lsp")

    # Register local marketplace + plugin
    $marketplacePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\marketplace"))
    if (-not (Test-Path (Join-Path $marketplacePath ".claude-plugin\marketplace.json"))) {
        Write-Host "[ERROR] Local marketplace not found: $marketplacePath" -ForegroundColor Red
    }
    else {
        $output = & claude plugin list 2>&1
        if ($output -notmatch "mq-lsp@local-dev") {
            & claude plugin marketplace add $marketplacePath 2>&1 | Out-Null
            [void](Register-Plugin "mq-lsp@local-dev")
        }
        else {
            Write-Host "[OK] mq-lsp@local-dev : already registered" -ForegroundColor Green
        }
    }
    Write-Host ""
}

# ---- Summary ----
$plugins = switch ($PluginType) {
    "typescript"   { @("typescript-lsp@local-dev") }
    "powershell"   { @("powershell-lsp@local-dev") }
    "astral"       { @("astral@local-dev") }
    "mq-lsp"       { @("mq-lsp@local-dev") }
    "nushell"      { @("nushell-lsp@local-dev") }
    "skill-creator"{ @("skill-creator@local-dev") }
    default        { @("typescript-lsp@local-dev", "powershell-lsp@local-dev", "astral@local-dev", "mq-lsp@local-dev", "nushell-lsp@local-dev", "skill-creator@local-dev") }
}
Write-Host "[INFO] Plugin status:" -ForegroundColor Cyan
$output = & claude plugin list 2>&1
foreach ($id in $plugins) {
    $short = $id -replace '@.*', ''
    if ($output -match [regex]::Escape($id)) {
        Write-Host "     $short : enabled" -ForegroundColor Green
    }
    else {
        Write-Host "     $short : NOT installed" -ForegroundColor DarkGray
    }
}
Write-Host ""
