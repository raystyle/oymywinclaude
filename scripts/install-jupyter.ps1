#Requires -Version 5.1

<#
.SYNOPSIS
    Install jupyter-mcp and dependencies via uv tool
#>

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
$jupyterMcpToolsVersion = "0.1.4"
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
    "jupyter-mcp-tools>=$jupyterMcpToolsVersion",
    "jupyter-mcp-server",
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

# ---- 5. Install via uv ----
Show-Installing -Component "jupyter-mcp"

$env:UV_NO_PROMPT = "1"
& uv @uvArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Installation failed" -ForegroundColor Red
    exit 1
}

# ---- 6. Verify installation ----
$uvList = & uv tool list 2>&1
if ($uvList -match "jupyter-core") {
    Show-InstallComplete -Tool "jupyter-core"
}
else {
    Write-Host "[WARN] jupyter-core not showing in uv tool list" -ForegroundColor Yellow
}
