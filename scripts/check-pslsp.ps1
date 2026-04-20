#Requires -Version 5.1

<#
.SYNOPSIS
    Check PowerShellEditorServices module status.
#>

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"

& "$PSScriptRoot\check-module.ps1" -ModuleName "PowerShellEditorServices"
