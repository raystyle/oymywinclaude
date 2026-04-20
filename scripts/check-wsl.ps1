#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$DistroName,

    [string]$ExpectedUser = "",

    [switch]$Detailed
)

. "$PSScriptRoot\helpers.ps1"

# Error action preference
$ErrorActionPreference = "Stop"

Write-Host "--- WSL: $DistroName ---" -ForegroundColor Cyan

# 1. Check if distro exists
$wslOutput = wsl.exe -l -v 2>$null
$wslList = $wslOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
# Simple check - just look for the distro name characters
$distroInfo = $wslList | Where-Object {
    # Extract just the alphanumeric characters and basic hyphens
    $cleanLine = $_ -replace '[^a-zA-Z0-9\-\*]', ''
    $cleanLine -like "*$DistroName*"
}

if (-not $distroInfo) {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-wsl' to install" -ForegroundColor DarkGray
    exit 1
}

# 2. Parse distro info
if ($distroInfo) {
    # Clean unicode characters for parsing
    $cleanInfo = $distroInfo -replace '[^a-zA-Z0-9\-\*\s]', '' -replace '\s+', ' '

    # Parse the cleaned string: "*ai-linux Stopped 2"
    if ($cleanInfo -match '(\*?[a-zA-Z0-9\-]+)\s+([a-zA-Z]+)\s+(\d+)') {
        $name = $Matches[1] -replace '\*', ''  # Remove leading *
        $state = $Matches[2]
        $version = $Matches[3]

        if ($state -eq "Running") {
            Write-Host "[OK] (running)" -ForegroundColor Green
        } else {
            Write-Host "[OK] ($state)" -ForegroundColor Green
        }

        Write-Host "  Name: $name" -ForegroundColor DarkGray
        Write-Host "  State: $state" -ForegroundColor DarkGray
        Write-Host "  WSL Version: $version" -ForegroundColor DarkGray
    } else {
        Write-Host "[OK]" -ForegroundColor Green
        Write-Host "  Name: $DistroName" -ForegroundColor DarkGray
        Write-Host "  State: Unknown" -ForegroundColor DarkGray
        $state = "Unknown"
    }
}

# 3. Check default user
if ($Detailed -or $ExpectedUser) {
    Write-Host "  User configuration:" -ForegroundColor DarkGray

    try {
        $currentUser = wsl -d $DistroName whoami 2>$null
        if ($currentUser) {
            Write-Host "    Default user: $currentUser" -ForegroundColor DarkGray

            if ($ExpectedUser -and $currentUser -eq $ExpectedUser) {
                Write-Host "    Status: OK" -ForegroundColor DarkGray
            } elseif ($ExpectedUser) {
                Write-Host "    Status: mismatch (current=$currentUser, expected=$ExpectedUser)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "    Default user: cannot get information" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "    Default user: check failed" -ForegroundColor DarkGray
    }
}

# 5. Check sudo configuration
if ($Detailed) {
    Write-Host "  Sudo configuration:" -ForegroundColor DarkGray

    try {
        $sudoTest = wsl -d $DistroName sudo whoami 2>$null
        if ($sudoTest -eq "root") {
            Write-Host "    Passwordless sudo: OK" -ForegroundColor DarkGray
        } else {
            Write-Host "    Passwordless sudo: may not be configured" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "    Passwordless sudo: check failed" -ForegroundColor DarkGray
    }
}

# 6. Check environment information
if ($Detailed) {
    Write-Host "  Environment:" -ForegroundColor DarkGray

    try {
        $bashCommand = @'
	cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"'
'@
        $osRelease = wsl -d $DistroName bash -c $bashCommand 2>$null
        if ($osRelease) {
            Write-Host "    OS: $osRelease" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "    OS: cannot get information" -ForegroundColor DarkGray
    }

    try {
        $kernelVersion = wsl -d $DistroName uname -r 2>$null
        if ($kernelVersion) {
            Write-Host "    Kernel: $kernelVersion" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "    Kernel: cannot get information" -ForegroundColor DarkGray
    }
}

exit 0
