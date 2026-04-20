#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall PSScriptAnalyzer module from both PS5 and PS7.
#>

[CmdletBinding()]
param()

& "$PSScriptRoot\uninstall-module.ps1" -ModuleName "PSScriptAnalyzer"
