#Requires -Version 5.1

<#
.SYNOPSIS
    Check mq, mq-crawl, mq-lsp and mq-check installation status
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

$binDir = "$env:USERPROFILE\.local\bin"

function Show-ToolStatus {
    param(
        [string]$ToolName,
        [string]$ExeName,
        [switch]$NoNewLine
    )

    $exePath = "$binDir\$ExeName"

    Write-Host "--- $ToolName ---" -ForegroundColor Cyan

    if (-not (Test-Path $exePath)) {
        Write-Host "[NOT INSTALLED]" -ForegroundColor Red
        Write-Host "  Run 'just install-mq' to install" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Get version
    try {
        $job = Start-Job -ScriptBlock {
            param($exePath)
            & $exePath "--version"
        } -ArgumentList $exePath

        $version = Wait-Job $job | Receive-Job
        Remove-Job $job

        if ($version -match '(\d+\.\d+\.\d+)') {
            $versionStr = $matches[1]
        }
        else {
            $versionStr = "unknown"
        }
    }
    catch {
        $versionStr = "error"
    }

    Write-Host "[OK] $versionStr" -ForegroundColor Green
    Write-Host "  Location:        $exePath" -ForegroundColor DarkGray

    # PATH scope
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $scope = if ($machinePath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "machine" }
             elseif ($userPath -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' -and $_ -eq $binDir.TrimEnd('\') }) { "user" }
             else { $null }
    if ($scope) { Write-Host "  PATH:            $scope" -ForegroundColor DarkGray }
    else { Write-Host "  PATH:            not configured" -ForegroundColor Yellow }

    if (-not $NoNewLine) {
        Write-Host ""
    }
}

Show-ToolStatus -ToolName "mq" -ExeName "mq.exe" -NoNewLine
Show-ToolStatus -ToolName "mq-crawl" -ExeName "mq-crawl.exe" -NoNewLine
Show-ToolStatus -ToolName "mq-lsp" -ExeName "mq-lsp.exe" -NoNewLine
Show-ToolStatus -ToolName "mq-check" -ExeName "mq-check.exe"
