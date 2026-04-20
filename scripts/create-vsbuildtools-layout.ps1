#Requires -Version 5.1
<#
.SYNOPSIS
    Create VS Build Tools offline layout for installation
.DESCRIPTION
    Downloads VS Build Tools bootstrapper and creates an offline layout
    at D:\DevSetup\VSBuildTools\Layout with MSVC + Windows SDK components.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ── Configuration ──
$script:LayoutDir    = $script:VSBuildTools_LayoutDir
$script:CacheDir     = $script:VSBuildTools_CacheDir
$script:Bootstrapper = $script:VSBuildTools_Bootstrapper
$script:TimeoutMs     = 3600000  # 60 minutes (layout creation can be large)

Write-Host ""
Write-Host "  VS Build Tools Layout Creation" -ForegroundColor White
Write-Host "  ===============================" -ForegroundColor DarkGray
Write-Host ""

# ── Step 0: Idempotent check ──
$layoutBootstrapper = Join-Path $script:LayoutDir "vs_buildtools.exe"
if (Test-Path $layoutBootstrapper) {
    Show-AlreadyInstalled -Tool "VS Build Tools Layout" -Location $script:LayoutDir
    Write-Host "  [INFO] You can proceed with: just install-vsbuildtools" -ForegroundColor Cyan
    exit 0
}

# ── Step 1: Create directories ──
Write-Host "  [INFO] Creating directories..." -ForegroundColor Cyan
$null = New-Item -Path $script:LayoutDir -ItemType Directory -Force
$null = New-Item -Path $script:CacheDir -ItemType Directory -Force
Write-Host "  [OK] Directories created" -ForegroundColor Green

# ── Step 2: Download bootstrapper ──
Write-Host ""
Write-Host "  [INFO] Downloading VS Build Tools bootstrapper..." -ForegroundColor Cyan

$bootstrapperUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"

if (-not (Test-Path $script:Bootstrapper)) {
    Write-Host "  URL: $bootstrapperUrl" -ForegroundColor DarkGray
    Save-WithProxy -Url $bootstrapperUrl -OutFile $script:Bootstrapper
    Write-Host "  [OK] Downloaded to $script:Bootstrapper" -ForegroundColor Green
} else {
    Write-Host "  [OK] Bootstrapper already exists: $script:Bootstrapper" -ForegroundColor Green
}

# ── Step 3: Create layout ──
Write-Host ""
Write-Host "  [INFO] Creating offline layout..." -ForegroundColor Cyan
Write-Host "  Layout:   $script:LayoutDir" -ForegroundColor DarkGray
Write-Host "  Cache:    $script:CacheDir" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [INFO] This will download ~3-5 GB and may take 10-30 minutes..." -ForegroundColor Yellow
Write-Host ""

$layoutArgs = @(
    "--layout", $script:LayoutDir,
    "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22621",
    "--add", "Microsoft.VisualStudio.Component.Windows11SDK.26100",
    "--includeRecommended",
    "--lang", "en-US",
    "--passive", "--wait"
)

$proc = Start-Process -FilePath $script:Bootstrapper -ArgumentList $layoutArgs `
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
    Write-Host "  [ERROR] Layout creation timed out ($([Math]::Round($script:TimeoutMs / 60000)) min)" -ForegroundColor Red
    exit 1
}

switch ($proc.ExitCode) {
    0 {
        Write-Host ""
        Write-Host "  [OK] Layout created successfully" -ForegroundColor Green
        Write-Host "  Location: $script:LayoutDir" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [INFO] You can now install with: just install-vsbuildtools" -ForegroundColor Cyan
    }
    default {
        Write-Host ""
        Write-Host "  [ERROR] Layout creation failed (exit code $($proc.ExitCode))" -ForegroundColor Red
        Write-Host "  Check logs: %TEMP%\dd_*.log" -ForegroundColor DarkGray
        exit 1
    }
}
