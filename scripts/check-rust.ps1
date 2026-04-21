#Requires -Version 5.1

<#
.SYNOPSIS
    Check Rust toolchain installation status.
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

$cargoBin = "$CargoHome\bin"
$rustc    = "$cargoBin\rustc.exe"
$cargo    = "$cargoBin\cargo.exe"
$rustup   = "$cargoBin\rustup.exe"

Write-Host "--- Rust ---" -ForegroundColor Cyan

# ---- Env vars (get and set first, but output later) ----
$actualRustupHome = [Environment]::GetEnvironmentVariable("RUSTUP_HOME", "User")
$actualCargoHome  = [Environment]::GetEnvironmentVariable("CARGO_HOME", "User")

# Ensure env vars for current session
$env:RUSTUP_HOME = $RustupHome
$env:CARGO_HOME  = $CargoHome

# ---- rustup ----
if (Test-Path $rustup) {
    $raw = & $rustup --version 2>&1 | Out-String
    # Only take the first line (version info), ignore additional info lines
    $version = ($raw -split "`n")[0].Trim()
    Write-Host "[OK] $version" -ForegroundColor Green

    $toolchains = & $rustup toolchain list 2>&1 | Out-String
    Write-Host "  Toolchains:      " -ForegroundColor DarkGray
    $toolchains.Trim().Split("`n") | ForEach-Object {
        Write-Host "    $_" -ForegroundColor DarkGray
    }

    # ---- rust-analyzer component ----
    $raCheck = & $rustup component list --installed 2>&1 | Out-String
    if ($raCheck -match 'rust-analyzer') {
        Write-Host "  rust-analyzer:   installed" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  rust-analyzer:   not installed (run: rustup component add rust-analyzer)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "[NOT INSTALLED] rustup" -ForegroundColor Red
    Write-Host "  Run 'just install-rust' to install" -ForegroundColor DarkGray
    return
}

# Now output env vars after version
if ($actualRustupHome) {
    Write-Host "  RUSTUP_HOME:     $actualRustupHome" -ForegroundColor DarkGray
}
else {
    Write-Host "  RUSTUP_HOME:     not set" -ForegroundColor DarkGray
}

if ($actualCargoHome) {
    Write-Host "  CARGO_HOME:      $actualCargoHome" -ForegroundColor DarkGray
}
else {
    Write-Host "  CARGO_HOME:      not set" -ForegroundColor DarkGray
}

# ---- rustc ----
if (Test-Path $rustc) {
    $raw = & $rustc --version 2>&1 | Out-String
    # Only take the first line (version info), ignore additional info lines
    $version = ($raw -split "`n")[0].Trim()
    Write-Host "  rustc:           $version" -ForegroundColor DarkGray
}
else {
    Write-Host "  rustc:           not found" -ForegroundColor DarkGray
}

# ---- cargo ----
if (Test-Path $cargo) {
    $raw = & $cargo --version 2>&1 | Out-String
    # Only take the first line (version info), ignore additional info lines
    $version = ($raw -split "`n")[0].Trim()
    Write-Host "  cargo:           $version" -ForegroundColor DarkGray
}
else {
    Write-Host "  cargo:           not found" -ForegroundColor DarkGray
}

# ---- Mirror config ----
$distServer = [Environment]::GetEnvironmentVariable("RUSTUP_DIST_SERVER", "User")
if ($distServer) {
    Write-Host "  RUSTUP_DIST_SERVER: $distServer" -ForegroundColor DarkGray
}
else {
    Write-Host "  RUSTUP_DIST_SERVER: not set" -ForegroundColor DarkGray
}

$configPath = "$CargoHome\config.toml"
if (Test-Path $configPath) {
    $content = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
    if ($content -match 'rsproxy\.cn') {
        Write-Host "  cargo registry:  rsproxy.cn" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  cargo registry: not configured" -ForegroundColor DarkGray
    }
}
else {
    Write-Host "  cargo registry: no config.toml" -ForegroundColor DarkGray
}
