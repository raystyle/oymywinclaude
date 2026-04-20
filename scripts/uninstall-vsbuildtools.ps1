#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstall VS Build Tools and clean up all related directories
.DESCRIPTION
    Uses InstallCleanup.exe -full for thorough removal, then cleans
    install directories and instance registry data.
    Layout is preserved for reinstall.
#>

[CmdletBinding()]
param(
    [switch]$Force
)

. "$PSScriptRoot\helpers.ps1"

$shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

# ── Self-elevation ──
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [INFO] Elevating to admin..." -ForegroundColor Yellow
    $logFile = Join-Path $env:TEMP "vsbt_uninstall.log"
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue

    $argList = @(
        "-NoLogo", "-NoProfileLoadTime",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath
    )
    if ($Force) { $argList += "-Force" }
    $proc = Start-Process $shell -Verb RunAs -ArgumentList $argList -Wait -PassThru

    # Relay elevated output
    if (Test-Path $logFile) {
        Get-Content $logFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -notmatch '^\*{10,}$' -and $_ -notmatch '^(PowerShell transcript|Start time|End time|Username|RunAs User|Configuration|Machine:|Host Application|Process ID|PSVersion|PSEdition|GitCommitId|OS:|Platform:|PSCompatible|PSRemoting|Serialization|WSManStack)' }
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
    # Elevated process completed - exit to avoid running uninstall twice
    exit $proc.ExitCode
}

# ── Elevated: capture output via transcript ──
$logFile = Join-Path $env:TEMP "vsbt_uninstall.log"
$null = Start-Transcript -Path $logFile -Force

try {
    Write-Host ""
    Write-Host "  VS Build Tools Uninstall" -ForegroundColor White
    Write-Host "  =========================" -ForegroundColor DarkGray
    Write-Host ""

    # ── Step 1: InstallCleanup.exe -full ──
    $cleanup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\InstallCleanup.exe"
    if (Test-Path $cleanup) {
        Write-Host "  [INFO] Running InstallCleanup.exe -full ..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $cleanup -ArgumentList "-full" -NoNewWindow -PassThru -Wait
        Write-Host "  [OK] InstallCleanup completed (exit $($proc.ExitCode))" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] InstallCleanup.exe not found, skipping" -ForegroundColor Yellow
    }

    # ── Step 2: Remove install directory ──
    $installDir = $script:VSBuildTools_InstallPath
    if (Test-Path $installDir) {
        Write-Host "  [INFO] Removing $installDir ..." -ForegroundColor Cyan
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed" -ForegroundColor Green
    }

    # ── Step 3: Remove shared directory ──
    $sharedDir = Join-Path $script:VSBuildTools_InstallPath "_shared"
    if (Test-Path $sharedDir) {
        Write-Host "  [INFO] Removing $sharedDir ..." -ForegroundColor Cyan
        Remove-Item $sharedDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed" -ForegroundColor Green
    }

    # ── Step 4: Remove _Instances ──
    $instancesDir = "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances"
    if (Test-Path $instancesDir) {
        Write-Host "  [INFO] Removing _Instances ..." -ForegroundColor Cyan
        Remove-Item $instancesDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Removed" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  [OK] VS Build Tools uninstall complete" -ForegroundColor Green
    Write-Host "  Layout preserved at: $($script:VSBuildTools_LayoutDir)" -ForegroundColor DarkGray

} catch {
    Write-Host "  [ERROR] $_" -ForegroundColor Red
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
