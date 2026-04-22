#Requires -Version 5.1

<#
.SYNOPSIS
    Install PowerShell 7 (pwsh) from GitHub Releases via MSI installer.
.DESCRIPTION
    Downloads PowerShell 7 MSI from GitHub Releases, installs via msiexec
    with ADD_PATH=1 (Machine PATH), ENABLE_PSREMOTING=1, REGISTER_MANIFEST=1.
    Idempotent -- safe to run multiple times. Supports upgrade detection.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'NoBackup', Justification = 'Reserved for consistency with install-tool.ps1')]
[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force,
    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

# ── Self-elevation (MSI per-machine install requires admin) ──
$shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [INFO] Elevating to admin..." -ForegroundColor Yellow
    $logFile = Join-Path $env:TEMP "pwsh7_install.log"
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue

    $proc = Start-Process $shell -Verb RunAs -ArgumentList @(
        "-NoLogo", "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath
    ) -Wait -PassThru

    # Relay elevated output
    if (Test-Path $logFile) {
        Get-Content $logFile -ErrorAction SilentlyContinue |
            Where-Object { $_ -notmatch '^\*{10,}$' -and $_ -notmatch '^(PowerShell transcript|Start time|End time|Username|RunAs User|Configuration|Machine:|Host Application|Process ID|PSVersion|PSEdition|GitCommitId|OS:|Platform:|PSCompatible|PSRemoting|Serialization|WSManStack)' }
        Remove-Item $logFile -Force -ErrorAction SilentlyContinue
    }
    exit $proc.ExitCode
}

# ── Elevated: capture output via transcript ──
$logFile = Join-Path $env:TEMP "pwsh7_install.log"
$null = Start-Transcript -Path $logFile -Force

try {

$ErrorActionPreference = 'Stop'
$script:exitCode = 0

# ---- Constants ----
$Repo    = "PowerShell/PowerShell"
$PwshDir = "$Env:ProgramFiles\PowerShell\7"
$PwshExe = "$PwshDir\pwsh.exe"

# ---- 0. Idempotent check ----
$installed = $false
$installedVersion = ""

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($pwshCmd) {
    $PwshExe = $pwshCmd.Source
}

if ($pwshCmd -or (Test-Path $PwshExe)) {
    $raw = & $PwshExe --version 2>&1 | Out-String
    if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
        $installedVersion = $Matches[1]
        $installed = $true
    }
}

if ($installed -and -not $Version -and -not $Force) {
    # Will resolve latest below to check if upgrade needed
}

# ---- 1. Resolve version ----
$release = $null
$tag = ""

if (-not $Version) {
    Write-Host "[INFO] Fetching latest release for $Repo..." -ForegroundColor Cyan
    try {
        $release = Get-GitHubRelease -Repo $Repo
        $rawTag  = $release.tag_name
        $Version = $rawTag -replace '^v', ''
        $tag     = $rawTag
        Write-Host "[OK] Latest version: $Version" -ForegroundColor Green
    }
    catch {
        if ($installed) {
            Show-AlreadyInstalled -Tool "PowerShell 7" -Version $installedVersion -Location (Split-Path $PwshExe -Parent)
            Write-Host "[WARN] Could not check for updates: $_" -ForegroundColor Yellow
            return
        }
        Write-Host "[ERROR] Cannot determine version to install: $_" -ForegroundColor Red
        $script:exitCode = 1; return
    }
}
else {
    $tag = "v$Version"
}

# ---- 2. Check if already installed and up to date ----
if ($installed) {
    $upgradeCheck = Test-UpgradeRequired -Current $installedVersion -Target $Version -ToolName "powershell7" -Force:$Force
    if (-not $upgradeCheck.Required) {
        Show-AlreadyInstalled -Tool "PowerShell 7" -Version $installedVersion -Location (Split-Path $PwshExe -Parent)
        Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
        return
    }

    Write-Host "[UPGRADE] PowerShell $installedVersion -> $Version" -ForegroundColor Cyan
    Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray

    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor Cyan
        Write-Host "    - Download PowerShell $Version MSI" -ForegroundColor DarkGray
        Write-Host "    - Run msiexec to upgrade in-place" -ForegroundColor DarkGray
        Write-Host "    - MSI handles rollback on failure" -ForegroundColor DarkGray
        Write-Host ""
        $response = Read-Host "  Continue? [Y/n]"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Upgrade cancelled" -ForegroundColor Cyan
            return
        }
    }
}

Show-Installing -Component "PowerShell 7 $Version"

# ---- 3. Download MSI ----
$msiName     = "PowerShell-${Version}-win-x64.msi"
$downloadUrl = "https://github.com/$Repo/releases/download/$tag/$msiName"
$msiFile     = "$env:TEMP\$msiName"

Write-Host "[INFO] Downloading $msiName ..." -ForegroundColor Cyan

# Need release object for hash verification
if (-not $release) {
    try {
        $release = Get-GitHubRelease -Repo $Repo -Tag $tag
    }
    catch {
        Write-Host "[WARN] Could not fetch release metadata, hash verification skipped" -ForegroundColor Yellow
        $release = $null
    }
}

try {
    Save-WithCache -Url $downloadUrl -OutFile $msiFile -CacheDir "PowerShell" -TimeoutSec 300
}
catch {
    Write-Host "[ERROR] Failed to download $($msiName): $($_)" -ForegroundColor Red
    $script:exitCode = 1; return
}

# ---- 4. Verify SHA256 ----
try {
    Test-FileHash -FilePath $msiFile -Release $release -AssetName $msiName
}
catch {
    Write-Host "[ERROR] Hash verification failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $msiFile -Force -ErrorAction SilentlyContinue
    $script:exitCode = 1; return
}

# ---- 5. Run msiexec ----
Write-Host "[INFO] Installing PowerShell $Version ..." -ForegroundColor Cyan
Write-Host "[INFO] msiexec /package $msiName /quiet ADD_PATH=1 ..." -ForegroundColor DarkGray

$msiexecArgs = @(
    "/package", $msiFile,
    "/quiet",
    "ADD_PATH=1",
    "ENABLE_PSREMOTING=1",
    "REGISTER_MANIFEST=1",
    "USE_MU=0",
    "ENABLE_MU=0",
    "/norestart"
)

$proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiexecArgs -Wait -PassThru -NoNewWindow

Remove-Item $msiFile -Force -ErrorAction SilentlyContinue

if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
    if ($proc.ExitCode -eq 3010) {
        Write-Host "[WARN] Installation succeeded but reboot required" -ForegroundColor Yellow
    }
    Write-Host "[OK] msiexec completed (exit code: $($proc.ExitCode))" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] msiexec failed with exit code: $($proc.ExitCode)" -ForegroundColor Red
    Write-Host "       MSI rollback is handled by Windows Installer" -ForegroundColor DarkGray
    $script:exitCode = 1; return
}

# ---- 6. Refresh environment and verify ----
Refresh-Environment

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $pwshCmd) {
    $pwshCmd = Get-Command "$PwshDir\pwsh.exe" -ErrorAction SilentlyContinue
}

if (-not $pwshCmd) {
    Write-Host "[WARN] pwsh not found in PATH after install (reboot may be needed)" -ForegroundColor Yellow
    if (Test-Path $PwshExe) {
        $pwshCmd = @{ Source = $PwshExe }
    }
    else {
        Write-Host "[ERROR] pwsh.exe not found at expected location" -ForegroundColor Red
        $script:exitCode = 1; return
    }
}

$raw = & $pwshCmd.Source --version 2>&1 | Out-String
if ($raw -match 'PowerShell\s+(\d+\.\d+\.\d+)') {
    $installedVersion = $Matches[1]
    Write-Host "[OK] Installed: $($raw.Trim())" -ForegroundColor Green
    Write-Host "[INFO] Path: $($pwshCmd.Source)" -ForegroundColor Cyan
}
else {
    Write-Host "[ERROR] Verification failed: could not parse version from pwsh --version" -ForegroundColor Red
    $script:exitCode = 1; return
}

# ---- 7. Summary ----
Write-Host ""
Show-InstallComplete -Tool "PowerShell 7" -Version $installedVersion

} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
    if ($script:exitCode) { exit $script:exitCode }
}
