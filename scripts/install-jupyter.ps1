#Requires -Version 5.1

<#
.SYNOPSIS
    Install jupyter-core and dependencies via uv tool
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Version', Justification = 'Reserved for future pinning')]
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$Version = ""
)

. "$PSScriptRoot\helpers.ps1"

# Refresh environment to pick up Python/uv from previous install steps
Refresh-Environment

$ErrorActionPreference = "Stop"

# Package versions
$jupyterlabVersion = "4.4.1"
$jupyterCollabVersion = "4.0.2"
$pycrdtVersion = "0.12.17"

# ---- 1. Check uv ----
if (-not (Get-Command "uv.exe" -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] uv not found" -ForegroundColor Red
    exit 1
}

# ---- 2. Define packages ----
$packages = @(
    "jupyter-core",
    "jupyterlab==$jupyterlabVersion",
    "jupyter-collaboration==$jupyterCollabVersion",
    "ipykernel",
    "datalayer_pycrdt==$pycrdtVersion"
)

# ---- 3. Build uv tool install command ----
$uvArgs = @("tool", "install", "--force", "jupyter-core")
foreach ($pkg in $packages[1..($packages.Length - 1)]) {
    $uvArgs += "--with", $pkg
}

# ---- 4. Check if already installed ----
$alreadyInstalled = $false
$uvList = & uv tool list 2>&1
if ($uvList -match "jupyter-core") {
    Show-AlreadyInstalled -Tool "jupyter-core"
    $alreadyInstalled = $true
}

if ($alreadyInstalled) {
    exit 0
}

# ---- 5. Ensure Rust default toolchain (needed by datalayer-pycrdt) ----
$cargoHome = $env:CARGO_HOME
if (-not $cargoHome) {
    $cargoHome = [Environment]::GetEnvironmentVariable("CARGO_HOME", "User")
}
if (-not $cargoHome) {
    $cargoHome = "$env:USERPROFILE\.cargo"
}
$rustup = Join-Path $cargoHome "bin\rustup.exe"

if (Test-Path $rustup) {
    $env:RUSTUP_HOME = if ($env:RUSTUP_HOME) { $env:RUSTUP_HOME } else { [Environment]::GetEnvironmentVariable("RUSTUP_HOME", "User") }
    $env:CARGO_HOME  = $cargoHome
    $rustupOutput = & $rustup show 2>&1 | Out-String
    if ($rustupOutput -match 'no.*toolchain' -or $rustupOutput -match 'no default') {
        Write-Host "[INFO] Setting Rust default toolchain to stable (required by datalayer-pycrdt)..." -ForegroundColor Cyan
        & $rustup default stable 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Rust default toolchain set to stable" -ForegroundColor Green
        }
        else {
            Write-Host "[WARN] Failed to set Rust default toolchain" -ForegroundColor Yellow
        }
    }
}

# ---- 6. Install via uv ----
Show-Installing -Component "jupyter-core"

$env:UV_NO_PROMPT = "1"
& uv @uvArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Installation failed" -ForegroundColor Red
    exit 1
}

# ---- 7. Verify installation ----
$uvList = & uv tool list 2>&1
if ($uvList -match "jupyter-core") {
    Show-InstallComplete -Tool "jupyter-core"
}
else {
    Write-Host "[WARN] jupyter-core not showing in uv tool list" -ForegroundColor Yellow
}
