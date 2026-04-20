#Requires -Version 5.1

<#
.SYNOPSIS
    Show PowerShell 7 (pwsh) installation status.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$PwshDir = "$Env:ProgramFiles\PowerShell\7"
$PwshExe = "$PwshDir\pwsh.exe"

Write-Host "--- PowerShell 7 ---" -ForegroundColor Cyan

# ---- 1. Check if installed ----
$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
$exePath = if ($pwshCmd) { $pwshCmd.Source } elseif (Test-Path $PwshExe) { $PwshExe } else { $null }

if (-not $exePath) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-powershell7' to install" -ForegroundColor DarkGray
    return
}

$raw = & $exePath --version 2>&1 | Out-String
$current = 'unknown'
if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
    $current = $Matches[1]
}

Write-Host "[OK] PowerShell $current" -ForegroundColor Green
Write-Host "  Location:        $exePath" -ForegroundColor DarkGray

# ---- 2. PATH scope ----
$installDir = Split-Path $exePath -Parent
$userPath   = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $installDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $installDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }

# ---- 3. Check for updates ----
try {
    $release = Get-GitHubRelease -Repo "PowerShell/PowerShell"
    $latestTag = $release.tag_name -replace '^v', ''
    $comparison = Compare-SemanticVersion -Current $current -Latest $latestTag
    if ($comparison -eq -1) {
        Write-Host "  Update available: $current -> $latestTag" -ForegroundColor Yellow
    }
    elseif ($comparison -eq 0) {
        Write-Host "  Latest:          $latestTag (up to date)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Latest:          $latestTag (installed is newer)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "  Update check:    unavailable ($($_.Exception.Message))" -ForegroundColor DarkGray
}
