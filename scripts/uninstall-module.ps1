#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall a PowerShell module from user module directories (both PS5 and PS7).
.DESCRIPTION
    Three-tier strategy:
      1. Remove-Module from current session
      2. Spawn a clean child process (pwsh/powershell -NoProfile) to delete the directory
         — the child never loaded the DLL, so there is no lock.
      3. If child-process deletion also fails (e.g. another terminal holds the DLL),
         fall back to renaming the directory to .pending-delete so the module
         won't be auto-imported on next session.
.PARAMETER ModuleName
    Module name to uninstall
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ModuleName
)

. "$PSScriptRoot\helpers.ps1"

# ---- 0. Auto-cleanup any stale .pending-delete from previous runs ----
Remove-PendingDeleteDirs

# ---- 0. Resolve targets ----
$myDocs = [Environment]::GetFolderPath('MyDocuments')

$targets = @(
    @{ Path = "$myDocs\WindowsPowerShell\Modules\$ModuleName"; Label = "PS5" }
    @{ Path = "$myDocs\PowerShell\Modules\$ModuleName";        Label = "PS7" }
)

# Pick the right child shell: prefer pwsh (PS7), fall back to powershell (PS5)
$childShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

# ---- 1. Remove loaded module from current session ----
if (Get-Module -Name $ModuleName -ErrorAction SilentlyContinue) {
    try {
        Remove-Module -Name $ModuleName -Force -ErrorAction Stop
        Write-Host "[OK] Removed $ModuleName from current session" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not remove $ModuleName from session: $_" -ForegroundColor Yellow
    }
}

# ---- 2. Delete module directories via clean child process ----
$lockedPaths = @()
$errorCount  = 0

foreach ($t in $targets) {
    if (-not (Test-Path $t.Path)) {
        Write-Host "[OK] $($t.Label) : not installed, nothing to remove" -ForegroundColor Gray
        continue
    }

    # Try 1: direct delete in current process (works if module was never loaded)
    try {
        Remove-Item -Path $t.Path -Recurse -Force -ErrorAction Stop
        Write-Host "[OK] $($t.Label) : removed $($t.Path)" -ForegroundColor Green
        continue
    }
    catch {
        Write-Host "[INFO] $($t.Label) : in-process delete failed, spawning clean child process..." -ForegroundColor DarkGray
    }

    # Try 2: child process — it has never loaded the DLL, so no file lock
    $deleteScript = "Remove-Item -Path '$($t.Path -replace "'","''")' -Recurse -Force -ErrorAction Stop"
    $proc = Start-Process -FilePath $childShell -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-Command', $deleteScript
    ) -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0 -and -not (Test-Path $t.Path)) {
        Write-Host "[OK] $($t.Label) : removed $($t.Path) (via child process)" -ForegroundColor Green
        continue
    }

    Write-Host "[WARN] $($t.Label) : child process delete failed (exit=$($proc.ExitCode)), trying rename..." -ForegroundColor Yellow

    # Try 3: rename to .pending-delete — prevents Import-Module on next session
    $pendingPath = "$($t.Path).pending-delete"

    # Clean up any previous .pending-delete
    if (Test-Path $pendingPath) {
        Remove-Item -Path $pendingPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $pendingPath) {
            # Also try child process for the stale pending-delete
            Start-Process -FilePath $childShell -ArgumentList @(
                '-NoProfile', '-NonInteractive', '-Command',
                "Remove-Item -Path '$($pendingPath -replace "'","''")' -Recurse -Force -ErrorAction SilentlyContinue"
            ) -Wait -NoNewWindow
        }
    }

    try {
        Rename-Item -Path $t.Path -NewName "$ModuleName.pending-delete" -Force -ErrorAction Stop
        Write-Host "[OK] $($t.Label) : renamed to .pending-delete (will not load on next session)" -ForegroundColor Green
        Write-Host "     Clean up later:  Remove-Item '$pendingPath' -Recurse -Force" -ForegroundColor DarkGray
        continue
    }
    catch {
        Write-Host "[WARN] $($t.Label) : rename also failed — file is truly locked by another process" -ForegroundColor Yellow
        $lockedPaths += $t.Path
    }
}

# ---- 3. Verify ----
foreach ($t in $targets) {
    if (Test-Path $t.Path) {
        if ($lockedPaths -contains $t.Path) { continue }
        Write-Host "[ERROR] $($t.Label) still exists: $($t.Path)" -ForegroundColor Red
        $errorCount++
    }
}

# ---- 4. Summary ----
if ($lockedPaths.Count -gt 0) {
    Write-Host ""
    Write-Host "[WARN] The following paths are locked by another process:" -ForegroundColor Yellow
    foreach ($p in $lockedPaths) {
        Write-Host "       $p" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "       Close ALL PowerShell/terminal windows, then run:" -ForegroundColor Yellow
    foreach ($p in $lockedPaths) {
        Write-Host "       cmd /c rmdir /s /q ""$p""" -ForegroundColor Cyan
    }
    Write-Host ""
}

if ($errorCount -gt 0) {
    Write-Host "[FAIL] $errorCount non-recoverable error(s) during uninstall." -ForegroundColor Red
    exit 1
}

if ($lockedPaths.Count -gt 0) {
    Write-Host "[OK] $ModuleName uninstall completed with warnings (locked files deferred)." -ForegroundColor Yellow
}
else {
    Write-Host "[OK] $ModuleName fully uninstalled from PS5 and PS7." -ForegroundColor Green
}
exit 0
