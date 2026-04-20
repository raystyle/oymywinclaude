#Requires -Version 5.1
<#
.SYNOPSIS
    Check VS Build Tools installation status (MSVC compiler + Windows SDK)
.DESCRIPTION
    Uses vswhere as primary detection, filesystem as fallback.
    Also reports COM DLL registration status (required for vswhere).
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$InstallRoot = $script:VSBuildTools_InstallPath
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

Write-Host "--- VS Build Tools ---" -ForegroundColor Cyan

# -- 1. vswhere detection --
$installPath = $null
$installVersion = $null

if (Test-Path $vswhere) {
    $installPath = & $vswhere -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null | Select-Object -First 1
    $installVersion = & $vswhere -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationVersion 2>$null | Select-Object -First 1
}

# -- 2. Filesystem fallback --
if (-not $installPath) {
    $cl = Get-ChildItem "$InstallRoot\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cl) { $installPath = $InstallRoot }
}

if (-not $installPath) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-vsbuildtools' to install" -ForegroundColor DarkGray
    Write-Host ""
    return
}

Write-Host "[OK]" -ForegroundColor Green
Write-Host "  Location:        $installPath" -ForegroundColor DarkGray

if ($installVersion) {
    Write-Host "  Version:         $installVersion" -ForegroundColor DarkGray
}

# -- 3. MSVC compiler --
$msvcDir = Get-ChildItem "$installPath\VC\Tools\MSVC" -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+' } |
    Select-Object -First 1

if ($msvcDir) {
    Write-Host "  MSVC:            $($msvcDir.Name)" -ForegroundColor DarkGray
} else {
    Write-Host "  MSVC:            not found" -ForegroundColor DarkGray
}

# -- 4. link.exe (linker) --
$linkExe = Get-ChildItem "$installPath\VC\Tools\MSVC" -Recurse -Filter "link.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.DirectoryName -match 'Hostx64\\x64' } |
    Select-Object -First 1

if ($linkExe) {
    Write-Host "  link.exe:        OK" -ForegroundColor DarkGray
} else {
    Write-Host "  link.exe:        not found" -ForegroundColor DarkGray
}

# -- 5. Windows SDK --
$kitsRoot = $null
foreach ($reg in @(
    "HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots"
)) {
    if (Test-Path $reg) {
        $obj = Get-ItemProperty $reg -ErrorAction SilentlyContinue
        if ($obj -and $obj.PSObject.Properties['KitsRoot10']) {
            $r = $obj.KitsRoot10
            if ($r -and (Test-Path $r)) { $kitsRoot = $r; break }
        }
    }
}

$sdkVersion = $null
if ($kitsRoot -and (Test-Path "$kitsRoot\Include")) {
    $sdkDir = Get-ChildItem "$kitsRoot\Include" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($sdkDir) { $sdkVersion = $sdkDir.Name }
}

if ($sdkVersion) {
    Write-Host "  Windows SDK: $sdkVersion" -ForegroundColor DarkGray
} else {
    Write-Host "  Windows SDK: not found" -ForegroundColor DarkGray
}

# -- 6. COM DLL status (vswhere dependency) --
$comDll = Get-ChildItem "C:\ProgramData\Microsoft\VisualStudio\Setup" -Recurse -Filter "Microsoft.VisualStudio.Setup.Configuration.Native.dll" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (Test-Path $comDll) {
    Write-Host "  COM DLL: OK" -ForegroundColor DarkGray
} else {
    Write-Host "  COM DLL: not found (vswhere may not work)" -ForegroundColor DarkGray
}

# -- 7. vswhere status hint --
if (-not (Test-Path $vswhere)) {
    Write-Host "  vswhere: not found" -ForegroundColor DarkGray
} elseif (-not $installVersion) {
    Write-Host "  vswhere: instance not registered (filesystem detection)" -ForegroundColor Yellow
}

# -- 8. Disk usage --
if (Test-Path $installPath) {
    $size = (Get-ChildItem $installPath -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($size) {
        Write-Host "  Disk: $([Math]::Round($size / 1GB, 2)) GB" -ForegroundColor DarkGray
    }
}
