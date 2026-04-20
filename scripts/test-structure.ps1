#Requires -Version 5.1

<#
.SYNOPSIS
    Validate structure of all PowerShell scripts in the project.
.DESCRIPTION
    Checks that every .ps1 script follows project conventions:
    - #Requires -Version 5.1 header
    - [CmdletBinding()] attribute
    - dot-source helpers.ps1 (except standalone scripts)
    - No direct $PROFILE manipulation (except profile-entry.ps1)
    - Installed scripts have matching check/uninstall scripts
#>

[CmdletBinding()]
param()

$scriptsDir = Split-Path $MyInvocation.MyCommand.Path
$allScripts = Get-ChildItem "$scriptsDir\*.ps1" -Exclude "test-*", "helpers.ps1", "lock-*", "check-lock*"

# Standalone scripts that intentionally don't dot-source helpers.ps1
$standaloneScripts = @(
    'profile-entry'
    'ensure-config'
    'justinit'
    'claude-config'
    'check-font'
    'check-python'
    'check-rust'
    'check-typescript-lsp'
    'uninstall-font'
    'uninstall-playwright-skills'
    'uninstall-tool'
    'install-wsl'
    'uninstall-wsl'
    'uninstall-pslsp'
    'uninstall-psscriptanalyzer'
)

# install-* scripts that use generic check-module/uninstall-module by ModuleName
$genericModuleScripts = @{
    'install-pslsp'           = @{ check = 'check-module'; uninstall = 'uninstall-module'; arg = 'PowerShellEditorServices' }
    'install-psscriptanalyzer' = @{ check = 'check-module'; uninstall = 'uninstall-module'; arg = 'PSScriptAnalyzer' }
    'install-python-lsp'      = @{ check = 'check-python-lsp'; uninstall = 'uninstall-python-lsp'; arg = '' }
}

$errors   = 0
$warnings = 0
$checked  = 0

Write-Host ""
Write-Host "=== Script Structure Validation ===" -ForegroundColor Cyan
Write-Host ""

# ---- 1. Check each script ----
foreach ($script in $allScripts) {
    $name = $script.Name
    $content = Get-Content $script.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        Write-Host "[FAIL] $name : could not read file" -ForegroundColor Red
        $errors++
        continue
    }
    $checked++

    # 1a. #Requires header
    if ($content -notmatch '#Requires -Version 5\.1') {
        Write-Host "[FAIL] $name : missing '#Requires -Version 5.1'" -ForegroundColor Red
        $errors++
    }

    # 1b. CmdletBinding
    if ($content -notmatch '\[CmdletBinding\(\)') {
        Write-Host "[FAIL] $name : missing [CmdletBinding()]" -ForegroundColor Red
        $errors++
    }

    # 1c. dot-source helpers.ps1 (skip standalone scripts)
    $isStandalone = $standaloneScripts | Where-Object { $name -match "^$_" }
    if (-not $isStandalone) {
        if ($content -notmatch '\. "\$PSScriptRoot\\helpers\.ps1"') {
            Write-Host "[FAIL] $name : missing dot-source helpers.ps1" -ForegroundColor Red
            $errors++
        }
    }

    # 1d. No direct $PROFILE manipulation
    if ($name -notmatch 'profile-entry' -and $content -match '\$PROFILE\b' -and $content -notmatch 'Show-ProfileStatus') {
        Write-Host "[WARN] $name : possible direct `$PROFILE usage (use profile-entry.ps1)" -ForegroundColor Yellow
        $warnings++
    }

    # 1e. File ends with newline
    $bytes = [System.IO.File]::ReadAllBytes($script.FullName)
    if ($bytes.Length -gt 0 -and $bytes[-1] -ne 10 -and $bytes[-1] -ne 13) {
        Write-Host "[WARN] $name : file does not end with a newline" -ForegroundColor Yellow
        $warnings++
    }
}

# ---- 2. Check install/check/uninstall pairing ----
Write-Host ""
Write-Host "--- Install/Check/Uninstall Pairing ---" -ForegroundColor Cyan

$installScripts = $allScripts | Where-Object { $_.Name -match '^install-' }
foreach ($inst in $installScripts) {
    $baseName = $inst.Name -replace '^install-', ''

    # Check if this uses generic module scripts
    $generic = $genericModuleScripts["install-$baseName"]

    if ($generic) {
        # Generic module pairing: uses check-module.ps1 / uninstall-module.ps1 with -ModuleName param
        $checkName   = "$($generic.check).ps1"
        $uninstallName = "$($generic.uninstall).ps1"
        $checkExists   = Test-Path "$scriptsDir\$checkName"
        $uninstallExists = Test-Path "$scriptsDir\$uninstallName"

        if ($checkExists -and $uninstallExists) {
            Write-Host "  [OK]  $baseName (generic: $checkName / $uninstallName -ModuleName $($generic.arg))" -ForegroundColor Green
        }
        else {
            $status = "[WARN]"
            $color = "Yellow"
            if (-not $checkExists)   { $status += " missing $checkName"; $warnings++ }
            if (-not $uninstallExists) { $status += " missing $uninstallName"; $warnings++ }
            Write-Host "  $status  $baseName" -ForegroundColor $color
        }
        continue
    }

    $checkExists     = Test-Path "$scriptsDir\check-$baseName"
    $uninstallExists = Test-Path "$scriptsDir\uninstall-$baseName"

    $status = "[OK]"
    $color = "Green"
    if (-not $checkExists) {
        $status = "[WARN] missing check-$baseName"
        $color = "Yellow"
        $warnings++
    }
    if (-not $uninstallExists) {
        if ($status -eq "[OK]") {
            $status = "[WARN] missing uninstall-$baseName"
        }
        else {
            $status += ", missing uninstall-$baseName"
        }
        $color = "Yellow"
        $warnings++
    }
    Write-Host "  $status  $baseName" -ForegroundColor $color
}

# ---- 3. Summary ----
Write-Host ""
$total = $checked
$pass  = $total - $errors
$color = if ($errors -eq 0) { "Green" } else { "Red" }
Write-Host "=== Result: $pass/$total passed, $errors failed, $warnings warnings ===" -ForegroundColor $color
Write-Host ""

exit $errors
