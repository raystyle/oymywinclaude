#Requires -Version 5.1

<#
.SYNOPSIS
    Configure VS Code to use CaskaydiaCove Nerd Font
.DESCRIPTION
    Sets terminal and editor font in VS Code settings.json.
    Preserves all existing settings. Creates settings.json if missing.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$settingsPath = "$env:APPDATA\Code\User\settings.json"

Write-Host ""
Write-Host "=== Configure VS Code Font ===" -ForegroundColor Cyan
Write-Host ""

# Font values
$fontSettings = @{
    "terminal.integrated.fontFamily" = "'CaskaydiaCove Nerd Font Mono', monospace"
    "editor.fontFamily"              = "'CaskaydiaCove Nerd Font', Consolas, 'Courier New', monospace"
    "editor.fontLigatures"           = $true
}

# ---- Helper: set a nested property on a PSCustomObject ----
function Set-NestedProperty {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Value
    )

    $parts   = $Key.Split('.')
    $current = $Object

    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        if ($null -eq $current) { return }
        $part = $parts[$i]
        $prop = $current.PSObject.Properties[$part]
        if (-not $prop) {
            $newObj = [PSCustomObject]@{}
            $current | Add-Member -NotePropertyName $part -NotePropertyValue $newObj -Force
            $current = $newObj
        }
        else {
            $current = $prop.Value
        }
    }

    $lastPart = $parts[-1]
    if ($current.PSObject.Properties[$lastPart]) {
        $current.$lastPart = $Value
    }
    else {
        $current | Add-Member -NotePropertyName $lastPart -NotePropertyValue $Value -Force
    }
}

# ---- 1. Read existing settings or create empty ----
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host "[INFO] Reading existing settings: $settingsPath" -ForegroundColor Cyan
    }
    catch {
        Write-Host "[WARN] Failed to parse settings.json (may contain comments): $_" -ForegroundColor Yellow
        Write-Host "[INFO] Creating fresh settings.json" -ForegroundColor Cyan
        $settings = [PSCustomObject]@{}
    }
}
else {
    $dir = Split-Path $settingsPath -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $settings = [PSCustomObject]@{}
    Write-Host "[INFO] Creating new settings.json" -ForegroundColor Cyan
}

# ---- 2. Apply font settings ----
foreach ($key in $fontSettings.Keys) {
    Set-NestedProperty -Object $settings -Key $key -Value $fontSettings[$key]
    Write-Host "[OK] Set $key" -ForegroundColor Green
}

# ---- 3. Write back ----
try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)
    Write-Host "[OK] Saved: $settingsPath" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to save settings: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[INFO] Restart VS Code and open a terminal to see the font changes." -ForegroundColor Cyan
Write-Host ""
