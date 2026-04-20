#Requires -Version 5.1

<#
.SYNOPSIS
    Check Claude Code LSP plugins installation status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Write-Host ""
Write-Host "--- Claude Code LSP Plugins ---" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check Claude Code ----
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Host "[NOT INSTALLED] Claude Code" -ForegroundColor Red
    Write-Host "     Run 'just install-claude' to install Claude Code" -ForegroundColor DarkGray
    exit 0
}

Write-Host "[OK] Claude Code installed" -ForegroundColor Green
Write-Host ""

# ---- 2. Check Python LSP (ty via Astral) ----
Write-Host "Python LSP (ty):" -ForegroundColor Cyan
Write-Host ""

$uvxCmd = Get-Command uvx -ErrorAction SilentlyContinue
if ($uvxCmd) {
    Write-Host "     uvx: installed" -ForegroundColor Green
    Write-Host "     Location: $($uvxCmd.Source)" -ForegroundColor DarkGray
}
else {
    Write-Host "     uvx: NOT installed" -ForegroundColor Yellow
    Write-Host "     Run 'just install-claude-plugin-astral' to install Astral plugin" -ForegroundColor DarkGray
}

# Check Claude plugin
try {
    $env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"
    $pluginOutput = & claude plugin list 2>&1
    if ($pluginOutput -match "astral@local-dev") {
        if ($pluginOutput -match "astral@local-dev[\s\S]*Status.*✓ enabled") {
            Write-Host "     astral plugin: enabled" -ForegroundColor Green
        }
        else {
            Write-Host "     astral plugin: installed (disabled)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "     astral plugin: NOT installed" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "     astral plugin: cannot check" -ForegroundColor DarkGray
}

Write-Host ""

# ---- 3. Check TypeScript LSP ----
Write-Host "TypeScript LSP:" -ForegroundColor Cyan
Write-Host ""

$tslsCmd = Get-Command typescript-language-server -ErrorAction SilentlyContinue
if ($tslsCmd) {
    Write-Host "     typescript-language-server: installed" -ForegroundColor Green
    Write-Host "     Location: $($tslsCmd.Source)" -ForegroundColor DarkGray
}
else {
    Write-Host "     typescript-language-server: NOT installed" -ForegroundColor Yellow
    Write-Host "     Run 'just install-typescript-lsp' to install" -ForegroundColor DarkGray
}

# Check Claude plugin
try {
    $env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"
    $pluginOutput = & claude plugin list 2>&1
    if ($pluginOutput -match "typescript-lsp@claude-plugins-official") {
        if ($pluginOutput -match "typescript-lsp@claude-plugins-official[\s\S]*Status.*✓ enabled") {
            Write-Host "     typescript-lsp plugin: enabled" -ForegroundColor Green
        }
        else {
            Write-Host "     typescript-lsp plugin: installed (disabled)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "     typescript-lsp plugin: NOT installed" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "     typescript-lsp plugin: cannot check" -ForegroundColor DarkGray
}

Write-Host ""

# ---- 4. Check PowerShell LSP ----
Write-Host "PowerShell LSP:" -ForegroundColor Cyan
Write-Host ""

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    Write-Host "     pwsh: NOT installed" -ForegroundColor Yellow
    Write-Host "     PowerShell 7+ is required for PowerShell LSP" -ForegroundColor DarkGray
}
else {
    Write-Host "     pwsh: installed" -ForegroundColor Green

    # Check PowerShellEditorServices module
    $pesModule = $null
    try {
        $pesModule = Get-Module -ListAvailable PowerShellEditorServices -ErrorAction Stop |
            Sort-Object Version -Descending | Select-Object -First 1
    }
    catch {
        # Module not installed — this is expected when PSES is not installed
        # No action needed, will be handled by the null check below
    }

    if ($pesModule) {
        Write-Host "     PowerShellEditorServices: $($pesModule.Version)" -ForegroundColor Green
    }
    else {
        Write-Host "     PowerShellEditorServices: NOT installed" -ForegroundColor Yellow
        Write-Host "     Run 'just install-pses' to install" -ForegroundColor DarkGray
    }

    # Check Claude plugin
    try {
        $env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"
        $pluginOutput = & claude plugin list 2>&1
        if ($pluginOutput -match "powershell-lsp@") {
            Write-Host "     powershell-lsp plugin: enabled" -ForegroundColor Green
        }
        else {
            Write-Host "     powershell-lsp plugin: NOT installed" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "     powershell-lsp plugin: cannot check" -ForegroundColor DarkGray
    }
}

Write-Host ""

# ---- 5. Check ENABLE_LSP_TOOL ----
Write-Host "LSP Configuration:" -ForegroundColor Cyan
Write-Host ""

$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
$lspEnabled = $false
if (Test-Path $settingsFile) {
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        if ($settings.env.ENABLE_LSP_TOOL -eq 1) { $lspEnabled = $true }
    }
    catch {
        Write-Debug "Settings parse error: $_"
    }
}

if ($lspEnabled) {
    Write-Host "     ENABLE_LSP_TOOL: enabled" -ForegroundColor Green
}
else {
    Write-Host "     ENABLE_LSP_TOOL: disabled" -ForegroundColor Yellow
    Write-Host "     Run 'just config-claude' to enable LSP support" -ForegroundColor DarkGray
}

Write-Host ""

# ---- 6. Summary ----
Write-Host "--- Quick Actions ---" -ForegroundColor Cyan
Write-Host ""
Write-Host "Install all LSP plugins:" -ForegroundColor DarkGray
Write-Host "     just install-claude-plugin all" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Install specific LSP plugin:" -ForegroundColor DarkGray
Write-Host "     just install-claude-plugin astral      # Python LSP (ty)" -ForegroundColor DarkGray
Write-Host "     just install-claude-plugin typescript  # TypeScript LSP" -ForegroundColor DarkGray
Write-Host "     just install-claude-plugin powershell  # PowerShell LSP" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Check status:" -ForegroundColor DarkGray
Write-Host "     just status-claude-lsp" -ForegroundColor DarkGray
Write-Host ""
