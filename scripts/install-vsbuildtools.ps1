#Requires -Version 5.1
<#
.SYNOPSIS
    Install VS Build Tools from offline layout (MSVC + Windows SDK)
.DESCRIPTION
    Layout-based offline install from D:\DevSetup\VSBuildTools\Layout.
    Post-install: registers COM DLL for vswhere compatibility.
    Idempotent: skips if VS Build Tools with MSVC is already detected.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }

# ── Self-elevation ──
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "  [INFO] Elevating to admin..." -ForegroundColor Yellow
    $logFile = Join-Path $env:TEMP "vsbt_install.log"
    Remove-Item $logFile -Force -ErrorAction SilentlyContinue

    $proc = Start-Process $shell -Verb RunAs -ArgumentList @(
        "-NoLogo", "-NoProfileLoadTime",
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
$logFile = Join-Path $env:TEMP "vsbt_install.log"
$null = Start-Transcript -Path $logFile -Force

try {

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ── Configuration ──
$script:LayoutDir    = $script:VSBuildTools_LayoutDir
$script:CacheDir     = $script:VSBuildTools_CacheDir
$script:InstallPath  = $script:VSBuildTools_InstallPath
$script:TimeoutMs    = 1800000  # 30 min

Write-Host ""
Write-Host "  VS Build Tools Install" -ForegroundColor White
Write-Host "  =======================" -ForegroundColor DarkGray
Write-Host ""

# ── Step 1: Idempotent check ──
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $existing = & $vswhere -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null | Select-Object -First 1
    if ($existing -and (Test-Path $existing)) {
        $ver = & $vswhere -prerelease -products * `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationVersion 2>$null | Select-Object -First 1
        Show-AlreadyInstalled -Tool "VS Build Tools" -Version $ver -Location $existing
        exit 0
    }
}

# Also check filesystem (for unregistered installs)
$cl = Get-ChildItem "$script:InstallPath\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($cl) {
    Show-AlreadyInstalled -Tool "VS Build Tools (filesystem)" -Location $script:InstallPath
    Write-Host "  [WARN] Instance not registered with vswhere. Try uninstall + reinstall." -ForegroundColor Yellow
    exit 0
}

# ── Step 2: Clean up incomplete installations ──
if (Test-Path $script:InstallPath) {
    $cl = Get-ChildItem "$script:InstallPath\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $cl) {
        Write-Host "  [WARN] Incomplete installation detected at: $script:InstallPath" -ForegroundColor Yellow
        Write-Host "  [INFO] Cleaning up incomplete installation..." -ForegroundColor Cyan
        try {
            Remove-Item -Path $script:InstallPath -Recurse -Force -ErrorAction Stop
            Write-Host "  [OK] Cleanup complete" -ForegroundColor Green
        }
        catch {
            Write-Host "  [ERROR] Failed to cleanup: $_" -ForegroundColor Red
            Write-Host "  [INFO] Please manually remove: $script:InstallPath" -ForegroundColor DarkGray
            exit 1
        }
    }
}

# ── Step 3: Validate or create layout ──
$bootstrapper = Join-Path $script:LayoutDir "vs_buildtools.exe"
if (-not (Test-Path $bootstrapper)) {
    Write-Host "  [WARN] Layout not found: $script:LayoutDir" -ForegroundColor Yellow
    Write-Host "  [INFO] Auto-creating layout (this will download ~3-5 GB)..." -ForegroundColor Cyan
    Write-Host ""

    # Invoke layout creation script
    $layoutScript = Join-Path $PSScriptRoot "create-vsbuildtools-layout.ps1"
    & $layoutScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Layout creation failed" -ForegroundColor Red
        exit 1
    }

    # Re-verify
    if (-not (Test-Path $bootstrapper)) {
        Write-Host "  [ERROR] Layout still not found after creation" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# ── Step 4: Ensure cache directory exists ──
if (-not (Test-Path $script:CacheDir)) {
    Write-Host "  [INFO] Creating cache directory..." -ForegroundColor Cyan
    $null = New-Item -Path $script:CacheDir -ItemType Directory -Force
    Write-Host "  [OK] Cache directory created" -ForegroundColor Green
}

# ── Step 5: Install from layout ──
Show-Installing -Component "VS Build Tools (MSVC + Windows SDK)"
Write-Host "  Layout:    $script:LayoutDir" -ForegroundColor DarkGray
Write-Host "  Install:   $script:InstallPath" -ForegroundColor DarkGray
Write-Host ""

$installArgs = @(
    "--passive", "--wait", "--norestart", "--noweb",
    "--installPath", $script:InstallPath,
    "--path", "cache=$script:CacheDir",
    "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621",
    "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100"
)

Write-Host "  [INFO] Installing... (this may take 5-15 minutes)" -ForegroundColor Cyan

$proc = Start-Process -FilePath $bootstrapper -ArgumentList $installArgs `
    -NoNewWindow -PassThru
$null = $proc.Handle

if (-not $proc.WaitForExit($script:TimeoutMs)) {
    try {
        $proc.Kill()
    }
    catch {
        # Process may have already exited — race condition is expected
        Write-Verbose "Process already exited or termination failed: $_"
    }
    Write-Host "  [ERROR] Install timed out ($([Math]::Round($script:TimeoutMs / 60000)) min)" -ForegroundColor Red
    exit 1
}

switch ($proc.ExitCode) {
    0 { Write-Host "" }
    3010 {
        Write-Host ""
        Write-Host "  [WARN] Install succeeded, reboot required" -ForegroundColor Yellow
    }
    1 {
        Write-Host ""
        Write-Host "  [ERROR] Install failed (exit code 1)" -ForegroundColor Red
        Write-Host "  Check logs: %TEMP%\dd_*.log" -ForegroundColor DarkGray
        Write-Host "  If migration error, try manual UI install from:" -ForegroundColor DarkGray
        Write-Host "    $bootstrapper" -ForegroundColor DarkGray
        exit 1
    }
    default {
        Write-Host ""
        Write-Host "  [ERROR] Install failed (exit code $($proc.ExitCode))" -ForegroundColor Red
        Write-Host "  Check logs: %TEMP%\dd_*.log" -ForegroundColor DarkGray
        exit 1
    }
}

# ── Step 6: Verify & register COM DLL if needed ──
Write-Host ""
Write-Host "  [INFO] Verifying installation..." -ForegroundColor Cyan

$verified = $null
if (Test-Path $vswhere) {
    $verified = & $vswhere -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null | Select-Object -First 1
}

if ($verified) {
    $ver = & $vswhere -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationVersion 2>$null | Select-Object -First 1
    Show-InstallComplete -Tool "VS Build Tools" -Version $ver
} else {
    Write-Host "  [WARN] vswhere cannot find the instance, registering COM DLL..." -ForegroundColor Yellow
    $comDll = Get-ChildItem "C:\ProgramData\Microsoft\VisualStudio\Setup" -Recurse -Filter "Microsoft.VisualStudio.Setup.Configuration.Native.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($comDll) {
        & regsvr32.exe /s $comDll
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] COM DLL registered" -ForegroundColor Green
            # Re-verify
            $verified = & $vswhere -prerelease -products * `
                -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                -property installationPath 2>$null | Select-Object -First 1
            if ($verified) {
                $ver = & $vswhere -prerelease -products * `
                    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
                    -property installationVersion 2>$null | Select-Object -First 1
                Show-InstallComplete -Tool "VS Build Tools" -Version $ver
            } else {
                Write-Host "  [WARN] vswhere still cannot find instance" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [WARN] regsvr32 failed (exit code $LASTEXITCODE)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] COM DLL not found" -ForegroundColor Yellow
    }
}

} catch {
    Write-Host "  [ERROR] $_" -ForegroundColor Red
    exit 1
} finally {
    Stop-Transcript | Out-Null
}
