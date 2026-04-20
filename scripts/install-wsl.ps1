#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$DistroName,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$OriginalWslFile,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetDir,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$LinuxUser,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$LinuxPass,

    [string]$InitScriptPath = "",

    [switch]$Force
)

# Error action preference
$ErrorActionPreference = "Stop"

# Helper functions for logging
function Write-OK { param([string]$msg); Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info { param([string]$msg); Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn { param([string]$msg); Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$msg); Write-Host "[ERROR] $msg" -ForegroundColor Red }

# 0. Idempotency check
$existingDistro = wsl.exe -l -q 2>$null | Where-Object { $_.Replace("`0","").Trim() -eq $DistroName }
$existingDir = Test-Path $TargetDir

if ($existingDistro -and -not $Force) {
    Write-OK "WSL distro '$DistroName' already exists, skipping installation"
    exit 0
}

if ($existingDistro -or $existingDir) {
    if ($Force) {
        Write-Warn "Detected old environment, cleaning up..."
    } else {
        Write-Warn "Detected old environment but -Force not enabled, exiting"
        exit 1
    }
}

# 1. Clean up old environment
if ($existingDistro) {
    Write-Info "Stopping WSL instance..."
    wsl --shutdown | Out-Null
    Start-Sleep -Seconds 2

    Write-Info "Unregistering old distro $DistroName..."
    wsl --unregister $DistroName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-OK "Unregistered old distro $DistroName"
    }
    Start-Sleep -Seconds 3
}

if ($existingDir) {
    Write-Info "Removing old directory $TargetDir..."
    Remove-Item -Path $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-OK "Removed old directory"
} else {
    Write-OK "No old environment detected, proceeding with installation"
}

# 2. File check
$FullWslPath = Resolve-Path $OriginalWslFile -ErrorAction SilentlyContinue
if (-not $FullWslPath) {
    # Try absolute path if resolve fails
    $FullWslPath = $OriginalWslFile
    if (-not (Test-Path $FullWslPath)) {
        Write-Fail "WSL image file not found: $OriginalWslFile"
        exit 1
    }
}
Write-OK "Found WSL image: $FullWslPath"

# 3. Create target directory
Write-Info "Creating target directory: $TargetDir"
New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
Write-OK "Created target directory"

# 4. Import WSL
Write-Info "Importing WSL (this may take 10-40 seconds)..."
wsl --import $DistroName $TargetDir $FullWslPath --version 2

if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL import failed, error code: $LASTEXITCODE"
    exit 1
}
Write-OK "WSL import completed, VHDX located at $TargetDir"

# 5. Automated user creation + sudo passwordless + default user setup
Write-Info "Creating user $LinuxUser and configuring environment..."

$SetupScript = @'
#!/bin/bash
set -e

USERNAME="PLACEHOLDER_USER"
PASSWORD="PLACEHOLDER_PASS"

if id "$USERNAME" &>/dev/null; then
    echo "User $USERNAME already exists, skipping creation"
else
    echo "Creating user $USERNAME ..."

    GROUPS=""
    for g in sudo adm cdrom dip plugdev lpadmin; do
        if getent group "$g" &>/dev/null; then
            GROUPS="${GROUPS:+$GROUPS,}$g"
        else
            echo "⚠️  Group $g does not exist, skipping"
        fi
    done

    if [ -z "$GROUPS" ]; then
        useradd -m -s /bin/bash "$USERNAME"
    else
        useradd -m -s /bin/bash -G "$GROUPS" "$USERNAME"
    fi

    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "✅ User $USERNAME created successfully"
fi

usermod -aG sudo "$USERNAME"

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME
chmod 440 /etc/sudoers.d/$USERNAME
echo "✅ Configured $USERNAME sudo passwordless"

cat > /etc/wsl.conf << EOF
[user]
default=$USERNAME
EOF

echo "✅ All user configuration completed!"
'@ -replace "PLACEHOLDER_USER", $LinuxUser -replace "PLACEHOLDER_PASS", $LinuxPass

$SetupScript = $SetupScript -replace "`r", ""

wsl -d $DistroName -u root --exec bash -c "$SetupScript"

if ($LASTEXITCODE -ne 0) {
    Write-Fail "User creation/configuration failed (error code: $LASTEXITCODE), please check the output above"
    exit 1
}
Write-OK "User $LinuxUser created, sudo passwordless configured"

# 6. Configure Chinese environment and locale
Write-Info "Configuring Chinese environment and locale..."

# First, check if zh_CN.UTF-8 locale is available
$localeCheck = wsl -d $DistroName -u $LinuxUser -- bash -c "locale -a | grep -q 'zh_CN.utf8' && echo 'AVAILABLE'" 2>&1

if ($localeCheck -match "AVAILABLE") {
    Write-OK "Chinese locale (zh_CN.UTF-8) is available"

    # Set environment variables for current session
    $localeSetupCommands = @"
export PYTHONIOENCODING=utf-8
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
echo 'Chinese environment configured for current session'
"@

    $localeSetupCommands = $localeSetupCommands -replace "`r", ""
$result = wsl -d $DistroName -u $LinuxUser --exec bash -c $localeSetupCommands 2>&1
    Write-Info $result
} else {
    Write-Warn "Chinese locale (zh_CN.UTF-8) not found in WSL"
    Write-Info "The Ubuntu-Init.sh script will install it on first run"
    Write-Info "After login, you can manually run: sudo locale-gen zh_CN.UTF-8 && sudo update-locale LANG=zh_CN.UTF-8"
}

# Always add environment variables to .bashrc for persistent configuration
$bashrcSetupCommands = @"
if ! grep -q 'Ubuntu-Init Chinese' ~/.bashrc; then
    echo '' >> ~/.bashrc
    echo '# --- Ubuntu-Init Chinese Environment ---' >> ~/.bashrc
    echo 'export PYTHONIOENCODING=utf-8' >> ~/.bashrc
    echo 'export LANG=zh_CN.UTF-8' >> ~/.bashrc
    echo 'export LC_ALL=zh_CN.UTF-8' >> ~/.bashrc
    echo '# --- end Ubuntu-Init Chinese Environment ---' >> ~/.bashrc
    echo 'Added Chinese environment variables to ~/.bashrc'
else
    echo 'Chinese environment variables already in ~/.bashrc'
fi
"@

$bashrcSetupCommands = $bashrcSetupCommands -replace "`r", ""
$bashrcResult = wsl -d $DistroName -u $LinuxUser --exec bash -c $bashrcSetupCommands 2>&1
Write-Info $bashrcResult

Write-OK "Chinese environment configuration completed"

# 7. Execute initialization script (if provided)
if ($InitScriptPath -and (Test-Path $InitScriptPath)) {
    Write-Info "Executing Linux initialization script: $InitScriptPath"

    # Get the relative path from current directory to the script
    $scriptFullPath = (Resolve-Path $InitScriptPath).Path
    $relativePath = Resolve-Path -Relative $scriptFullPath

    # Convert Windows path separators to forward slashes for Linux
    $linuxPath = $relativePath -replace '\\', '/'

    Write-Info "Linux path: $linuxPath"

    wsl -d $DistroName -u $LinuxUser --exec bash "$linuxPath"

    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Initialization script execution failed (error code: $LASTEXITCODE), but WSL environment is usable"
    } else {
        Write-OK "Initialization script execution completed"
    }
}

# 8. Restart WSL to apply default user configuration
Write-Info "Restarting WSL to apply default user configuration..."
wsl --terminate $DistroName
Start-Sleep -Seconds 3

# 9. Final verification
Write-Host "`n🎉 Installation completed! Verifying..." -ForegroundColor Magenta

Write-Host "`n--- Default user test ---" -ForegroundColor Cyan
$testUser = wsl -d $DistroName whoami 2>$null
if ($testUser -eq $LinuxUser) {
    Write-OK "Default user: $testUser"
} else {
    Write-Warn "Default user test: $testUser (expected: $LinuxUser)"
}

Write-Host "--- sudo passwordless test ---" -ForegroundColor Cyan
$testSudo = wsl -d $DistroName sudo whoami 2>$null
if ($testSudo -eq "root") {
    Write-OK "Sudo passwordless: OK"
} else {
    Write-Warn "Sudo passwordless test: $testSudo (expected: root)"
}

Write-Host "--- Current directory test ---" -ForegroundColor Cyan
$testPwd = wsl -d $DistroName pwd 2>$null
Write-Info "Current directory: $testPwd"

# 10. Usage instructions
Write-Host "`n✅ WSL distro '$DistroName' installation successful!" -ForegroundColor Green
Write-Host "`nStart command:" -ForegroundColor Yellow
Write-Host "   wsl -d $DistroName" -ForegroundColor White
Write-Host "`nTo change password, execute inside: passwd $LinuxUser" -ForegroundColor Gray
