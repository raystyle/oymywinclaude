#Requires -Version 5.1

<#
.SYNOPSIS
    Generic tool uninstaller. Removes executable from ~/.local/bin
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ExeName,

    [switch]$Force
)

$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\$ExeName"

$removed = $false
if (Test-Path $exePath) {
    try {
        Remove-Item $exePath -Force -ErrorAction Stop
        Write-Host "[OK] Removed: $exePath" -ForegroundColor Green
        $removed = $true
    }
    catch {
        $hresult = $_.Exception.HResult
        # 0x80070020 = ERROR_SHARING_VIOLATION (file locked by another process)
        if ($hresult -eq -2147024864) {
            Write-Host "[WARN] $ExeName is locked (in use by another process)." -ForegroundColor Yellow
            Write-Host "       Close all terminals/sessions, then manually delete:" -ForegroundColor Yellow
            Write-Host "       $exePath" -ForegroundColor White
            Write-Host "       Or run: cmd /c del `"$exePath`"" -ForegroundColor Cyan
        }
        else {
            Write-Host "[WARN] Could not remove $ExeName : $_" -ForegroundColor Yellow
            Write-Host "       Manually delete: $exePath" -ForegroundColor White
        }
        # exit 0 so that `just` continues with remaining uninstall tasks
    }
}
else {
    Write-Host "[SKIP] $exePath does not exist" -ForegroundColor DarkGray
    $removed = $true
}

if ($removed) {
    Write-Host "[OK] $ExeName uninstalled" -ForegroundColor Green
}
Write-Host "     ~/.local/bin and PATH preserved (other tools may use them)" -ForegroundColor DarkGray
