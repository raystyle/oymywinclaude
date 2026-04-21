#Requires -Version 5.1

<#
.SYNOPSIS
    Check tool installation status, PATH, and available updates
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Repo', Justification = 'Kept for CLI compatibility')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TagPrefix', Justification = 'Kept for CLI compatibility')]
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^/]+/[^/]+$')]
    [string]$Repo,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExeName,

    [string]$TagPrefix = "",

    [string]$ProfileLine = "",

    [string]$ProfileLabel = ""
)

. "$PSScriptRoot\helpers.ps1"

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\$ExeName"

# Get tool name without .exe extension
$toolName = $ExeName -replace '\.exe$', ''

Write-Host "--- $toolName ---" -ForegroundColor Cyan

if (-not (Test-Path $exePath)) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-$($toolName.ToLower())' to install" -ForegroundColor DarkGray
    return
}

# Current version
$raw = & $exePath --version 2>&1 | Out-String
$current = 'unknown'
if ($raw -match '(\d+\.\d+\.\d+)') {
    $current = $Matches[1]
}
Write-Host "[OK] $current" -ForegroundColor Green
Write-Host "  Location:        $exePath" -ForegroundColor DarkGray

# PATH scope
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "machine" }
         elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "user" }
         else { $null }
if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }

# Check profile configuration
if ($ProfileLine -and $ProfileLabel) {
    Show-ProfileStatus -Line $ProfileLine -Label $ProfileLabel
}
