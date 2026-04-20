#Requires -Version 5.1

<#
.SYNOPSIS
    Install SQLite CLI tools from sqlite.org
.DESCRIPTION
    Downloads SQLite tools bundle (sqlite3, sqldiff, sqlite3_analyzer, sqlite3_rsync)
    from sqlite.org and installs to ~/.local/bin.
    Supports idempotent install, upgrade, and SHA3-256 integrity verification.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [AllowEmptyString()]
    [string]$Version = "",

    [switch]$Force,
    [switch]$NoBackup
)

. "$PSScriptRoot\helpers.ps1"

$binDir   = "$env:USERPROFILE\.local\bin"
$exePath  = "$binDir\sqlite3.exe"
$toolName = "sqlite3"

# All executables shipped in the tools bundle
$allExes = @("sqlite3.exe", "sqldiff.exe", "sqlite3_analyzer.exe", "sqlite3_rsync.exe")

# ---- Helper: Convert semantic version (3.X.Y) to sqlite version number (3XXYY00) ----
function ConvertTo-SqliteVersionNumber {
    param([string]$SemanticVersion)
    if ($SemanticVersion -match '^(\d+)\.(\d+)\.(\d+)$') {
        $major = [int]$Matches[1]
        $minor = [int]$Matches[2]
        $patch = [int]$Matches[3]
        return "{0}{1:D2}{2:D2}00" -f $major, $minor, $patch
    }
    return $SemanticVersion
}

# ---- Helper: Extract SHA3-256 hash using .NET (PS 7 / .NET 8+) ----
function Get-SHA3_256Hash {
    <#
    .SYNOPSIS
        Compute SHA3-256 hash of a file. Returns $null on PS 5.1 (not supported).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath)

    try {
        $sha3 = [System.Security.Cryptography.SHA3_256]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        $hashBytes = $sha3.ComputeHash($stream)
        $stream.Close()
        $sha3.Dispose()
        return ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ''
    }
    catch {
        return $null
    }
}

# ---- Helper: Parse SQLite download page for latest version info ----
function Get-LatestSqliteInfo {
    <#
    .SYNOPSIS
        Fetch sqlite.org/download.html and parse the embedded CSV product data.
        Returns version, relative URL (with year), and SHA3-256 hash.
    .OUTPUTS
        Hashtable with Version (3.X.Y), RelativeUrl (YYYY/...zip), SHA3Hash
    #>
    Write-Host "[INFO] Fetching latest SQLite version..." -ForegroundColor Cyan

    $downloadPageUrl = "https://sqlite.org/download.html"
    try {
        $response = Invoke-WebRequest -Uri $downloadPageUrl -TimeoutSec 30 -ErrorAction Stop
        $content = $response.Content
    }
    catch {
        throw "Failed to fetch sqlite.org/download.html: $_"
    }

    # The page embeds a CSV comment: PRODUCT,VERSION,RELATIVE-URL,SIZE-IN-BYTES,SHA3-HASH
    # Find the line for sqlite-tools-win-x64
    $pattern = 'PRODUCT,([^,]+),(\d{4}/sqlite-tools-win-x64-\d{7}\.zip),(\d+),([a-f0-9]{64})'
    if ($content -match $pattern) {
        return @{
            Version      = $Matches[1]
            RelativeUrl  = $Matches[2]
            SHA3Hash     = $Matches[4]
        }
    }

    throw "Could not parse SQLite product data from download page"
}

# ---- 1. Resolve version ----
$verNum      = ""
$year        = ""
$expectedHash = $null

if (-not $Version) {
    try {
        $info = Get-LatestSqliteInfo
        $Version      = $info.Version
        $expectedHash = $info.SHA3Hash
        # Extract version number and year from relative URL: YYYY/sqlite-tools-win-x64-NNNNNNN.zip
        if ($info.RelativeUrl -match '^(\d{4})/sqlite-tools-win-x64-(\d{7})\.zip$') {
            $year   = $Matches[1]
            $verNum = $Matches[2]
        }
        Write-Host "[OK] Latest version: $Version ($verNum)" -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not determine latest version" -ForegroundColor Yellow

        if (Test-Path $exePath) {
            Write-Host "[INFO] Tool already installed, skipping version check..." -ForegroundColor Cyan
            Add-UserPath -Dir $binDir
            exit 0
        }
        else {
            Write-Host "[ERROR] Cannot determine version to install" -ForegroundColor Red
            Write-Host "       Please try again later or specify version: .\install-sqlite.ps1 -Version 3.53.0" -ForegroundColor DarkGray
            exit 1
        }
    }
}
else {
    $verNum = ConvertTo-SqliteVersionNumber -SemanticVersion $Version
    # Need to fetch page for SHA3 hash and correct year
    try {
        $info = Get-LatestSqliteInfo
        $expectedHash = $info.SHA3Hash
        if ($info.RelativeUrl -match '^(\d{4})/') {
            $year = $Matches[1]
        }
    }
    catch {
        # If page fetch fails, use current year
        $year = (Get-Date).Year.ToString()
    }
    Write-Host "[INFO] Target: SQLite $Version ($verNum)" -ForegroundColor Cyan
}

# ---- 2. Idempotent check ----
$backupPath = $null
if (Test-Path $exePath) {
    $raw = & $exePath --version 2>&1 | Out-String
    $installed = ''
    if ($raw -match '(\d+\.\d+\.\d+)') {
        $installed = $Matches[1]
    }

    $upgradeCheck = Test-UpgradeRequired -Current $installed -Target $Version -ToolName $toolName -Force:$Force

    if (-not $upgradeCheck.Required) {
        Write-Host "[OK] SQLite $Version already installed, skipping." -ForegroundColor Green
        Write-Host "     $($upgradeCheck.Reason)" -ForegroundColor DarkGray
        Add-UserPath -Dir $binDir
        exit 0
    }

    if ($installed) {
        Write-Host "[UPGRADE] $installed -> $Version" -ForegroundColor Cyan
        Write-Host "     Reason: $($upgradeCheck.Reason)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "[WARN] sqlite3.exe exists but version unreadable, reinstalling" -ForegroundColor Yellow
    }

    if (-not $Force) {
        Write-Host ""
        Write-Host "  This will:" -ForegroundColor Cyan
        Write-Host "    • Backup current version" -ForegroundColor DarkGray
        Write-Host "    • Uninstall old version" -ForegroundColor DarkGray
        Write-Host "    • Install new version" -ForegroundColor DarkGray
        Write-Host "    • Verify installation" -ForegroundColor DarkGray
        Write-Host "    • Rollback on failure" -ForegroundColor DarkGray
        Write-Host ""
        $response = Read-Host "  Continue? [Y/n]"
        if ($response -and $response -ne 'Y' -and $response -ne 'y') {
            Write-Host "[INFO] Upgrade cancelled by user" -ForegroundColor Cyan
            exit 0
        }
    }

    if (-not $NoBackup) {
        try {
            Write-Host "[INFO] Backing up current version..." -ForegroundColor Cyan
            $backupPath = Backup-ToolVersion -ToolName $toolName -ExePath $exePath
            Write-Host "[OK] Backed up to: $backupPath" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Backup failed: $_" -ForegroundColor Yellow
            Write-Host "[WARN] Proceeding without backup" -ForegroundColor Yellow
            $backupPath = $null
        }
    }

    Write-Host "[INFO] Uninstalling old version..." -ForegroundColor Cyan
    $uninstallScript = "$PSScriptRoot\uninstall-sqlite.ps1"
    if (Test-Path $uninstallScript) {
        try {
            & $uninstallScript -Force
        }
        catch {
            Write-Host "[WARN] Uninstall script failed: $_" -ForegroundColor Yellow
            foreach ($e in $allExes) {
                Remove-Item "$binDir\$e" -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        foreach ($e in $allExes) {
            Remove-Item "$binDir\$e" -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---- 3. Download ----
$archiveName = "sqlite-tools-win-x64-$verNum.zip"
$downloadUrl = "https://sqlite.org/$year/$archiveName"
$zipFile = "$env:TEMP\$archiveName"

Write-Host "[INFO] Downloading $archiveName ..." -ForegroundColor Cyan
try {
    Save-WithCache -Url $downloadUrl -OutFile $zipFile -CacheDir "sqlite"
}
catch {
    Write-Host "[ERROR] Failed to download $archiveName" -ForegroundColor Red
    Write-Host "       URL: $downloadUrl" -ForegroundColor DarkGray
    exit 1
}

# ---- 4. Verify SHA3-256 digest ----
Write-Host "[INFO] Verifying SHA3-256 hash..." -ForegroundColor Cyan
$actualHash = Get-SHA3_256Hash -FilePath $zipFile
if ($null -eq $actualHash) {
    Write-Host "[WARN] SHA3-256 not supported on PowerShell $([string]$PSVersionTable.PSVersion)" -ForegroundColor Yellow
    Write-Host "[WARN] Hash verification skipped" -ForegroundColor Yellow
}
elseif ($expectedHash) {
    if ($actualHash -eq $expectedHash) {
        Write-Host "[OK] SHA3-256 verified" -ForegroundColor Green
    }
    else {
        Write-Host "[ERROR] SHA3-256 mismatch!" -ForegroundColor Red
        Write-Host "       Expected: $expectedHash" -ForegroundColor DarkGray
        Write-Host "       Actual:   $actualHash" -ForegroundColor DarkGray
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
}
else {
    Write-Host "[WARN] Expected hash not available, verification skipped" -ForegroundColor Yellow
}

# ---- 5. Extract ----
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Write-Host "[OK] Created: $binDir" -ForegroundColor Green
}

$extractDir = "$env:TEMP\sqlite-extract"
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

try {
    Expand-Archive -Path $zipFile -DestinationPath $extractDir -Force -ErrorAction Stop
}
catch {
    Write-Host "[ERROR] Failed to extract $archiveName" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# Find and copy all executables from the extracted directory
$extractedExes = Get-ChildItem -Path $extractDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue
$installedCount = 0
foreach ($extracted in $extractedExes) {
    $targetPath = Join-Path $binDir $extracted.Name
    try {
        Move-Item -Path $extracted.FullName -Destination $targetPath -Force -ErrorAction Stop
        Write-Host "[OK] Installed: $($extracted.Name)" -ForegroundColor Green
        $installedCount++
    }
    catch {
        Write-Host "[WARN] Failed to install $($extracted.Name): $_" -ForegroundColor Yellow
    }
}

# Cleanup extraction temp dir
Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

if ($installedCount -eq 0) {
    Write-Host "[ERROR] No executables found in archive" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 6. PATH + cleanup ----
Add-UserPath -Dir $binDir
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

# ---- 7. Verify ----
Write-Host "[INFO] Verifying..." -ForegroundColor Cyan
$result = & $exePath --version 2>&1 | Out-String
if ($result -match '(\d+\.\d+\.\d+)') {
    $installedVersion = $Matches[1]
    if ($installedVersion -eq $Version) {
        Write-Host "[OK] Installed: SQLite $($result.Trim())" -ForegroundColor Green
        Write-Host "[INFO] Tools installed: $installedCount executables" -ForegroundColor Cyan

        # Clean up backup on successful upgrade
        if ($backupPath -and (Test-Path (Split-Path $backupPath -Parent))) {
            try {
                Remove-Item (Split-Path $backupPath -Parent) -Recurse -Force -ErrorAction Stop
                Write-Host "[INFO] Cleaned up backup" -ForegroundColor Cyan
            }
            catch {
                # Cleanup failed, but installation succeeded — ignore to avoid masking the real success
                Write-Verbose "Failed to clean up backup: $_"
            }
        }
    }
    else {
        Write-Host "[ERROR] Version mismatch! Expected: $Version, Got: $installedVersion" -ForegroundColor Red

        if ($backupPath -and (Test-Path $backupPath)) {
            Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
            try {
                Restore-ToolVersion -ToolName $toolName -BackupPath $backupPath -TargetPath $exePath
                Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Rollback failed: $_" -ForegroundColor Red
            }
        }
        exit 1
    }
}
else {
    Write-Host "[ERROR] Verification failed, executable not responding" -ForegroundColor Red

    if ($backupPath -and (Test-Path $backupPath)) {
        Write-Host "[INFO] Rolling back from backup..." -ForegroundColor Cyan
        try {
            Restore-ToolVersion -ToolName $toolName -BackupPath $backupPath -TargetPath $exePath
            Write-Host "[OK] Rolled back to previous version" -ForegroundColor Green
            Write-Host "[INFO] Backup retained at: $backupPath" -ForegroundColor Cyan
        }
        catch {
            Write-Host "[ERROR] Rollback failed: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "[ERROR] No backup available, cannot rollback" -ForegroundColor Red
    }
    exit 1
}
