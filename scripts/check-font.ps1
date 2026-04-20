#Requires -Version 5.1

<#
.SYNOPSIS
    Check font installation status via registry
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FontName,

    [string]$FilePattern = ""
)

if (-not $FilePattern) { $FilePattern = $FontName }

Write-Host "--- $FontName ---" -ForegroundColor Cyan

$regPath = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
if (-not (Test-Path $regPath)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-font' to install" -ForegroundColor DarkGray
    return
}

$regEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
$found = @()
if ($regEntries) {
    $found = @($regEntries.PSObject.Properties |
        Where-Object { $_.Name -match $FilePattern -or $_.Value -match $FilePattern })
}

if ($found.Count -gt 0) {
    Write-Host "[OK] $($found.Count) font entries registered" -ForegroundColor Green

    # Show first 3 fonts
    $displayCount = [Math]::Min(3, $found.Count)
    for ($i = 0; $i -lt $displayCount; $i++) {
        Write-Host "  $($found[$i].Name)" -ForegroundColor DarkGray
    }

    # Show ellipsis if there are more
    if ($found.Count -gt 3) {
        $remaining = $found.Count - 3
        Write-Host "  ... ($remaining more)" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-font' to install" -ForegroundColor DarkGray
}
