#Requires -Version 5.1

<#
.SYNOPSIS
    Check TypeScript LSP binary status
#>

[CmdletBinding()]
param()

$nodeDir = "D:\DevEnvs\node"
$shimExePath = "$env:USERPROFILE\.local\bin\typescript-language-server.exe"
$cliMjs  = Join-Path $nodeDir "node_modules\typescript-language-server\lib\cli.mjs"

Write-Host "--- TypeScript LSP ---" -ForegroundColor Cyan

if ((Test-Path $shimExePath) -and (Test-Path $cliMjs)) {
    $output = & $shimExePath --version 2>&1 | Out-String
    $version = if ($output -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { "unknown" }
    Write-Host "[OK] $version" -ForegroundColor Green
    Write-Host "  Shim:            $shimExePath" -ForegroundColor DarkGray
    Write-Host "  Location:        $cliMjs" -ForegroundColor DarkGray
    Write-Host "  PATH:            user" -ForegroundColor DarkGray
}
else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-typescript-lsp' to install" -ForegroundColor DarkGray
}
