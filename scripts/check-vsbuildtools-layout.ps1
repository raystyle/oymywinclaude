#Requires -Version 5.1
<#
.SYNOPSIS
    Check VS Build Tools offline layout status
.DESCRIPTION
    Checks if the VS Build Tools layout exists at D:\DevSetup\VSBuildTools\Layout
    and shows its size and contents.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$layoutDir = $script:VSBuildTools_LayoutDir
$bootstrapper = $script:VSBuildTools_Bootstrapper

Write-Host ""
Write-Host "  VS Build Tools Layout Status" -ForegroundColor White
Write-Host "  =============================" -ForegroundColor DarkGray
Write-Host ""

$bootstrapperExists = Test-Path $bootstrapper
$layoutExists = Test-Path $layoutDir

if (-not $bootstrapperExists -and -not $layoutExists) {
    Write-Host "  [ ] Layout: NOT FOUND" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Create layout first with:" -ForegroundColor DarkGray
    Write-Host "    just create-vsbuildtools-layout" -ForegroundColor Cyan
    exit 0
}

# Show bootstrapper status
if ($bootstrapperExists) {
    $bootstrapperSize = (Get-Item $bootstrapper).Length / 1MB
    Write-Host "  [OK] Bootstrapper: $bootstrapper ($([Math]::Round($bootstrapperSize, 2)) MB)" -ForegroundColor Green
} else {
    Write-Host "  [ ] Bootstrapper: NOT FOUND" -ForegroundColor Red
}

# Show layout status
if ($layoutExists) {
    $layoutSize = (Get-ChildItem $layoutDir -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum / 1GB
    Write-Host "  [OK] Layout: $layoutDir ($([Math]::Round($layoutSize, 2)) GB)" -ForegroundColor Green

    # Check for bootstrapper in layout (idempotent verification)
    $layoutBootstrapper = Join-Path $layoutDir "vs_buildtools.exe"

    if (Test-Path $layoutBootstrapper) {
        Write-Host "  [OK] Layout: COMPLETE" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Ready to install with:" -ForegroundColor DarkGray
        Write-Host "    just install-vsbuildtools" -ForegroundColor Cyan
    } else {
        Write-Host "  [WARN] Layout: INCOMPLETE" -ForegroundColor Yellow
        Write-Host "  Missing components:" -ForegroundColor DarkGray
        Write-Host "    - vs_buildtools.exe" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  [ ] Layout: NOT FOUND" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Create layout with:" -ForegroundColor DarkGray
    Write-Host "    just create-vsbuildtools-layout" -ForegroundColor Cyan
}
