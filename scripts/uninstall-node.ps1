#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Node.js: remove D:\DevEnvs\node, PATH entry, and .npmrc registry
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = 'Continue'

$NodeDir = "D:\DevEnvs\node"

Write-Host "--- Uninstalling Node.js ---" -ForegroundColor Cyan

# ---- 1. Remove from PATH ----
Remove-UserPath -Dir $NodeDir

# ---- 2. Remove Node.js directory ----
if (Test-Path $NodeDir) {
    try {
        Remove-Item -Path $NodeDir -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] Removed $NodeDir" -ForegroundColor Green
    }
    catch {
        cmd /c "rd /s /q `"$NodeDir`"" 2>$null
        if (Test-Path $NodeDir) {
            Write-Host "[WARN] Could not fully remove $NodeDir -- close all terminals and retry:" -ForegroundColor Yellow
            Write-Host "       cmd /c rmdir /s /q `"$NodeDir`"" -ForegroundColor Cyan
        }
        else {
            Write-Host "[OK] Removed $NodeDir (via cmd)" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "[OK] $NodeDir not found, nothing to remove" -ForegroundColor Gray
}

# ---- 3. Remove .npmrc registry line ----
$npmrcPath = "$env:USERPROFILE\.npmrc"
if (Test-Path $npmrcPath) {
    $content = Get-Content $npmrcPath -Raw -ErrorAction SilentlyContinue
    if ($content -match '(?m)^registry\s*=\s*https://registry\.npmmirror\.com') {
        $newContent = ($content -replace '(?m)^registry\s*=\s*https://registry\.npmmirror\.com/?\s*\r?\n?', '').TrimEnd()
        if ($newContent) {
            Set-Content -Path $npmrcPath -Value $newContent -NoNewline -Encoding UTF8
            Write-Host "[OK] Removed npmmirror registry from .npmrc" -ForegroundColor Green
        }
        else {
            Remove-Item -Path $npmrcPath -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed .npmrc" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "[OK] Node.js uninstalled." -ForegroundColor Green
