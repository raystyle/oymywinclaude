#Requires -Version 5.1

<#
.SYNOPSIS
    Uninstall Rust toolchain (rustup + cargo) from D:\DevEnvs.
.DESCRIPTION
    Bypasses `rustup self uninstall` (which is extremely slow on Windows
    due to per-file deletion of tens of thousands of small files).
    Instead, removes RUSTUP_HOME and CARGO_HOME directories directly
    using `cmd /c rd /s /q` for maximum speed, then cleans up
    environment variables and PATH entries.
.PARAMETER RustupHome
    Rustup home directory. Default: D:\DevEnvs\.rustup
.PARAMETER CargoHome
    Cargo home directory. Default: D:\DevEnvs\.cargo
#>

[CmdletBinding()]
param(
    [string]$RustupHome = "D:\DevEnvs\.rustup",
    [string]$CargoHome  = "D:\DevEnvs\.cargo"
)

. "$PSScriptRoot\helpers.ps1"

$cargoBin = "$CargoHome\bin"

# ---- 1. Check if installed ----
$found = (Test-Path $RustupHome) -or (Test-Path $CargoHome)
if (-not $found) {
    Write-Host "[OK] Rust not found at $RustupHome / $CargoHome, nothing to do." -ForegroundColor Green
    exit 0
}

if (Test-Path "$cargoBin\rustc.exe") {
    $raw = & "$cargoBin\rustc.exe" --version 2>&1 | Out-String
    Write-Host "[INFO] Found: $($raw.Trim())" -ForegroundColor Cyan
}

# ---- 2. Remove PATH entries ----
Remove-UserPath -Dir $cargoBin

# ---- 3. Remove environment variables ----
$envVars = @("RUSTUP_HOME", "CARGO_HOME", "RUSTUP_DIST_SERVER", "RUSTUP_UPDATE_ROOT")
foreach ($var in $envVars) {
    $current = [Environment]::GetEnvironmentVariable($var, "User")
    if ($current) {
        [Environment]::SetEnvironmentVariable($var, $null, "User")
        Write-Host "[OK] Removed env var: $var" -ForegroundColor Green
    }
}

# ---- 4. Fast delete directories ----
# cmd /c rd /s /q is an order of magnitude faster than
# Remove-Item -Recurse on Windows for large directory trees.
foreach ($dir in @($RustupHome, $CargoHome)) {
    if (Test-Path $dir) {
        Write-Host "[INFO] Removing $dir ..." -ForegroundColor Cyan
        cmd /c "rd /s /q `"$dir`"" 2>$null
        if (Test-Path $dir) {
            Write-Host "[WARN] Some files may be locked. Manually delete: $dir" -ForegroundColor Yellow
            Write-Host "       Or run: cmd /c rd /s /q `"$dir`"" -ForegroundColor Cyan
        }
        else {
            Write-Host "[OK] Removed $dir" -ForegroundColor Green
        }
    }
}

# ---- Done ----
Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "  Rust toolchain uninstalled." -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
