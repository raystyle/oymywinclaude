#Requires -Version 5.1

<#
.SYNOPSIS
    Install Rust toolchain via rustup with China mirror support.
.DESCRIPTION
    Downloads rustup-init.exe, configures rsproxy.cn mirrors,
    installs specified toolchain silently to D:\DevEnvs.
.PARAMETER Version
    Rust toolchain version to install. Default: stable
.PARAMETER RustupHome
    Rustup home directory. Default: D:\DevEnvs\.rustup
.PARAMETER CargoHome
    Cargo home directory. Default: D:\DevEnvs\.cargo
.PARAMETER Mirror
    Mirror base URL for rustup. Default: https://rsproxy.cn
#>

[CmdletBinding()]
param(
    [string]$Version    = "stable",
    [string]$RustupHome = "D:\DevEnvs\.rustup",
    [string]$CargoHome  = "D:\DevEnvs\.cargo",
    [string]$Mirror     = "https://rsproxy.cn"
)

. "$PSScriptRoot\helpers.ps1"

$cargoBin = "$CargoHome\bin"
$rustup   = "$cargoBin\rustup.exe"
$rustc    = "$cargoBin\rustc.exe"

# ---- 1. Idempotent check ----
if ((Test-Path $rustup) -and (Test-Path $rustc)) {
    $env:RUSTUP_HOME = $RustupHome
    $env:CARGO_HOME  = $CargoHome
    $raw = & $rustc --version 2>&1 | Out-String
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $installed = $Matches[1]
        Write-Host "[OK] Rust $installed already installed." -ForegroundColor Green
        Write-Host "[INFO] RUSTUP_HOME: $RustupHome" -ForegroundColor Cyan
        Write-Host "[INFO] CARGO_HOME:  $CargoHome" -ForegroundColor Cyan

        # Ensure default toolchain is set (may be missing after manual/rustup-init install)
        $showOutput = & $rustup show 2>&1 | Out-String
        if ($showOutput -match 'no.*toolchain' -or $showOutput -match 'no default') {
            Write-Host "[INFO] Setting default toolchain to stable..." -ForegroundColor Cyan
            & $rustup default stable 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Default toolchain set to stable" -ForegroundColor Green
            }
            else {
                Write-Host "[WARN] Failed to set default toolchain, run manually: rustup default stable" -ForegroundColor Yellow
            }
        }

        Write-Host "[INFO] Run 'rustup update' to update." -ForegroundColor Cyan
        exit 0
    }
}

# ---- 2. Configure environment variables (permanent + session) ----
Write-Host "[INFO] Configuring environment variables..." -ForegroundColor Cyan

# Install location
$env:RUSTUP_HOME = $RustupHome
$env:CARGO_HOME  = $CargoHome
[Environment]::SetEnvironmentVariable("RUSTUP_HOME", $RustupHome, "User")
[Environment]::SetEnvironmentVariable("CARGO_HOME",  $CargoHome,  "User")
Write-Host "[OK] RUSTUP_HOME = $RustupHome" -ForegroundColor Green
Write-Host "[OK] CARGO_HOME  = $CargoHome" -ForegroundColor Green

# Mirror
$env:RUSTUP_DIST_SERVER = $Mirror
$env:RUSTUP_UPDATE_ROOT = "$Mirror/rustup"
[Environment]::SetEnvironmentVariable("RUSTUP_DIST_SERVER", $Mirror, "User")
[Environment]::SetEnvironmentVariable("RUSTUP_UPDATE_ROOT", "$Mirror/rustup", "User")
Write-Host "[OK] RUSTUP_DIST_SERVER = $Mirror" -ForegroundColor Green
Write-Host "[OK] RUSTUP_UPDATE_ROOT = $Mirror/rustup" -ForegroundColor Green

# ---- 3. Ensure directories exist ----
foreach ($dir in @($RustupHome, $CargoHome)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "[OK] Created: $dir" -ForegroundColor Green
    }
}

# ---- 4. Configure cargo registry ----
$configPath = "$CargoHome\config.toml"

$needWrite = $true
if (Test-Path $configPath) {
    $existing = Get-Content -Path $configPath -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'rsproxy\.cn') {
        Write-Host "[OK] cargo config.toml already configured with rsproxy.cn" -ForegroundColor Green
        $needWrite = $false
    }
    else {
        $backupPath = "$configPath.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -Path $configPath -Destination $backupPath -Force
        Write-Host "[WARN] Existing config.toml backed up to: $backupPath" -ForegroundColor Yellow
    }
}

if ($needWrite) {
    $configContent = @'
[source.crates-io]
replace-with = "rsproxy"

[source.rsproxy]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true

[http]
check-revoke = false
multiplexing = true
'@
    Set-Content -Path $configPath -Value $configContent -Encoding UTF8 -NoNewline
    Write-Host "[OK] cargo config.toml written with rsproxy.cn" -ForegroundColor Green
}

# ---- 5. Download rustup-init.exe ----
$rustupInitUrl = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
$rustupInit    = "$env:TEMP\rustup-init.exe"

Write-Host "[INFO] Downloading rustup-init.exe ..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $rustupInitUrl -OutFile $rustupInit -CacheDir "rustup"
}
catch {
    Write-Host "[WARN] Direct download failed, trying mirror..." -ForegroundColor Yellow
    try {
        $mirrorUrl = "$Mirror/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
        Invoke-WebRequest -Uri $mirrorUrl -OutFile $rustupInit -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
        Write-Host "[OK] Downloaded (mirror)" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to download rustup-init.exe: $_" -ForegroundColor Red
        exit 1
    }
}

# ---- 6. Run rustup-init (silent) ----
Write-Host "[INFO] Installing Rust $Version toolchain..." -ForegroundColor Cyan
Write-Host "       This may take a few minutes." -ForegroundColor DarkGray

try {
    # -y: accept defaults, no prompts
    # --default-toolchain <version>: install specified version
    # --default-host x86_64-pc-windows-msvc: MSVC target
    # --no-modify-path: we manage PATH ourselves
    $proc = Start-Process -FilePath $rustupInit `
        -ArgumentList '-y', '--default-toolchain', $Version, '--default-host', 'x86_64-pc-windows-msvc', '--no-modify-path' `
        -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        throw "rustup-init.exe exited with code $($proc.ExitCode)"
    }
    Write-Host "[OK] rustup-init completed" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Rust installation failed: $_" -ForegroundColor Red
    Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 7. PATH ----
Add-UserPath -Dir $cargoBin

# ---- 8. Cleanup ----
Remove-Item $rustupInit -Force -ErrorAction SilentlyContinue

# ---- 9. Set default toolchain explicitly ----
Write-Host "[INFO] Setting default toolchain..." -ForegroundColor Cyan

# Refresh PATH for current session
if ($env:Path -notlike "*$cargoBin*") {
    $env:Path = "$cargoBin;$env:Path"
}

& "$cargoBin\rustup.exe" default stable 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Default toolchain set to stable" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Failed to set default toolchain, run manually: rustup default stable" -ForegroundColor Yellow
}

# ---- 10. Install rust-analyzer component ----
Write-Host "[INFO] Installing rust-analyzer component..." -ForegroundColor Cyan
& "$cargoBin\rustup.exe" component add rust-analyzer 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] rust-analyzer component installed" -ForegroundColor Green
}
else {
    Write-Host "[WARN] Failed to install rust-analyzer, run manually: rustup component add rust-analyzer" -ForegroundColor Yellow
}

# ---- 11. Verify ----
Write-Host "[INFO] Verifying..." -ForegroundColor Cyan

$result = & "$cargoBin\rustc.exe" --version 2>&1 | Out-String
if ($result -match '(\d+\.\d+\.\d+)') {
    Write-Host "[OK] Installed: $($result.Trim())" -ForegroundColor Green
}
else {
    Write-Host "[WARN] rustc not responding, restart terminal and run: rustc --version" -ForegroundColor Yellow
}

$result2 = & "$cargoBin\cargo.exe" --version 2>&1 | Out-String
if ($result2 -match '(\d+\.\d+\.\d+)') {
    Write-Host "[OK] $($result2.Trim())" -ForegroundColor Green
}

$result3 = & "$cargoBin\rustup.exe" --version 2>&1 | Out-String
if ($result3 -match '(\d+\.\d+\.\d+)') {
    Write-Host "[OK] $($result3.Trim())" -ForegroundColor Green
}

Write-Host ""
Write-Host "[OK] Rust installation complete!" -ForegroundColor Green
Write-Host "     Toolchain:   stable-x86_64-pc-windows-msvc" -ForegroundColor DarkGray
Write-Host "     RUSTUP_HOME: $RustupHome" -ForegroundColor DarkGray
Write-Host "     CARGO_HOME:  $CargoHome" -ForegroundColor DarkGray
Write-Host "     cargo bin:   $cargoBin" -ForegroundColor DarkGray
Write-Host "     Mirror:      $Mirror" -ForegroundColor DarkGray
