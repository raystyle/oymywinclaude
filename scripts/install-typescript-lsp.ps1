#Requires -Version 5.1

<#
.SYNOPSIS
    Install TypeScript LSP for Claude Code
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

# ---- 1. Check Node.js/npm ----
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Write-Host "[ERROR] npm not found" -ForegroundColor Red
    Write-Host "       Run 'just install-node' to install Node.js" -ForegroundColor DarkGray
    exit 1
}

Write-Host "[OK] Node.js/npm found" -ForegroundColor Green

# ---- 2. Install typescript-language-server ----
$tslsCmd = Get-Command typescript-language-server -ErrorAction SilentlyContinue
if ($tslsCmd) {
    Show-AlreadyInstalled -Tool "typescript-language-server"
}
else {
    Write-Host "[INFO] Installing typescript-language-server via npm..." -ForegroundColor Cyan

    try {
        & npm install -g typescript-language-server typescript 2>&1 | Out-Null
        $tslsCmd = Get-Command typescript-language-server -ErrorAction SilentlyContinue
        if ($tslsCmd) {
            Write-Host "[OK] typescript-language-server installed" -ForegroundColor Green
        }
        else {
            Write-Host "[WARN] typescript-language-server not found in PATH" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "[ERROR] Failed to install typescript-language-server: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "[OK] TypeScript LSP installation completed!" -ForegroundColor Green

# ---- 3. Deploy shim exe (node.exe + cli.mjs) ----
$nodeDir        = "D:\DevEnvs\node"
$shimExePath    = "$env:USERPROFILE\.local\bin\typescript-language-server.exe"
$cliMjsPath     = Join-Path $nodeDir "node_modules\typescript-language-server\lib\cli.mjs"

if ((Test-Path (Join-Path $nodeDir "node.exe")) -and (Test-Path $cliMjsPath)) {
    try {
        Install-ShimExe -TargetExePath $shimExePath -ShimTargetPath "$nodeDir\node.exe" -ShimArgs "$cliMjsPath"
    }
    catch {
        Write-Host "[WARN] Shim deployment failed (non-critical): $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[WARN] node.exe or cli.mjs not found, skipping shim deployment" -ForegroundColor Yellow
}
