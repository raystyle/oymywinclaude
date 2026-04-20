#Requires -Version 5.1

<#
.SYNOPSIS
    Install markdownlint-cli2 globally via npm and deploy shim exe
.DESCRIPTION
    Installs markdownlint-cli2 globally via npm, then creates a shim exe
    named 'markdownlint' for seamless CLI usage. Idempotent.
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

# ---- 2. Install markdownlint-cli2 ----
$nodeDir = "D:\DevEnvs\node"
$shimExePath = "$env:USERPROFILE\.local\bin\markdownlint.exe"

if (Test-Path $shimExePath) {
    $currentVer = (& markdownlint --version 2>$null | Out-String).Trim()
    if ($currentVer) {
        Show-AlreadyInstalled -Tool "markdownlint" -Version $currentVer -Location $shimExePath
        return
    }
}

Write-Host "[INFO] Installing markdownlint-cli2 via npm..." -ForegroundColor Cyan

try {
    & npm install -g markdownlint-cli2 2>&1 | Out-Null

    $mdCmdPath = "$nodeDir\markdownlint-cli2.cmd"
    if (-not (Test-Path $mdCmdPath)) {
        Write-Host "[WARN] markdownlint-cli2.cmd not found at $mdCmdPath" -ForegroundColor Yellow
        exit 1
    }

    $ver = (& markdownlint-cli2 --version 2>$null | Out-String).Trim()
    Show-InstallSuccess -Component "markdownlint" -Location $ver

    # ---- 3. Deploy shim exe ----
    if (Test-Path $mdCmdPath) {
        try {
            Install-ShimExe -TargetExePath $shimExePath -ShimTargetPath $mdCmdPath
            Write-Host "[INFO] Created shim: $shimExePath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[WARN] Shim deployment failed (non-critical): $_" -ForegroundColor Yellow
        }
    }

    # Also remove manual shim at D:\DevEnvs\node if it exists
    $oldShimExe  = "$nodeDir\markdownlint.exe"
    $oldShimConf = "$nodeDir\markdownlint.shim"
    if (Test-Path $oldShimExe) {
        Remove-Item -Path $oldShimExe -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $oldShimConf) {
        Remove-Item -Path $oldShimConf -Force -ErrorAction SilentlyContinue
    }

    Refresh-Environment
}
catch {
    Write-Host "[ERROR] Failed to install markdownlint-cli2: $_" -ForegroundColor Red
    exit 1
}
