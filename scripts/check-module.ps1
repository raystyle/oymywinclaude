#Requires -Version 5.1

<#
.SYNOPSIS
    Check PowerShell module installation status in user module directories
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName
)

. "$PSScriptRoot\helpers.ps1"

Write-Host "--- $ModuleName (PS Module) ---" -ForegroundColor Cyan

$ps7Dir = "$HOME\Documents\PowerShell\Modules\$ModuleName"
$ps5Dir = "$HOME\Documents\WindowsPowerShell\Modules\$ModuleName"

$moduleLocations = @()

foreach ($item in @(
    @{ Path = $ps7Dir; Label = "PS7" }
    @{ Path = $ps5Dir; Label = "PS5" }
)) {
    if (Test-Path $item.Path) {
        $versions = @(Get-ChildItem -Path $item.Path -Directory |
            Where-Object { Test-Path "$($_.FullName)\$ModuleName.psd1" } |
            Select-Object -ExpandProperty Name)
        if ($versions.Count -gt 0) {
            Write-Host "  $($item.Label):         installed ($($versions -join ', '))" -ForegroundColor DarkGray
            $moduleLocations += $item.Path
        }
        else {
            Write-Host "  $($item.Label):         directory exists but no valid module found" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "  $($item.Label):         NOT installed" -ForegroundColor DarkGray
    }
}

# Show all module locations
if ($moduleLocations.Count -gt 0) {
    foreach ($location in $moduleLocations) {
        Write-Host "  Location:        $location" -ForegroundColor DarkGray
    }
}

# Check if importable in current session
try {
    $mod = Get-Module -ListAvailable -Name $ModuleName -ErrorAction Stop | Select-Object -First 1
    if ($mod) {
        Write-Host "  Importable:       $($mod.Name) $($mod.Version)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Importable:       NOT found" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host "  Importable: check failed" -ForegroundColor DarkGray
}

# Check profile configuration
if ($ModuleName -eq "PSFzf") {
    Show-ProfileStatus -Line "Import-Module PSFzf" -Label "PSFzf import"
}
