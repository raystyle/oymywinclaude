#Requires -Version 5.1

<#
.SYNOPSIS
    Check TypeScript LSP binary status
#>

[CmdletBinding()]
param()

$nodeDir = "D:\DevEnvs\node"
$binDir  = "$env:USERPROFILE\.local\bin"

Write-Host "--- TypeScript LSP ---" -ForegroundColor Cyan

# Check typescript-language-server shim
$shimExePath = "$binDir\typescript-language-server.exe"
$cliMjs      = Join-Path $nodeDir "node_modules\typescript-language-server\lib\cli.mjs"

if ((Test-Path $shimExePath) -and (Test-Path $cliMjs)) {
    $output = & $shimExePath --version 2>&1 | Out-String
    $version = if ($output -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
    Write-Host "[OK] typescript-language-server $version" -ForegroundColor Green
    Write-Host "  Shim:            $shimExePath" -ForegroundColor DarkGray
    Write-Host "  Location:        $cliMjs" -ForegroundColor DarkGray
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-typescript-lsp' to install" -ForegroundColor DarkGray
}

# Check tsc shim
$tscShimPath = "$binDir\tsc.exe"
if (Test-Path $tscShimPath) {
    $output = & $tscShimPath --version 2>&1 | Out-String
    $version = if ($output -match 'Version\s+([\d.]+)') { $Matches[1] } else { "unknown" }
    Write-Host "[OK] tsc $version" -ForegroundColor Green
    Write-Host "  Shim:            $tscShimPath" -ForegroundColor DarkGray
}
else {
    Write-Host "[NOT INSTALLED] tsc" -ForegroundColor Red
}

# Check tsserver shim
$tssShimPath = "$binDir\tsserver.exe"
if (Test-Path $tssShimPath) {
    Write-Host "[OK] tsserver (LSP protocol, no CLI version)" -ForegroundColor Green
    Write-Host "  Shim:            $tssShimPath" -ForegroundColor DarkGray
}
else {
    Write-Host "[NOT INSTALLED] tsserver" -ForegroundColor Red
}
