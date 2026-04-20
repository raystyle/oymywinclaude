#Requires -Version 5.1

[CmdletBinding()]
param()

. "$PSScriptRoot\helpers.ps1"
Refresh-Environment

Write-Host "--- Claude Code ---" -ForegroundColor Cyan

# --- 1. Binary ---
function Get-ClaudePath {
    # Method 1: where.exe (Windows native)
    $wherePath = where.exe claude 2>$null | Select-Object -First 1
    if ($wherePath) { return $wherePath }

    # Method 2: Common install locations
    $candidates = @(
        "$env:USERPROFILE\.claude\local\claude.exe"
        "$env:LOCALAPPDATA\Programs\claude\claude.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    return $null
}

$claudePath = Get-ClaudePath
if ($claudePath) {
    $version = & claude --version 2>&1
    Write-Host "[OK] $version" -ForegroundColor Green
    Write-Host "  Location: $claudePath" -ForegroundColor DarkGray
} else {
    Write-Host "[NOT INSTALLED]" -ForegroundColor Red
    Write-Host "  Run 'just install-claude' to install" -ForegroundColor DarkGray
}

# --- 2. Windows User Environment Variables ---
$tokenValue = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
$urlValue = [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

Write-Host "  Windows User Environment Variables:" -ForegroundColor DarkGray

if ($tokenValue) {
    $maskedToken = if ($tokenValue.Length -gt 8) {
        $tokenValue.Substring(0, 8) + "..." + $tokenValue.Substring($tokenValue.Length - 4)
    } else {
        "***"
    }
    Write-Host "    ANTHROPIC_AUTH_TOKEN: $maskedToken" -ForegroundColor DarkGray
} else {
    Write-Host "    ANTHROPIC_AUTH_TOKEN: not set" -ForegroundColor DarkGray
    Write-Host "    Run 'just setup-claude <key>' to configure" -ForegroundColor DarkGray
}

if ($urlValue) {
    Write-Host "    ANTHROPIC_BASE_URL: $urlValue" -ForegroundColor DarkGray
} else {
    Write-Host "    ANTHROPIC_BASE_URL: not set" -ForegroundColor DarkGray
}

# --- 4. settings.json ---
$settingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settingsFile) {
    Write-Host "  settings.json: OK ($settingsFile)" -ForegroundColor DarkGray
    try {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json

        # ENABLE_LSP_TOOL
        if ($settings.env.ENABLE_LSP_TOOL -eq 1) {
            Write-Host "    ENABLE_LSP_TOOL: 1" -ForegroundColor DarkGray
        } else {
            Write-Host "    ENABLE_LSP_TOOL: not set" -ForegroundColor DarkGray
        }

        # Agent Teams
        if ($settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS -eq 1) {
            Write-Host "    Agent Teams: enabled" -ForegroundColor DarkGray
        } else {
            Write-Host "    Agent Teams: disabled" -ForegroundColor DarkGray
        }

        # PowerShell tool
        if ($settings.env.CLAUDE_CODE_USE_POWERSHELL_TOOL -eq 1) {
            Write-Host "    PowerShell tool: enabled" -ForegroundColor DarkGray
        } else {
            Write-Host "    PowerShell tool: not set" -ForegroundColor DarkGray
        }

        # teammateMode
        if ($settings.teammateMode) {
            Write-Host "    teammateMode: $($settings.teammateMode)" -ForegroundColor DarkGray
        }

        # Git Bash
        if ($settings.env.CLAUDE_CODE_GIT_BASH_PATH) {
            $gbPath = $settings.env.CLAUDE_CODE_GIT_BASH_PATH
            if (Test-Path $gbPath) {
                Write-Host "    Git Bash: $gbPath" -ForegroundColor DarkGray
            } else {
                Write-Host "    Git Bash: $gbPath (path not found)" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "  settings.json: parse error" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  settings.json: not found" -ForegroundColor DarkGray
}

# --- 5. .claude.json (onboarding) ---
$claudeJson = Join-Path $env:USERPROFILE ".claude.json"
if (Test-Path $claudeJson) {
    try {
        $cj = Get-Content $claudeJson -Raw | ConvertFrom-Json
        if ($cj.hasCompletedOnboarding -eq $true) {
            Write-Host "  Onboarding: skipped" -ForegroundColor DarkGray
        } else {
            Write-Host "  Onboarding: not completed" -ForegroundColor DarkGray
        }
    }
    catch {
        # Malformed .claude.json — treat as not completed
        $cj = @{
            hasCompletedOnboarding = $false
        }
    }
} else {
    Write-Host "  .claude.json: not found" -ForegroundColor DarkGray
}

# --- 6. LSP Support (Language Servers + Plugins) ---
Write-Host ""
Write-Host "  LSP Support:" -ForegroundColor DarkGray

$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\DevEnvs\Git\bin\bash.exe"
$pluginOutput = if ($claudePath) {
    try {
        & claude plugin list 2>&1 | Out-String
    }
    catch {
        ""
    }
} else {
    ""
}

# Python LSP (ty via Astral plugin)
$uvxCmd = Get-Command uvx -ErrorAction SilentlyContinue
if ($uvxCmd) {
    $pluginStatus = if ($pluginOutput -match "astral@local-dev") {
        if ($pluginOutput -match "astral@local-dev[\s\S]*?Status.*?enabled") {
            "enabled"
        } else {
            "disabled"
        }
    } else {
        "plugin not installed"
    }
    $statusColor = if ($pluginStatus -eq "enabled") { "Green" } elseif ($pluginStatus -eq "disabled") { "Yellow" } else { "DarkGray" }
    Write-Host "    Python LSP (ty): $($uvxCmd.Source)" -ForegroundColor DarkGray
    Write-Host "      Plugin: $pluginStatus" -ForegroundColor $statusColor
} else {
    Write-Host "    Python LSP (ty): uvx not installed" -ForegroundColor Yellow
    Write-Host "      Run 'just install-claude-plugin-astral' to install Astral plugin" -ForegroundColor DarkGray
}

# TypeScript LSP
$tscCmd = Get-Command typescript-language-server -ErrorAction SilentlyContinue
if ($tscCmd) {
    $pluginStatus = if ($pluginOutput -match "typescript-lsp@claude-plugins-official") {
        if ($pluginOutput -match "typescript-lsp@claude-plugins-official[\s\S]*?Status.*?enabled") {
            "enabled"
        } else {
            "disabled"
        }
    } else {
        "plugin not installed"
    }
    $statusColor = if ($pluginStatus -eq "enabled") { "Green" } elseif ($pluginStatus -eq "disabled") { "Yellow" } else { "DarkGray" }
    Write-Host "    TypeScript: $($tscCmd.Source)" -ForegroundColor DarkGray
    Write-Host "      Plugin: $pluginStatus" -ForegroundColor $statusColor
} else {
    Write-Host "    TypeScript: not installed" -ForegroundColor Yellow
    Write-Host "      Run 'just install-typescript-lsp' to install TypeScript LSP" -ForegroundColor DarkGray
    Write-Host "      Run 'just install-claude-plugin-typescript' to register plugin" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "For detailed status, run:" -ForegroundColor DarkGray
Write-Host "  just status-jupyter               # Check Jupyter MCP server" -ForegroundColor DarkGray
Write-Host "  just status-claude-plugin-astral  # Check Astral (uv, ruff, ty)" -ForegroundColor DarkGray
Write-Host "  just status-claude-plugin-typescript # Check TypeScript LSP" -ForegroundColor DarkGray
