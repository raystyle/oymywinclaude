#Requires -Version 5.1

<#
.SYNOPSIS
    Lock or unlock a tool version to prevent upgrades.
.DESCRIPTION
    Writes tool version to D:\DevSetup\version-lock.json.
    When locked, install scripts will skip upgrades even if a newer version is available.
    Use -Force on install commands to override the lock.
.PARAMETER ToolName
    Tool identifier (e.g. "git", "fzf", "python")
.PARAMETER Version
    Version to lock. Omit to auto-detect current installed version.
.PARAMETER Remove
    Remove the lock for the specified tool.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$ToolName,

    [Parameter(Position = 1)]
    [string]$Version = "",

    [switch]$Remove
)

. "$PSScriptRoot\helpers.ps1"

if ($Remove) {
    Set-VersionLock -ToolName $ToolName -Version ""
    Write-Host "[OK] $ToolName unlocked" -ForegroundColor Green
    return
}

# Auto-detect current version if not specified
if (-not $Version) {
    # Try common detection methods
    $exePaths = @(
        "$env:USERPROFILE\.local\bin\$ToolName.exe",
        "$env:USERPROFILE\.local\bin\$($ToolName.Substring(0,1).ToUpper() + $ToolName.Substring(1)).exe",
        "$Env:ProgramFiles\PowerShell\7\pwsh.exe",
        "D:\DevEnvs\Git\cmd\git.exe",
        "D:\DevEnvs\Python\python.exe",
        "D:\DevEnvs\node\node.exe",
        "D:\DevEnvs\.cargo\bin\rustc.exe"
    )

    $exePath = $null
    foreach ($p in $exePaths) {
        if (Test-Path $p) { $exePath = $p; break }
    }

    # Try Get-Command as fallback
    if (-not $exePath) {
        $cmd = Get-Command $ToolName -ErrorAction SilentlyContinue
        if ($cmd) { $exePath = $cmd.Source }
    }

    if (-not $exePath) {
        Write-Host "[ERROR] $ToolName not found. Cannot auto-detect version." -ForegroundColor Red
        Write-Host "       Specify version explicitly: just lock $ToolName 1.2.3" -ForegroundColor DarkGray
        exit 1
    }

    $raw = & $exePath --version 2>&1 | Out-String
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $Version = $Matches[1]
    }
    elseif ($raw -match '(\d+\.\d+)') {
        $Version = $Matches[1]
    }

    if (-not $Version) {
        Write-Host "[ERROR] Could not detect version for $ToolName" -ForegroundColor Red
        exit 1
    }
}

Set-VersionLock -ToolName $ToolName -Version $Version
Write-Host "[OK] $ToolName locked to version $Version" -ForegroundColor Green
