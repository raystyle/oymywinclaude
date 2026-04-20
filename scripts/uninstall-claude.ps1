#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Claude Code and remove configuration files
.DESCRIPTION
    Removes Claude Code configuration files, downloads cache, and profile alias.
    Note: Claude Code has no built-in uninstall command; remove via npm/package manager.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$ErrorActionPreference = "Stop"

Write-Host "[INFO] Uninstalling Claude Code..." -ForegroundColor Cyan

# ---- 0. Terminate Claude Code processes ----
Write-Host "[INFO] Checking for running Claude Code processes..." -ForegroundColor Cyan

$claudeProcesses = Get-Process -Name "claude" -ErrorAction SilentlyContinue
if ($claudeProcesses) {
    Write-Host "[INFO] Terminating Claude Code process(es)..." -ForegroundColor Cyan
    try {
        $claudeProcesses | Stop-Process -Force -ErrorAction Stop
        Write-Host "[OK] Terminated $($claudeProcesses.Count) process(es)" -ForegroundColor Green
        Start-Sleep -Seconds 1
    }
    catch {
        Write-Host "[WARN] Failed to terminate process: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[OK] No running Claude Code processes found" -ForegroundColor Green
}

# ---- 1. Remove PowerShell profile alias ----
Write-Host "[INFO] Removing PowerShell profile alias..." -ForegroundColor Cyan
& "$PSScriptRoot/profile-entry.ps1" `
    -Action remove `
    -Line 'if (Get-Command claude.cmd -ErrorAction SilentlyContinue) { Set-Alias -Name claude -Value claude.cmd }' `
    -Comment "Claude Code alias (fnm provides .cmd not .exe)"

# ---- 2. Remove claude binary ----
Write-Host "[INFO] Removing Claude Code binary..." -ForegroundColor Cyan

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $claudeExe = $claudeCmd.Source
    try {
        Remove-Item -Path $claudeExe -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $claudeExe" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to remove $claudeExe : $_" -ForegroundColor Yellow
        Write-Host "[INFO] Close Claude Code and try again" -ForegroundColor Cyan
    }
}

# ---- 3. Remove configuration files and plugin data ----
Write-Host "[INFO] Removing configuration files and plugin data..." -ForegroundColor Cyan

$removedItems = @()
$claudeDir = Join-Path $env:USERPROFILE ".claude"

function Remove-ItemSafe {
    param([string]$Path, [string]$Label, [switch]$Recurse)
    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Force -ErrorAction Stop @("Recurse:$Recurse")
            $script:removedItems += $Path
            Write-Host "[OK] Removed: $Label" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Failed to remove $Label`: $_" -ForegroundColor Yellow
        }
    }
}

[void](Remove-ItemSafe -Path (Join-Path $claudeDir "settings.json") -Label "settings.json")
[void](Remove-ItemSafe -Path "$env:USERPROFILE\.claude.json" -Label ".claude.json")
[void](Remove-ItemSafe -Path (Join-Path $claudeDir "skills") -Label "skills/" -Recurse)
[void](Remove-ItemSafe -Path (Join-Path $claudeDir "backups") -Label "backups/" -Recurse)
[void](Remove-ItemSafe -Path (Join-Path $claudeDir "plugins") -Label "plugins/" -Recurse)

# ---- 4. Verify ----
Write-Host ""
Write-Host "[INFO] Preserving: projects/, memory/" -ForegroundColor Cyan
if ($removedItems.Count -gt 0) {
    Write-Host "[OK] Claude Code uninstalled successfully!" -ForegroundColor Green
    Write-Host "   Removed $($removedItems.Count) item(s)" -ForegroundColor Cyan
}
else {
    Write-Host "[INFO] Claude Code uninstalled (no config files found)" -ForegroundColor Cyan
}
