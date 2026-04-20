#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Go (D:\DevEnvs\Go)
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$GoDir = "D:\DevEnvs\Go"

if (-not (Test-Path $GoDir)) {
    Write-Host "[INFO] Go is not installed" -ForegroundColor Cyan
    return
}

Write-Host "[INFO] Removing Go installation..." -ForegroundColor Cyan

# Remove from PATH
Remove-UserPath -Dir "$GoDir\bin"

# Remove directory
try {
    Remove-Item -Path $GoDir -Recurse -Force -ErrorAction Stop
    Write-Host "[OK] Go removed from $GoDir" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to remove Go: $_" -ForegroundColor Red
    exit 1
}

# Remove environment variables
try {
    [Environment]::SetEnvironmentVariable("GO111MODULE", $null, "User")
    Write-Host "[OK] Removed GO111MODULE environment variable" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Failed to remove GO111MODULE: $_" -ForegroundColor Yellow
}

try {
    [Environment]::SetEnvironmentVariable("GOPROXY", $null, "User")
    Write-Host "[OK] Removed GOPROXY environment variable" -ForegroundColor Green
}
catch {
    Write-Host "[WARN] Failed to remove GOPROXY: $_" -ForegroundColor Yellow
}

Write-Host "[OK] Go uninstall completed!" -ForegroundColor Green
