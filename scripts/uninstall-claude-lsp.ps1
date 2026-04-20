#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Claude Code LSP plugins (Pyright + TypeScript)
.DESCRIPTION
    Uninstalls Pyright LSP for Python and TypeScript LSP for TypeScript/JavaScript.
    Supports uninstalling both or specific LSPs based on parameters.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("all", "python", "typescript", "")]
    [string]$LspType = "all"
)

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Claude Code LSP Plugins Uninstallation ===" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check Claude Code ----
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[WARN] Claude Code not installed. Nothing to uninstall." -ForegroundColor Yellow
    exit 0
}

Write-Host "[OK] Claude Code found" -ForegroundColor Green
Write-Host ""

# ---- 2. Uninstall Python LSP (Pyright) ----
if ($LspType -eq "all" -or $LspType -eq "python") {
    Write-Host "--- Uninstalling Python LSP (Pyright) ---" -ForegroundColor Cyan
    Write-Host ""

    # Uninstall Claude plugin
    Write-Host "[INFO] Uninstalling pyright-lsp Claude plugin..." -ForegroundColor Cyan
    try {
        & claude plugin uninstall pyright-lsp@claude-plugins-official 2>&1 | Out-Null
        Write-Host "[OK] pyright-lsp plugin uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to uninstall pyright-lsp plugin: $_" -ForegroundColor Yellow
    }
    Write-Host ""

    # Uninstall pyright
    Write-Host "[INFO] Uninstalling pyright via pip..." -ForegroundColor Cyan
    try {
        & pip uninstall -y pyright 2>&1 | Out-Null
        Write-Host "[OK] pyright uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to uninstall pyright: $_" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---- 3. Uninstall TypeScript LSP ----
if ($LspType -eq "all" -or $LspType -eq "typescript") {
    Write-Host "--- Uninstalling TypeScript LSP ---" -ForegroundColor Cyan
    Write-Host ""

    # Uninstall Claude plugin
    Write-Host "[INFO] Uninstalling typescript-lsp Claude plugin..." -ForegroundColor Cyan
    try {
        & claude plugin uninstall typescript-lsp@claude-plugins-official 2>&1 | Out-Null
        Write-Host "[OK] typescript-lsp plugin uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to uninstall typescript-lsp plugin: $_" -ForegroundColor Yellow
    }
    Write-Host ""

    # Uninstall typescript-language-server
    Write-Host "[INFO] Uninstalling typescript-language-server via npm..." -ForegroundColor Cyan
    try {
        & npm uninstall -g typescript-language-server 2>&1 | Out-Null
        Write-Host "[OK] typescript-language-server uninstalled" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to uninstall typescript-language-server: $_" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ---- 4. Summary ----
Write-Host "--- Summary ---" -ForegroundColor Cyan
Write-Host ""

Write-Host "[OK] LSP uninstallation completed!" -ForegroundColor Green
Write-Host "  Restart Claude Code to apply changes" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor DarkGray
Write-Host "  just uninstall-claude-lsp             # Uninstall all LSPs" -ForegroundColor DarkGray
Write-Host "  just uninstall-claude-lsp python      # Uninstall only Python LSP" -ForegroundColor DarkGray
Write-Host "  just uninstall-claude-lsp typescript  # Uninstall only TypeScript LSP" -ForegroundColor DarkGray
Write-Host ""
