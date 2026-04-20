#Requires -Version 5.1

<#
.SYNOPSIS
    Check PSScriptAnalyzer module status.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

& "$PSScriptRoot\check-module.ps1" -ModuleName "PSScriptAnalyzer"
