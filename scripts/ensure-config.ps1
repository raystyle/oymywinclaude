#Requires -Version 5.1

<#
.SYNOPSIS
    Force overwrite a config file from template or default content, then open in editor.
    Supports -Merge for JSON deep merge with array deduplication.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,

    [string]$DefaultContent = "",

    [string]$TemplatePath = "",

    [switch]$Merge,

    [bool]$EditAfter = $true
)

$dir = Split-Path $Path -Parent
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

if ($TemplatePath -and (Test-Path $TemplatePath)) {
    if ($Merge -and (Test-Path $Path)) {
        try {
            $existingRaw = Get-Content $Path -Raw -Encoding UTF8
            $templateRaw = Get-Content $TemplatePath -Raw -Encoding UTF8
            $existing = $existingRaw | ConvertFrom-Json
            $template = $templateRaw | ConvertFrom-Json

            function Merge-Recursive($src, $tpl) {
                foreach ($prop in $tpl.PSObject.Properties) {
                    $name = $prop.Name
                    $tVal = $prop.Value
                    $sProp = $src.PSObject.Properties[$name]

                    if ($sProp) {
                        if ($tVal -is [PSCustomObject] -and $sProp.Value -is [PSCustomObject]) {
                            # Both are objects: recurse
                            Merge-Recursive $sProp.Value $tVal
                        }
                        elseif ($tVal -is [array] -and $sProp.Value -is [array]) {
                            # Both are arrays: dedup and merge
                            $merged = @($sProp.Value)
                            foreach ($tItem in $tVal) {
                                $found = $false
                                foreach ($mItem in $merged) {
                                    if (Test-SameEntry $mItem $tItem) {
                                        # Replace existing with template version
                                        $idx = [Array]::IndexOf($merged, $mItem)
                                        $merged[$idx] = $tItem
                                        $found = $true
                                        break
                                    }
                                }
                                if (-not $found) {
                                    $merged += $tItem
                                }
                            }
                            $src.$name = [array]$merged
                        }
                        else {
                            # Scalar or type mismatch: template overrides
                            $src.$name = $tVal
                        }
                    }
                    else {
                        # New key from template
                        $src | Add-Member -NotePropertyName $name -NotePropertyValue $tVal
                    }
                }
            }

            # Dedup key for arrays of objects: match by "matcher" or "command" field
            # For string arrays: exact match
            function Test-SameEntry($a, $b) {
                if ($a -is [string] -and $b -is [string]) {
                    return $a -eq $b
                }
                if ($a -is [PSCustomObject] -and $b -is [PSCustomObject]) {
                    # Try matcher field first (hooks), then command field
                    $aMatcher = $a.PSObject.Properties["matcher"]
                    $bMatcher = $b.PSObject.Properties["matcher"]
                    if ($aMatcher -and $bMatcher) {
                        return $a.Matcher -eq $b.Matcher
                    }
                    $aCmd = $a.PSObject.Properties["command"]
                    $bCmd = $b.PSObject.Properties["command"]
                    if ($aCmd -and $bCmd) {
                        return $a.Command -eq $b.Command
                    }
                }
                return $false
            }

            Merge-Recursive $existing $template

            # Move $schema to the top of the object for clean output
            $schemaProp = $existing.PSObject.Properties['$schema']
            if ($schemaProp) {
                $ordered = [ordered]@{'$schema' = $schemaProp.Value}
                foreach ($prop in $existing.PSObject.Properties) {
                    if ($prop.Name -ne '$schema') {
                        $ordered[$prop.Name] = $prop.Value
                    }
                }
                $existing = [PSCustomObject]$ordered
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $json = $existing | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
            Write-Host "[OK] Config merged from template: $Path" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] JSON merge failed, falling back to overwrite: $_" -ForegroundColor Yellow
            Copy-Item -Path $TemplatePath -Destination $Path -Force
            Write-Host "[OK] Config updated from template: $Path" -ForegroundColor Green
        }
    }
    else {
        Copy-Item -Path $TemplatePath -Destination $Path -Force -ErrorAction Stop
        Write-Host "[OK] Config updated from template: $Path" -ForegroundColor Green
    }
}
elseif ($DefaultContent) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $DefaultContent, $utf8NoBom)
    Write-Host "[OK] Config updated with default content: $Path" -ForegroundColor Green
}
else {
    New-Item -ItemType File -Path $Path -Force | Out-Null
    Write-Host "[OK] Config file reset: $Path" -ForegroundColor Green
}

if ($EditAfter) {
    if (Get-Command code -ErrorAction SilentlyContinue) {
        code $Path
    }
    else {
        notepad $Path
    }
}
