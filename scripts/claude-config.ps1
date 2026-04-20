#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiKey,
    [string]$BaseUrl = "https://open.bigmodel.cn/api/anthropic",
    [int]$EnableLsp   = 1,
    [int]$EnableTeams = 1,
    [int]$EnableTmux  = 1,
    [string]$TemplatePath = "",
    [switch]$UseTemplate = $false
)

# --- 1. Detect Git Bash ---
$gitBashPath = $null
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $candidate = Join-Path (Split-Path (Split-Path $gitCmd.Source)) "bin\bash.exe"
    if (Test-Path $candidate) { $gitBashPath = $candidate }
}
if (-not $gitBashPath) {
    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\bin\bash.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Git\bin\bash.exe"),
        "D:\DevEnvs\Git\bin\bash.exe",
        "D:\Git\bin\bash.exe",
        "C:\Git\bin\bash.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { $gitBashPath = $p; break }
    }
}
if ($gitBashPath) {
    Write-Host "[OK] Git Bash detected: $gitBashPath" -ForegroundColor Green
} else {
    Write-Host "[WARN] Git Bash not found, skipping CLAUDE_CODE_GIT_BASH_PATH" -ForegroundColor Yellow
}

# --- 2. Load template or create base settings ---
if ($UseTemplate -and $TemplatePath -and (Test-Path $TemplatePath)) {
    Write-Host "[INFO] Loading base configuration from template: $TemplatePath" -ForegroundColor Cyan
    try {
        $templateContent = Get-Content -Path $TemplatePath -Raw -Encoding UTF8
        $settings = $templateContent | ConvertFrom-Json
        Write-Host "[OK] Template loaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Failed to load template, creating fresh configuration: $_" -ForegroundColor Yellow
        $settings = [ordered]@{}
    }
}
else {
    $settings = [ordered]@{}
}

# --- 3. Build env hash ---
# Preserve existing env settings from template if they exist
if (-not $settings.env) {
    $settings.env = [ordered]@{}
}

# Set/update required environment variables
$settings.env.ANTHROPIC_AUTH_TOKEN = $ApiKey
$settings.env.ANTHROPIC_BASE_URL = $BaseUrl
$settings.env.API_TIMEOUT_MS = "3000000"
$settings.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = 1

if ($EnableLsp -eq 1) {
    $settings.env.ENABLE_LSP_TOOL = 1
}
if ($EnableTeams -eq 1) {
    $settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = 1
}
if ($gitBashPath) {
    $settings.env.CLAUDE_CODE_GIT_BASH_PATH = $gitBashPath
}

# --- 4. Update settings object ---
if ($EnableTmux -eq 1) {
    $settings.teammateMode = "tmux"
}

# --- 5. Write ~/.claude/settings.json ---
$settingsDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null }
$settingsFile = Join-Path $settingsDir "settings.json"
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsFile -Encoding UTF8
Write-Host "[OK] settings.json written: $settingsFile" -ForegroundColor Green

# --- 7. Write ~/.claude.json (skip onboarding) ---
$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
@{ hasCompletedOnboarding = $true } | ConvertTo-Json | Set-Content -Path $claudeJson -Encoding UTF8
Write-Host "[OK] .claude.json written: $claudeJson" -ForegroundColor Green

# --- 8. Summary ---
Write-Host ""
Write-Host "[OK] Claude Code environment configured!" -ForegroundColor Cyan
Write-Host "   ANTHROPIC_AUTH_TOKEN = $ApiKey"
Write-Host "   ANTHROPIC_BASE_URL   = $BaseUrl"
Write-Host "   ENABLE_LSP_TOOL      = $(if ($EnableLsp -eq 1) { '1' } else { 'off' })"
Write-Host "   Agent Teams          = $(if ($EnableTeams -eq 1) { 'enabled' } else { 'off' })"
Write-Host "   teammateMode         = $(if ($EnableTmux -eq 1) { 'tmux' } else { 'off' })"
if ($gitBashPath) { Write-Host "   GIT_BASH_PATH        = $gitBashPath" }
