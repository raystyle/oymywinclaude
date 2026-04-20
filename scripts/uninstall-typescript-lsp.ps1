#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall TypeScript LSP: remove shim exe, npm packages, and Claude plugin
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

# ---- 1. Remove shim exe and .shim config ----
$shimExePath = "$env:USERPROFILE\.local\bin\typescript-language-server.exe"

Remove-ShimExe -TargetExePath $shimExePath

# ---- 2. Uninstall typescript-language-server via npm ----
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Write-Host "[INFO] Uninstalling typescript-language-server via npm..." -ForegroundColor Cyan
    try {
        & npm uninstall -g typescript-language-server typescript 2>&1 | Out-Null
        Write-Host "[OK] npm packages removed" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] npm uninstall failed: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] npm not found, skipping npm uninstall" -ForegroundColor Yellow
}

# ---- 3. Uninstall Claude plugin ----
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    Write-Host "[INFO] Removing typescript-lsp Claude plugin..." -ForegroundColor Cyan
    try {
        & claude plugin uninstall typescript-lsp@claude-plugins-official 2>&1 | Out-Null
        Write-Host "[OK] Claude plugin removed" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Claude plugin uninstall failed: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[INFO] Claude CLI not found, skipping plugin uninstall" -ForegroundColor DarkGray
}

Write-Host "[OK] TypeScript LSP uninstall completed!" -ForegroundColor Green
