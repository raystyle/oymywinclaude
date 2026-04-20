#Requires -Version 5.1

<#
.SYNOPSIS
    Install Playwright CLI globally via npm
.DESCRIPTION
    Installs @playwright/cli globally via npm. Idempotent — safe to run multiple times.
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

# ---- 2. Install @playwright/cli ----
$pwCmd = Get-Command playwright-cli -ErrorAction SilentlyContinue
if ($pwCmd) {
    $currentVer = (& playwright-cli --version 2>$null | Out-String).Trim()
    if ($currentVer) {
        Show-AlreadyInstalled -Tool "Playwright CLI" -Version $currentVer -Location $pwCmd.Source
        return
    }
}

Write-Host "[INFO] Installing @playwright/cli@latest via npm..." -ForegroundColor Cyan

try {
    & npm install -g @playwright/cli@latest 2>&1 | Out-Null

    # Find the playwright-cli.js installed by npm
    $nodeDir = "D:\DevEnvs\node"
    $pwJsPath = "$nodeDir\node_modules\@playwright\cli\playwright-cli.js"

    if (-not (Test-Path $pwJsPath)) {
        Write-Host "[WARN] playwright-cli.js not found at $pwJsPath" -ForegroundColor Yellow
        exit 1
    }

    $ver = (& playwright-cli --version 2>$null | Out-String).Trim()
    Show-InstallSuccess -Component "Playwright CLI" -Location $ver

    # ---- Deploy shim exe (node.exe + playwright-cli.js) ----
    $shimExePath = "$env:USERPROFILE\.local\bin\playwright-cli.exe"
    if ((Test-Path "$nodeDir\node.exe") -and (Test-Path $pwJsPath)) {
        try {
            Install-ShimExe -TargetExePath $shimExePath -ShimTargetPath "$nodeDir\node.exe" -ShimArgs $pwJsPath
            Write-Host "[INFO] Created shim: $shimExePath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[WARN] Shim deployment failed (non-critical): $_" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[WARN] node.exe or playwright-cli.js not found, skipping shim deployment" -ForegroundColor Yellow
    }

    # Refresh PATH
    Refresh-Environment
}
catch {
    Write-Host "[ERROR] Failed to install @playwright/cli: $_" -ForegroundColor Red
    exit 1
}
