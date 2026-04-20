#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall jq - Command-line JSON processor
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

& "$PSScriptRoot\uninstall-tool.ps1" -ExeName "jq.exe"
