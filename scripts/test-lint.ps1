#Requires -Version 5.1

<#
.SYNOPSIS
    Run PSScriptAnalyzer on all project scripts.
.DESCRIPTION
    Checks all .ps1 files in scripts/ directory for best practices and coding style.
    Uses Invoke-ScriptAnalyzer if available, otherwise reports module not installed.
#>

[CmdletBinding()]
param()

$scriptsDir = Split-Path $MyInvocation.MyCommand.Path
$errors   = 0
$warnings = 0

Write-Host ""
Write-Host "=== PSScriptAnalyzer Lint ===" -ForegroundColor Cyan
Write-Host ""

# Check if PSScriptAnalyzer is available
$module = Get-Module -ListAvailable -Name "PSScriptAnalyzer" -ErrorAction SilentlyContinue |
    Sort-Object Version -Descending | Select-Object -First 1

if (-not $module) {
    Write-Host "[ERROR] PSScriptAnalyzer not installed." -ForegroundColor Red
    Write-Host "  Run 'just install-psscriptanalyzer' to install." -ForegroundColor DarkGray
    exit 1
}

Write-Host "[OK] PSScriptAnalyzer $($module.Version)" -ForegroundColor Green
Write-Host ""

# Rules to exclude (project design decisions that differ from PSScriptAnalyzer defaults)
$excludeRules = @(
    'PSUseShouldProcessForStateChangingFunctions'  # our scripts use CmdletBinding instead
    'PSUseUTF8EncodingForHelpFile'                 # no help files in this project
    'PSReviewUnusedParameter'                      # some params used by external callers
    'PSAvoidUsingWriteHost'                        # intentional: colored console output via Write-Host
    'PSUseBOMForUnicodeEncodedFile'                # intentional: UTF-8 without BOM
    'PSUseSingularNouns'                           # function names chosen for clarity (e.g. Remove-PendingDeleteDirs)
    'PSUseApprovedVerbs'                           # project verb choices (e.g. Refresh-Environment)
    # Note: PSAvoidUsingEmptyCatchBlock is NOT excluded — all catch blocks now have proper error handling
)

# Run analyzer on each script (skip test scripts)
$targetScripts = Get-ChildItem "$scriptsDir\*.ps1" -Exclude "test-*"

foreach ($script in $targetScripts) {
    $results = Invoke-ScriptAnalyzer -Path $script.FullName -ExcludeRule $excludeRules -ErrorAction SilentlyContinue

    if (-not $results -or $results.Count -eq 0) {
        Write-Host "[OK] $($script.Name)" -ForegroundColor Green
    }
    else {
        foreach ($r in $results) {
            $line = if ($r.Line) { ":$($r.Line)" } else { "" }
            $msg = "  $($r.Severity) $($r.RuleName)$line : $($r.Message)"
            if ($r.Severity -eq 'Error') {
                Write-Host "[FAIL] $($script.Name)$msg" -ForegroundColor Red
                $errors++
            }
            elseif ($r.Severity -eq 'Warning') {
                Write-Host "[WARN] $($script.Name)$msg" -ForegroundColor Yellow
                $warnings++
            }
            else {
                Write-Host "[INFO] $($script.Name)$msg" -ForegroundColor DarkGray
            }
        }
    }
}

Write-Host ""
$color = if ($errors -eq 0) { "Green" } else { "Red" }
Write-Host "=== Lint Result: $errors errors, $warnings warnings ===" -ForegroundColor $color
Write-Host ""

exit $errors
