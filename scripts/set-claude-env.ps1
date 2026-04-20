#Requires -Version 5.1

<#
.SYNOPSIS
    Set or update Claude Code Windows user environment variables (API credentials)
.DESCRIPTION
    Sets ANTHROPIC_AUTH_TOKEN and ANTHROPIC_BASE_URL as Windows user environment variables
    Supports checking current values and overwriting existing configuration
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$RemainingArguments = @(),

    [string]$ApiKey = "",

    [string]$BaseUrl = "",

    [switch]$Check = $false,

    [switch]$Interactive = $false
)

. "$PSScriptRoot\helpers.ps1"

# --- Handle positional arguments ---
if ($RemainingArguments.Count -gt 0 -and [string]::IsNullOrEmpty($ApiKey)) {
    $ApiKey = $RemainingArguments[0]
}
if ($RemainingArguments.Count -gt 1 -and [string]::IsNullOrEmpty($BaseUrl)) {
    $BaseUrl = $RemainingArguments[1]
}

# --- Check mode: don't require API key ---
if ($Check) {
    Write-Host "[INFO] Checking Claude Code environment variables..." -ForegroundColor Cyan
    Write-Host ""

    $tokenValue = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
    $urlValue = [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

    Write-Host "Current Windows User Environment Variables:" -ForegroundColor White
    Write-Host ""

    if ($tokenValue) {
        $maskedToken = if ($tokenValue.Length -gt 8) {
            $tokenValue.Substring(0, 8) + "..." + $tokenValue.Substring($tokenValue.Length - 4)
        } else {
            "***"
        }
        Write-Host "  ANTHROPIC_AUTH_TOKEN = $maskedToken" -ForegroundColor Green
    } else {
        Write-Host "  ANTHROPIC_AUTH_TOKEN = (not set)" -ForegroundColor Red
        Write-Host "  Run 'just setup-claude <key>' to configure" -ForegroundColor Yellow
    }

    if ($urlValue) {
        Write-Host "  ANTHROPIC_BASE_URL   = $urlValue" -ForegroundColor Green
    } else {
        Write-Host "  ANTHROPIC_BASE_URL   = (not set, using default)" -ForegroundColor Yellow
        Write-Host "  Default: https://open.bigmodel.cn/api/anthropic" -ForegroundColor Cyan
    }

    Write-Host ""
    exit 0
}

# --- Interactive mode or positional parameter handling ---
if ($Interactive -and [string]::IsNullOrEmpty($ApiKey)) {
    # Check existing environment variables first
    $existingToken = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
    $existingUrl = [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

    Write-Host ""
    Write-Host "🤖 Claude Code Configuration" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host ""

    # If environment variables are already set, ask what to do
    if ($existingToken -or $existingUrl) {
        Write-Host "[INFO] Existing configuration found:" -ForegroundColor Cyan
        if ($existingToken) {
            $maskedToken = if ($existingToken.Length -gt 8) {
                $existingToken.Substring(0, 8) + "..." + $existingToken.Substring($existingToken.Length - 4)
            } else {
                "***"
            }
            Write-Host "  ANTHROPIC_AUTH_TOKEN = $maskedToken" -ForegroundColor Green
        }
        if ($existingUrl) {
            Write-Host "  ANTHROPIC_BASE_URL   = $existingUrl" -ForegroundColor Green
        }
        Write-Host ""

        $response = Read-Host "Configuration already exists. Keep existing (K) or Reset (R)?"
        if ($response -eq "K" -or $response -eq "k" -or $response -eq "") {
            Write-Host "[INFO] Keeping existing configuration" -ForegroundColor Green
            exit 0
        }
        Write-Host "[INFO] Resetting configuration..." -ForegroundColor Cyan
        Write-Host ""
    }

    # Prompt for API Key
    $ApiKey = Read-Host "Please enter your API Key (ANTHROPIC_AUTH_TOKEN)"
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        Write-Host "[ERROR] API Key cannot be empty" -ForegroundColor Red
        exit 1
    }

    # Prompt for API Base URL (with default)
    Write-Host ""
    Write-Host "API Base URL (press Enter for default: https://open.bigmodel.cn/api/anthropic):" -ForegroundColor Cyan
    $BaseUrlInput = Read-Host
    if ([string]::IsNullOrWhiteSpace($BaseUrlInput)) {
        $BaseUrl = "https://open.bigmodel.cn/api/anthropic"
        Write-Host "[INFO] Using default API endpoint: $BaseUrl" -ForegroundColor Green
    } else {
        $BaseUrl = $BaseUrlInput
    }

    Write-Host ""
}
elseif ([string]::IsNullOrEmpty($ApiKey)) {
    # Not interactive mode and no API key provided - show usage
    Write-Host "[ERROR] ApiKey is required" -ForegroundColor Red
    Write-Host "[INFO] Usage: just setup-claude <api-key> [api-url]" -ForegroundColor Cyan
    Write-Host "[INFO]    or: just setup-claude (for interactive input)" -ForegroundColor Cyan
    Write-Host "[INFO] Example: just setup-claude sk-1234567890abcdef" -ForegroundColor Cyan
    exit 1
}

# Set default BaseURL if not provided
if ([string]::IsNullOrEmpty($BaseUrl)) {
    $BaseUrl = "https://open.bigmodel.cn/api/anthropic"
}

# --- Set mode: update Windows user environment variables ---
Write-Host "[INFO] Configuring Claude Code Windows user environment variables..." -ForegroundColor Cyan

# Check current values
$currentToken = [Environment]::GetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", "User")
$currentUrl = [Environment]::GetEnvironmentVariable("ANTHROPIC_BASE_URL", "User")

if ($currentToken -or $currentUrl) {
    Write-Host "[INFO] Found existing environment variables:" -ForegroundColor Cyan
    if ($currentToken) {
        $maskedOld = if ($currentToken.Length -gt 8) { $currentToken.Substring(0, 8) + "..." } else { "***" }
        Write-Host "  ANTHROPIC_AUTH_TOKEN: $maskedOld" -ForegroundColor Yellow
    }
    if ($currentUrl) {
        Write-Host "  ANTHROPIC_BASE_URL: $currentUrl" -ForegroundColor Yellow
    }

    # Skip confirmation in interactive mode (user already chose Reset above)
    if (-not $Interactive) {
        Write-Host ""
        $response = Read-Host "Replace existing values? (Y/N)"
        if ($response -ne "Y" -and $response -ne "y") {
            Write-Host "[INFO] Keeping existing environment variables" -ForegroundColor Cyan
            exit 0
        }
    }
    Write-Host "[INFO] Updating environment variables..." -ForegroundColor Cyan
} else {
    Write-Host "[INFO] Setting new environment variables" -ForegroundColor Cyan
}

# Set current session environment variables (for immediate use)
$env:ANTHROPIC_AUTH_TOKEN = $ApiKey
$env:ANTHROPIC_BASE_URL = $BaseUrl

# Set Windows user environment variables (persistent across sessions)
[Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $ApiKey, "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $BaseUrl, "User")

# Display summary
Write-Host ""
Write-Host "[OK] Claude Code environment variables configured!" -ForegroundColor Green
Write-Host "   ANTHROPIC_AUTH_TOKEN = " -NoNewline
$maskedToken = if ($ApiKey.Length -gt 8) {
    $ApiKey.Substring(0, 8) + "..." + $ApiKey.Substring($ApiKey.Length - 4)
} else {
    $ApiKey
}
Write-Host $maskedToken -ForegroundColor Green
Write-Host "   ANTHROPIC_BASE_URL   = $BaseUrl" -ForegroundColor Green
Write-Host ""
Write-Host "[INFO] Environment variables set for:" -ForegroundColor Cyan
Write-Host "   - Current PowerShell session" -ForegroundColor Cyan
Write-Host "   - All new sessions (Windows User environment)" -ForegroundColor Cyan
Write-Host ""
Write-Host "[INFO] Restart your terminal or IDE to use the new environment variables" -ForegroundColor Yellow
