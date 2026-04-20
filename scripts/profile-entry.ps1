#Requires -Version 5.1

<#
.SYNOPSIS
    Add or remove a line in PowerShell profile (CurrentUserCurrentHost).
    Manages both PS5 and PS7 profiles with idempotent behavior.
.PARAMETER Action
    "add" or "remove"
.PARAMETER Line
    The exact line to add/remove
.PARAMETER Comment
    Comment placed above the line (used as marker for identification)
.PARAMETER BlockName
    When specified, wraps the line(s) in a marked block:
      # BEGIN ohmywinclaude: <BlockName>
      ...
      # END ohmywinclaude: <BlockName>
    Re-running "add" replaces the entire block. "remove" deletes it.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('add', 'remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Line,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Comment,

    [string]$BlockName
)

$myDocs = [Environment]::GetFolderPath('MyDocuments')

# CurrentUserCurrentHost profile for each PS version
$targets = @(
    @{
        Path  = "$myDocs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
        Label = "PS5 CurrentHost"
    }
    @{
        Path  = "$myDocs\PowerShell\Microsoft.PowerShell_profile.ps1"
        Label = "PS7 CurrentHost"
    }
)

$commentLine = "# $Comment"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Block markers
$useBlock = $false
$beginMarker = ''
$endMarker   = ''
if ($BlockName) {
    $useBlock    = $true
    $beginMarker = "# BEGIN ohmywinclaude: $BlockName"
    $endMarker   = "# END ohmywinclaude: $BlockName"
}

function Remove-Block([string[]]$lines, [string]$begin, [string]$end) {
    $result = @()
    $inBlock = $false
    foreach ($l in $lines) {
        if (-not $inBlock -and $l.Trim() -eq $begin) {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($l.Trim() -eq $end) {
                $inBlock = $false
            }
            continue
        }
        $result += $l
    }
    return ,@($result)
}

function Remove-TrailingBlanks([string[]]$lines) {
    $endIndex = $lines.Count - 1
    while ($endIndex -ge 0 -and $lines[$endIndex].Trim() -eq '') {
        $endIndex--
    }
    if ($endIndex -lt 0) { return ,@() }
    if ($endIndex -lt $lines.Count - 1) { return ,@($lines[0..$endIndex]) }
    return $lines
}

foreach ($t in $targets) {
    $profilePath = $t.Path
    $label = $t.Label

    # Ensure parent directory exists
    $parentDir = Split-Path $profilePath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Read existing content (or empty array if file doesn't exist)
    if (Test-Path $profilePath) {
        $lines = @(Get-Content -Path $profilePath -Encoding UTF8)
    }
    else {
        $lines = @()
    }

    if ($useBlock) {
        # ---- Block mode ----
        if ($Action -eq 'add') {
            # Remove existing block, then append new
            $filtered = Remove-Block $lines $beginMarker $endMarker
            $newLines = @($filtered)
            if ($newLines.Count -gt 0 -and $newLines[-1].Trim() -ne '') {
                $newLines += ''
            }
            $newLines += $beginMarker
            $newLines += $commentLine
            $newLines += $Line
            $newLines += $endMarker

            [System.IO.File]::WriteAllLines($profilePath, $newLines, $utf8NoBom)
            Write-Host "[OK] $label : block [$BlockName] updated" -ForegroundColor Green
        }
        elseif ($Action -eq 'remove') {
            $filtered = Remove-Block $lines $beginMarker $endMarker
            $filtered = Remove-TrailingBlanks $filtered

            if ($filtered.Count -ne $lines.Count) {
                [System.IO.File]::WriteAllLines($profilePath, [string[]]$filtered, $utf8NoBom)
                Write-Host "[OK] $label : block [$BlockName] removed" -ForegroundColor Green
            }
            else {
                Write-Host "[OK] $label : block [$BlockName] not found, nothing to remove" -ForegroundColor Gray
            }
        }
    }
    else {
        # ---- Legacy single-line mode ----
        if ($Action -eq 'add') {
            # Idempotent: skip if line already present
            $found = $false
            foreach ($l in $lines) {
                if ($l.Trim() -eq $Line.Trim()) {
                    $found = $true
                    break
                }
            }
            if ($found) {
                Write-Host "[OK] Already present: $label" -ForegroundColor DarkGray
                continue
            }

            # Append comment + line
            $newLines = @($lines)
            # Add blank line separator if file is not empty and doesn't end with blank line
            if ($newLines.Count -gt 0 -and $newLines[-1].Trim() -ne '') {
                $newLines += ''
            }
            $newLines += $commentLine
            $newLines += $Line

            [System.IO.File]::WriteAllLines($profilePath, $newLines, $utf8NoBom)
            Write-Host "[OK] $label : added" -ForegroundColor Green
        }
        elseif ($Action -eq 'remove') {
            if (-not (Test-Path $profilePath)) {
                Write-Host "[OK] $label : profile not found, nothing to remove" -ForegroundColor Gray
                continue
            }

            # Remove the comment line and the target line
            $filtered = @()
            $skipNext = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($skipNext) {
                    $skipNext = $false
                    continue
                }
                # Match comment line, then check if next line is the target
                if ($lines[$i].Trim() -eq $commentLine.Trim()) {
                    if (($i + 1) -lt $lines.Count -and $lines[$i + 1].Trim() -eq $Line.Trim()) {
                        $skipNext = $true
                        continue
                    }
                }
                # Also remove standalone target line (without comment)
                if ($lines[$i].Trim() -eq $Line.Trim()) {
                    continue
                }
                $filtered += $lines[$i]
            }

            # Remove trailing blank lines (PS5-safe)
            $filtered = Remove-TrailingBlanks $filtered

            if ($filtered.Count -ne $lines.Count) {
                [System.IO.File]::WriteAllLines($profilePath, [string[]]$filtered, $utf8NoBom)
                Write-Host "[OK] $label : removed" -ForegroundColor Green
            }
            else {
                Write-Host "[OK] $label : not found, nothing to remove" -ForegroundColor Gray
            }
        }
    }
}
