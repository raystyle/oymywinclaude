#Requires -Version 5.1

<#
.SYNOPSIS
    Download and install fonts from a zip URL (user-level, no admin required).
.DESCRIPTION
    - Downloads zip to temp, extracts, installs matching .ttf/.otf to user font dir.
    - Registers each font in HKCU registry so Windows picks them up without reboot.
    - Idempotent: skips if fonts already registered.
.PARAMETER Url
    Direct download URL for the font zip archive
.PARAMETER FontName
    Display name used for logging and temp file naming
.PARAMETER FilePattern
    Regex pattern to filter which font files to install from the archive.
    Defaults to FontName. Use this to pick specific variants (e.g. "NF" for Nerd Font).
.PARAMETER SubDir
    Subdirectory inside the zip to look for fonts (e.g. "ttf" to skip otf/woff2).
    If empty, searches the entire archive.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Url,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$FontName,

    [string]$FilePattern = "",

    [string]$SubDir = ""
)

. "$PSScriptRoot\helpers.ps1"

if (-not $FilePattern) { $FilePattern = $FontName }

$userFontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$regPath     = "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"

# Ensure registry path exists
if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# ---- 1. Idempotent check via registry ----
$regEntries = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
$found = @()
if ($regEntries) {
    $found = @($regEntries.PSObject.Properties |
        Where-Object { $_.Name -match $FilePattern -or $_.Value -match $FilePattern })
}
if ($found.Count -gt 0) {
    Write-Host "[OK] $FontName fonts already installed ($($found.Count) entries in registry)" -ForegroundColor Green
    return
}

# ---- 2. Download ----
$zipFile = "$env:TEMP\$FontName.zip"
Write-Host "[INFO] Downloading $FontName fonts..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $Url -OutFile $zipFile -CacheDir "fonts"
}
catch {
    Write-Host "[ERROR] Download failed: $_" -ForegroundColor Red
    exit 1
}

# ---- 3. Extract to temp ----
$extractDir = "$env:TEMP\$FontName-extract"
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force
}
try {
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Extract failed: $_" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 4. Locate font files ----
$searchRoot = $extractDir
if ($SubDir) {
    # Find the subdir (may be nested under a version folder like CascadiaCode-2407.24/ttf/)
    $candidates = Get-ChildItem -Path $extractDir -Directory -Recurse -Filter $SubDir
    if ($candidates.Count -gt 0) {
        $searchRoot = $candidates[0].FullName
    }
    else {
        Write-Host "[WARN] SubDir '$SubDir' not found in archive, searching entire archive" -ForegroundColor Yellow
    }
}

$fontFiles = @(Get-ChildItem -Path $searchRoot -Recurse -Include '*.ttf', '*.otf' |
    Where-Object { $_.BaseName -match $FilePattern })

if ($fontFiles.Count -eq 0) {
    Write-Host "[WARN] No font files matching '$FilePattern' found in archive" -ForegroundColor Yellow
    # Fallback: list what's available
    $allFonts = Get-ChildItem -Path $extractDir -Recurse -Include '*.ttf', '*.otf'
    if ($allFonts.Count -gt 0) {
        Write-Host "       Available fonts in archive:" -ForegroundColor DarkGray
        $allFonts | ForEach-Object { Write-Host "         $($_.Name)" -ForegroundColor DarkGray }
    }
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. Install fonts (user-level) ----
if (-not (Test-Path $userFontDir)) {
    New-Item -ItemType Directory -Path $userFontDir -Force | Out-Null
}

# Use Shell.Application to get the real font name from the file metadata
$shell = New-Object -ComObject Shell.Application
$count = 0

foreach ($font in $fontFiles) {
    $dest = Join-Path $userFontDir $font.Name
    Copy-Item -Path $font.FullName -Destination $dest -Force -ErrorAction Stop

    # Extract real font name from file metadata (index 21 = Title on most Windows versions)
    $folder   = $shell.Namespace($font.DirectoryName)
    $fileItem = $folder.ParseName($font.Name)
    $title    = $folder.GetDetailsOf($fileItem, 21)  # "Title" column

    if (-not $title) {
        # Fallback: derive from filename
        $title = $font.BaseName -replace '[-_]', ' '
    }

    # Determine suffix
    $ext = $font.Extension.ToLower()
    $suffix = switch ($ext) {
        '.ttf' { '(TrueType)' }
        '.otf' { '(OpenType)' }
        default { '(TrueType)' }
    }
    $regName = "$title $suffix"

    New-ItemProperty -Path $regPath -Name $regName -Value $dest -PropertyType String -Force | Out-Null
    $count++
}

[System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

# ---- 6. Cleanup ----
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

if ($count -gt 0) {
    Write-Host "[OK] Installed $count font files for $FontName" -ForegroundColor Green
    Write-Host "     Location: $userFontDir" -ForegroundColor DarkGray
    Write-Host "     Restart your terminal to use the new fonts" -ForegroundColor DarkGray
}
else {
    Write-Host "[WARN] No font files were installed" -ForegroundColor Yellow
}
