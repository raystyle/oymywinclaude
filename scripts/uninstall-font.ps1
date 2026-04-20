#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall user-level fonts by removing files and registry entries.
.PARAMETER FontName
    Font family name (used for logging)
.PARAMETER FilePattern
    Regex pattern to match registry entries and font files to remove
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FontName,

    [string]$FilePattern = ""
)

if (-not $FilePattern) { $FilePattern = $FontName }

$userFontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regPath     = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

Write-Host "--- Uninstalling $FontName Fonts ---" -ForegroundColor Cyan

# ---- 1. Remove registry entries ----
$regRemoved = 0
if (Test-Path $regPath) {
    $regEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    if ($regEntries) {
        $matching = @($regEntries.PSObject.Properties |
            Where-Object { $_.Name -match $FilePattern -or $_.Value -match $FilePattern })

        foreach ($entry in $matching) {
            Remove-ItemProperty -Path $regPath -Name $entry.Name -Force -ErrorAction SilentlyContinue
            $regRemoved++
        }
    }
}

if ($regRemoved -gt 0) {
    Write-Host "[OK] Removed $regRemoved registry entries" -ForegroundColor Green
}
else {
    Write-Host "[OK] No matching registry entries found" -ForegroundColor Gray
}

# ---- 2. Remove font files ----
$filesRemoved = 0
if (Test-Path $userFontDir) {
    $fontFiles = @(Get-ChildItem -Path $userFontDir -Include '*.ttf', '*.otf' -Recurse |
        Where-Object { $_.BaseName -match $FilePattern })

    foreach ($f in $fontFiles) {
        try {
            Remove-Item -Path $f.FullName -Force -ErrorAction Stop
            $filesRemoved++
        }
        catch {
            Write-Host "[WARN] Could not delete: $($f.Name) - $_" -ForegroundColor Yellow
        }
    }
}

if ($filesRemoved -gt 0) {
    Write-Host "[OK] Deleted $filesRemoved font files from $userFontDir" -ForegroundColor Green
}
else {
    Write-Host "[OK] No matching font files found in $userFontDir" -ForegroundColor Gray
}

# ---- 3. Summary ----
if ($regRemoved -gt 0 -or $filesRemoved -gt 0) {
    Write-Host "[OK] $FontName fonts uninstalled. Restart your terminal for changes to take effect." -ForegroundColor Green
}
else {
    Write-Host "[OK] $FontName was not installed, nothing to do." -ForegroundColor Gray
}
