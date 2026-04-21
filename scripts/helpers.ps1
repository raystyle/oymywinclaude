#Requires -Version 5.1

# ── 统一安装包缓存根目录 ──
$script:DevSetupRoot = "D:\DevSetup"

# ── VS Build Tools 共享路径 ──
$script:VSBuildTools_LayoutDir    = "D:\DevSetup\VSBuildTools\Layout"
$script:VSBuildTools_Bootstrapper = "D:\DevSetup\VSBuildTools\vs_buildtools.exe"
$script:VSBuildTools_CacheDir     = "C:\VSBuildToolsCache"
$script:VSBuildTools_InstallPath  = "D:\DevEnvs\VSBuildTools"

# ── 全局设置：确保外部 CLI 输出 UTF-8 正确显示（emoji/Unicode） ──
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Set-ConsoleUtf8 {
    <#
    .SYNOPSIS
        Set console encoding to UTF-8 for correct emoji/Unicode output from external tools.
        Call before running npm, uv, claude, playwright-cli or other Node.js/Rust CLIs.
    #>
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

function Refresh-Environment {
    <#
    .SYNOPSIS
        Reload PATH from Machine and User registry into current process.
        Use at the start of scripts that depend on tools installed by previous steps.
    #>
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath    = [Environment]::GetEnvironmentVariable("Path", "User")

    # Merge with deduplication while preserving order (Machine -> User)
    $pathSet = New-Object System.Collections.Generic.HashSet[string]
    $mergedPaths = New-Object System.Collections.Generic.List[string]

    foreach ($path in $machinePath -split ';') {
        if (-not [string]::IsNullOrWhiteSpace($path) -and $pathSet.Add($path)) {
            $mergedPaths.Add($path)
        }
    }
    foreach ($path in $userPath -split ';') {
        if (-not [string]::IsNullOrWhiteSpace($path) -and $pathSet.Add($path)) {
            $mergedPaths.Add($path)
        }
    }

    $env:Path = $mergedPaths -join ';'
}

function Save-WithProxy {
    <#
    .SYNOPSIS
        Download a file with automatic gh-proxy fallback and retry.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile,

        [ValidateRange(1, 300)]
        [int]$TimeoutSec = 30,

        [string]$UserAgent = ""
    )

    # Ensure parent directory exists
    $parentDir = Split-Path $OutFile -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    $invokeParams = @{ Uri = $Url; OutFile = $OutFile; TimeoutSec = $TimeoutSec; MaximumRedirection = 5 }
    if ($UserAgent) { $invokeParams['UserAgent'] = $UserAgent }

    # Try direct download (up to 2 attempts)
    for ($i = 1; $i -le 2; $i++) {
        try {
            Invoke-WebRequest @invokeParams -ErrorAction Stop
            Write-Host "[OK] Downloaded (direct)" -ForegroundColor Green
            return
        }
        catch {
            if ($i -lt 2) {
                Write-Host "[WARN] Direct attempt $i failed, retrying in 2s..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }

    # Try gh-proxy download (up to 2 attempts)
    for ($i = 1; $i -le 2; $i++) {
        try {
            Invoke-WebRequest @invokeParams -Uri "https://gh-proxy.org/$Url" -ErrorAction Stop
            Write-Host "[OK] Downloaded (gh-proxy)" -ForegroundColor Green
            return
        }
        catch {
            if ($i -lt 2) {
                Write-Host "[WARN] gh-proxy attempt $i failed, retrying in 2s..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }

    throw "Both download channels failed after retries. URL: $Url"
}

function Save-WithCache {
    <#
    .SYNOPSIS
        Download with caching to D:\DevSetup. First download caches the file
        and generates a .sha256 companion; subsequent calls verify hash from
        cache and copy, falling back to re-download on mismatch.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Url,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$CacheDir,

        [ValidateRange(1, 300)]
        [int]$TimeoutSec = 30,

        [string]$UserAgent = ""
    )

    $fullCacheDir = Join-Path $script:DevSetupRoot $CacheDir
    $cacheFile = Join-Path $fullCacheDir (Split-Path $OutFile -Leaf)
    $hashFile  = "$cacheFile.sha256"

    # Ensure parent directories exist
    $outParent = Split-Path $OutFile -Parent
    if ($outParent -and -not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }

    # Check cache hit
    if ((Test-Path $cacheFile) -and (Test-Path $hashFile)) {
        try {
            $expectedHash = (Get-Content $hashFile -Raw).Trim()
            $actualHash   = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
            if ($actualHash -eq $expectedHash) {
                $cacheSize = (Get-Item $cacheFile).Length
                if ($cacheSize -ge 1MB) {
                    $sizeStr = "{0:N1} MB" -f ($cacheSize / 1MB)
                } else {
                    $sizeStr = "{0:N0} KB" -f ($cacheSize / 1KB)
                }
                Write-Host "[OK] Using cached: $(Split-Path $cacheFile -Leaf) ($sizeStr)" -ForegroundColor Green
                Copy-Item -Path $cacheFile -Destination $OutFile -Force
                return
            }
            else {
                Write-Host "[WARN] Cache hash mismatch, re-downloading" -ForegroundColor Yellow
                Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
                Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Host "[WARN] Cache verification failed, re-downloading: $_" -ForegroundColor Yellow
            Remove-Item $cacheFile -Force -ErrorAction SilentlyContinue
            Remove-Item $hashFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Cache miss -- download via Save-WithProxy
    if (-not (Test-Path $fullCacheDir)) {
        New-Item -ItemType Directory -Path $fullCacheDir -Force | Out-Null
    }

    Save-WithProxy -Url $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -UserAgent $UserAgent

    # Cache the downloaded file + generate .sha256 companion
    try {
        Copy-Item -Path $OutFile -Destination $cacheFile -Force
        $hash = (Get-FileHash -Path $cacheFile -Algorithm SHA256).Hash
        Set-Content -Path $hashFile -Value $hash -NoNewline -Encoding UTF8
        Write-Host "[OK] Cached: $(Split-Path $cacheFile -Leaf) + .sha256 -> $fullCacheDir" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "[WARN] Failed to cache file: $_" -ForegroundColor Yellow
    }
}

function Get-GitHubRelease {
    <#
    .SYNOPSIS
        Fetch a GitHub release object (latest or by tag).
        Automatically falls back to ghproxy when rate limit is exceeded.
    .PARAMETER Repo
        GitHub repo in "owner/repo" format.
    .PARAMETER Tag
        Specific tag to fetch. If omitted, fetches latest.
    .OUTPUTS
        PSObject — full release object including assets[].digest
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [string]$Tag
    )

    $apiBase = "https://api.github.com/repos/$Repo/releases"
    $url = if ($Tag) { "$apiBase/tags/$Tag" } else { "$apiBase/latest" }

    $headers = @{ 'User-Agent' = 'ohmycode-installer' }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN"
    }

    try {
        $release = Invoke-RestMethod -Uri $url -Headers $headers -ErrorAction Stop
        return $release
    }
    catch {
        $errorBody = $null
        try {
            $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            # Error body is not JSON (e.g., HTML from Cloudflare), rethrow original error
            throw
        }

        # Check if rate limit exceeded
        if ($errorBody -and $errorBody.message -match "rate limit exceeded") {
            Write-Host "[WARN] GitHub API rate limit exceeded, falling back to ghproxy..." -ForegroundColor Yellow

            # Fallback to ghproxy
            $proxyUrl = "https://gh-proxy.com/https://api.github.com/repos/$Repo/releases"
            $proxyUrl = if ($Tag) { "$proxyUrl/tags/$Tag" } else { "$proxyUrl/latest" }

            try {
                $release = Invoke-RestMethod -Uri $proxyUrl -Headers $headers -ErrorAction Stop
                Write-Host "[OK] Successfully fetched via ghproxy" -ForegroundColor Green
                return $release
            }
            catch {
                Write-Host "[WARN] Could not check for updates (API rate limit)" -ForegroundColor Yellow
                throw "GitHub API rate limit exceeded and proxy fallback failed"
            }
        }
        else {
            # Not a rate limit error, rethrow
            throw
        }
    }
}

function Get-LatestGitHubVersion {
    <#
    .SYNOPSIS
        Convenience wrapper: returns version string from latest release.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Repo,
        [switch]$StripVPrefix
    )

    $release = Get-GitHubRelease -Repo $Repo
    $tag = $release.tag_name
    if ($StripVPrefix) { $tag = $tag -replace '^v', '' }
    return $tag
}

function Test-FileHash {
    <#
    .SYNOPSIS
        Verify SHA256 hash of a downloaded file against GitHub asset digest.
    .PARAMETER FilePath
        Path to the downloaded file.
    .PARAMETER Release
        GitHub release object from Get-GitHubRelease.
    .PARAMETER AssetName
        Exact file name of the asset to match in release.assets[].
    .RETURNS
        $true if verified or skipped (no digest available).
        Throws on mismatch.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Release,

        [Parameter(Mandatory)]
        [string]$AssetName
    )

    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

    # ---- Extract expected digest from release metadata ----
    $expectedDigest = $null
    if ($Release -and $Release.assets) {
        $asset = $Release.assets | Where-Object { $_.name -eq $AssetName } | Select-Object -First 1
        if ($asset -and $asset.digest -and $asset.digest -match '^sha256:(.+)$') {
            $expectedDigest = $Matches[1].ToUpper()
        }
    }

    # ---- Compare ----
    if ($expectedDigest) {
        if ($actualHash -eq $expectedDigest) {
            Write-Host "[OK] SHA256 verified: $actualHash" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "[FAIL] SHA256 mismatch!" -ForegroundColor Red
            Write-Host "       Expected: $expectedDigest" -ForegroundColor Red
            Write-Host "       Actual:   $actualHash" -ForegroundColor Red
            throw "Integrity check failed for $AssetName"
        }
    }
    else {
        # 2025-06 之前上传的 release 没有 digest 字段
        Write-Host "[WARN] No digest from GitHub API, hash verification skipped" -ForegroundColor Yellow
        Write-Host "       SHA256: $actualHash" -ForegroundColor DarkGray
        return $true
    }
}

function Add-UserPath {
    <#
    .SYNOPSIS
        Idempotently add a directory to user-level PATH
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Dir
    )
    $normalizedDir = $Dir.TrimEnd('\')
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $currentPath) { $currentPath = '' }
    $entries = ($currentPath -split ';') |
        ForEach-Object { $_.TrimEnd('\') } |
        Where-Object { $_ -ne '' }
    if ($entries -contains $normalizedDir) {
        Write-Host "[INFO] $Dir already in PATH" -ForegroundColor Cyan
    }
    else {
        # Avoid double semicolons
        $separator = if ($currentPath -and -not $currentPath.EndsWith(';')) { ';' } else { '' }
        $newPath = "$currentPath$separator$normalizedDir"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        $env:Path = "$env:Path;$normalizedDir"
        Write-Host "[OK] Added $Dir to user PATH" -ForegroundColor Green
    }
}

function Remove-UserPath {
    param(
        [Parameter(Mandatory)]
        [string]$Dir
    )
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $current) { return }

    $parts   = $current -split ';' | Where-Object { $_.TrimEnd('\') -ne $Dir.TrimEnd('\') }
    $cleaned = ($parts | Where-Object { $_ -ne '' }) -join ';'

    if ($cleaned -ne $current) {
        [Environment]::SetEnvironmentVariable("Path", $cleaned, "User")
        Write-Host "[OK] Removed from PATH: $Dir" -ForegroundColor Green
    }
}

function Test-ProfileEntry {
    <#
    .SYNOPSIS
        Check if a specific line exists in PowerShell profiles
    .PARAMETER Line
        The exact line to search for in profile files
    .OUTPUTS
        Hashtable with PS5 and PS7 status
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Line
    )

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(
        @{ Path = "$myDocs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"; Label = "PS5" }
        @{ Path = "$myDocs\PowerShell\Microsoft.PowerShell_profile.ps1";        Label = "PS7" }
    )

    $result = @{
        PS5 = $false
        PS7 = $false
        All = $false
    }

    foreach ($p in $profiles) {
        if (Test-Path $p.Path) {
            $content = Get-Content $p.Path -Raw -ErrorAction SilentlyContinue
            if ($content -match [regex]::Escape($Line)) {
                $result[$p.Label] = $true
            }
        }
    }

    $result.All = $result.PS5 -and $result.PS7
    return $result
}

function Show-ProfileStatus {
    <#
    .SYNOPSIS
        Display profile status in a formatted way
    .PARAMETER Line
        The line that should be in profile
    .PARAMETER Label
        Optional label for the line being checked
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,
        [string]$Label = "Profile entry"
    )

    $status = Test-ProfileEntry -Line $Line

    if ($status.All) {
        Write-Host "  Profile ($Label): OK (PS5 + PS7)" -ForegroundColor DarkGray
    }
    elseif ($status.PS5 -or $status.PS7) {
        $partial = if ($status.PS5) { "PS5" } else { "PS7" }
        Write-Host "  Profile ($Label): Partial ($partial only)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  Profile ($Label): NOT configured" -ForegroundColor DarkGray
    }
}

#region Version Management Functions

function Compare-SemanticVersion {
    <#
    .SYNOPSIS
        Compare two semantic version strings
    .DESCRIPTION
        Uses .NET [version] type for proper semantic version comparison.
        Handles cases like "1.2.10" > "1.2.3" correctly.
    .PARAMETER Current
        Current version string
    .PARAMETER Latest
        Latest/target version string
    .EXAMPLE
        Compare-SemanticVersion "1.2.3" "1.2.10"  # Returns -1 (upgrade available)
        Compare-SemanticVersion "1.2.3" "1.2.3"  # Returns 0 (equal)
        Compare-SemanticVersion "1.2.10" "1.2.3" # Returns 1 (current newer)
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string]$Current,

        [Parameter(Mandatory)]
        [string]$Latest
    )

    try {
        $currentVer = [version]$Current
        $latestVer = [version]$Latest

        if ($currentVer -lt $latestVer) {
            return -1  # Current < Latest, upgrade needed
        }
        elseif ($currentVer -gt $latestVer) {
            return 1   # Current > Latest, already have newer version
        }
        else {
            return 0   # Versions are equal
        }
    }
    catch {
        # If version parsing fails, fall back to string comparison
        if ($Current -eq $Latest) {
            return 0
        }
        elseif ($Current -lt $Latest) {
            return -1
        }
        else {
            return 1
        }
    }
}

function Test-VersionLocked {
    <#
    .SYNOPSIS
        Check if a tool version is locked
    .DESCRIPTION
        Reads D:\DevSetup\version-lock.json and checks if the specified
        tool has a locked version. Returns the locked version string or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName
    )

    $lockFile = "$script:DevSetupRoot\version-lock.json"
    if (-not (Test-Path $lockFile)) { return $null }

    try {
        $lockData = Get-Content -Path $lockFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($lockData.$ToolName) { return $lockData.$ToolName }
    }
    catch {
        # Corrupt lock file → treat as unlocked
        Write-Debug "Version lock file parse error: $_"
    }
    return $null
}

function Set-VersionLock {
    <#
    .SYNOPSIS
        Set or remove a version lock for a tool
    .PARAMETER ToolName
        Tool identifier (e.g. "git", "fzf", "python")
    .PARAMETER Version
        Version to lock. Pass empty string or $null to remove lock.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [AllowEmptyString()]
        [string]$Version = ""
    )

    $lockFile = "$script:DevSetupRoot\version-lock.json"

    # Ensure DevSetupRoot exists
    if (-not (Test-Path $script:DevSetupRoot)) {
        New-Item -ItemType Directory -Path $script:DevSetupRoot -Force | Out-Null
    }

    $lockData = @{}
    if (Test-Path $lockFile) {
        try {
            $lockData = Get-Content -Path $lockFile -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $lockData = @{}
        }
    }

    if ($Version) {
        $lockData[$ToolName] = $Version
    }
    else {
        $lockData.Remove($ToolName)
    }

    # Write back
    $lockData | ConvertTo-Json -Depth 1 | Set-Content -Path $lockFile -Encoding UTF8 -Force
}

function Test-UpgradeRequired {
    <#
    .SYNOPSIS
        Test if a tool upgrade is required
    .DESCRIPTION
        Checks version lock, then semantic version comparison.
        Locked tools return Required=false unless -Force is used.
    .PARAMETER Current
        Current installed version
    .PARAMETER Target
        Target version to install
    .PARAMETER ToolName
        Tool identifier for version lock lookup
    .PARAMETER Force
        If set, always returns true (skip lock and version check)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string]$Current,

        [Parameter(Mandatory)]
        [string]$Target,

        [string]$ToolName = "",

        [switch]$Force
    )

    # Check version lock (unless Force)
    if (-not $Force -and $ToolName) {
        $lockedVersion = Test-VersionLocked -ToolName $ToolName
        if ($lockedVersion) {
            return @{
                Required = $false
                Reason = "Version locked to $lockedVersion (use -Force to override)"
            }
        }
    }

    if ($Force) {
        return @{
            Required = $true
            Reason = "Force mode enabled"
        }
    }

    $comparison = Compare-SemanticVersion -Current $Current -Latest $Target

    if ($comparison -eq -1) {
        return @{
            Required = $true
            Reason = "Upgrade available: $Current → $Target"
        }
    }
    elseif ($comparison -eq 1) {
        return @{
            Required = $false
            Reason = "Current version ($Current) is newer than target ($Target)"
        }
    }
    else {
        return @{
            Required = $false
            Reason = "Already up to date: $Current"
        }
    }
}

function Backup-ToolVersion {
    <#
    .SYNOPSIS
        Backup current tool executable file
    .DESCRIPTION
        Creates a backup of the tool executable to a temporary directory.
        Backup is named with timestamp for rollback capability.
    .PARAMETER ToolName
        Name of the tool (used in backup directory name)
    .PARAMETER ExePath
        Full path to the executable to backup
    .EXAMPLE
        Backup-ToolVersion -ToolName "fzf" -ExePath "C:\Users\ray\.local\bin\fzf.exe"
        # Returns: C:\Users\ray\AppData\Local\Temp\fzf-backup-20250410-143000\fzf.exe
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$ExePath
    )

    if (-not (Test-Path $ExePath)) {
        throw "Executable not found: $ExePath"
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $env:TEMP "$ToolName-backup-$timestamp"
    $backupFile = Join-Path $backupDir (Split-Path $ExePath -Leaf)

    # Create backup directory
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    # Copy executable to backup
    Copy-Item -Path $ExePath -Destination $backupFile -Force

    return $backupFile
}

function Restore-ToolVersion {
    <#
    .SYNOPSIS
        Restore tool from backup
    .DESCRIPTION
        Restores a tool executable from backup location.
        Used when upgrade fails and rollback is needed.
    .PARAMETER ToolName
        Name of the tool
    .PARAMETER BackupPath
        Full path to the backup file
    .PARAMETER TargetPath
        Target location where executable should be restored
    .EXAMPLE
        Restore-ToolVersion -ToolName "fzf" -BackupPath "C:\...\fzf.exe" -TargetPath "C:\Users\ray\.local\bin\fzf.exe"
    # Restores fzf.exe from backup
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    if (-not (Test-Path $BackupPath)) {
        throw "Backup file not found: $BackupPath"
    }

    try {
        # Ensure target directory exists
        $targetDir = Split-Path $TargetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # Restore from backup
        Copy-Item -Path $BackupPath -Destination $TargetPath -Force
        Write-Host "[INFO] Restored $ToolName from backup" -ForegroundColor Cyan
    }
    catch {
        throw "Failed to restore $ToolName from backup: $_"
    }
}

#endregion Version Management Functions

#region Unified Output Functions

function Show-AlreadyInstalled {
    <#
    .SYNOPSIS
        Display unified "already installed" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [string]$Version = "",
        [string]$Location = ""
    )

    $versionInfo = if ($Version) { " $Version" } else { "" }
    Write-Host "[OK] Already installed: $Tool$versionInfo" -ForegroundColor Green

    if ($Location) {
        Write-Host "  Location: $Location" -ForegroundColor DarkGray
    }
}

function Show-Installing {
    <#
    .SYNOPSIS
        Display unified "installing" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component
    )

    Write-Host "[INFO] Installing $Component..." -ForegroundColor Cyan
}

function Show-InstallComplete {
    <#
    .SYNOPSIS
        Display unified "installation completed" message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Tool,
        [string]$Version = "",
        [string]$NextSteps = ""
    )

    $versionInfo = if ($Version) { " $Version" } else { "" }
    Write-Host "[OK] $Tool installation completed!$versionInfo" -ForegroundColor Green

    if ($NextSteps) {
        Write-Host "  $NextSteps" -ForegroundColor DarkGray
    }
}

function Show-InstallSuccess {
    <#
    .SYNOPSIS
        Display unified "installed" message for components
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,
        [string]$Location = ""
    )

    Write-Host "[OK] $Component installed" -ForegroundColor Green

    if ($Location) {
        Write-Host "  Location: $Location" -ForegroundColor DarkGray
    }
}

#endregion Unified Output Functions

#region Shim Deployment Functions

function Install-ShimExe {
    <#
    .SYNOPSIS
        Deploy a scoop-better-shimexe shim next to an existing script/cmd.
    .DESCRIPTION
        Downloads scoop-better-shimexe (with caching), extracts shim.exe,
        copies it as <TargetExePath>, and creates a companion .shim config
        file that points to the real script. Idempotent.
    .PARAMETER TargetExePath
        Full path where the shim .exe should be placed.
        Example: D:\DevEnvs\node\typescript-language-server.exe
    .PARAMETER ShimTargetPath
        Full path to the real script/cmd that the shim should invoke.
        Example: D:\DevEnvs\node\typescript-language-server.cmd
    .PARAMETER ShimArgs
        Optional additional arguments passed via the 'args = ' line in the .shim config.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetExePath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ShimTargetPath,

        [string]$ShimArgs = ""
    )

    # ---- Idempotent check ----
    $shimConfigPath = [System.IO.Path]::ChangeExtension($TargetExePath, ".shim")
    if ((Test-Path $TargetExePath) -and (Test-Path $shimConfigPath)) {
        $existingContent = (Get-Content $shimConfigPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existingContent -match [regex]::Escape("path = $ShimTargetPath")) {
            Show-AlreadyInstalled -Tool "shim: $(Split-Path $TargetExePath -Leaf)" -Location $TargetExePath
            return
        }
    }

    # ---- Validate target script exists ----
    if (-not (Test-Path $ShimTargetPath)) {
        throw "Shim target not found: $ShimTargetPath"
    }

    # ---- Download shimexe ----
    $ShimExeVersion = "3.2.1"
    $ShimExeUrl     = "https://github.com/kiennq/scoop-better-shimexe/releases/download/v$ShimExeVersion/shimexe-x86_64.zip"
    $ShimExeZipName = "shimexe-x86_64.zip"
    $tempZip        = Join-Path $env:TEMP $ShimExeZipName

    try {
        Write-Host "[INFO] Downloading shimexe v$ShimExeVersion..." -ForegroundColor Cyan
        Save-WithCache -Url $ShimExeUrl -OutFile $tempZip -CacheDir "shimexe"
    }
    catch {
        Write-Host "[ERROR] Failed to download shimexe: $_" -ForegroundColor Red
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        return
    }

    # ---- Extract ----
    $extractDir    = Join-Path $env:TEMP "shimexe-extract"
    $shimExeSource = Join-Path $extractDir "shim.exe"

    try {
        if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
        Expand-Archive -Path $tempZip -DestinationPath $extractDir -Force -ErrorAction Stop

        if (-not (Test-Path $shimExeSource)) {
            throw "shim.exe not found in extracted archive"
        }
    }
    catch {
        throw "Failed to extract shimexe: $_"
    }

    # ---- Deploy shim exe ----
    $targetDir = Split-Path $TargetExePath -Parent
    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    Copy-Item -Path $shimExeSource -Destination $TargetExePath -Force

    # ---- Create .shim config ----
    $shimLines = @("path = $ShimTargetPath")
    if ($ShimArgs) {
        $shimLines += "args = $ShimArgs"
    }
    Set-Content -Path $shimConfigPath -Value ($shimLines -join "`n") -NoNewline -Encoding UTF8

    # ---- Cleanup ----
    Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue

    Show-InstallSuccess -Component "shim: $(Split-Path $TargetExePath -Leaf)" -Location $TargetExePath
}

function Remove-ShimExe {
    <#
    .SYNOPSIS
        Remove a shim exe and its companion .shim config file.
    .PARAMETER TargetExePath
        Full path to the shim .exe to remove.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetExePath
    )

    $shimConfigPath = [System.IO.Path]::ChangeExtension($TargetExePath, ".shim")
    foreach ($file in @($TargetExePath, $shimConfigPath)) {
        if (Test-Path $file) {
            try {
                Remove-Item $file -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $file" -ForegroundColor Green
            }
            catch {
                Write-Host "[WARN] Could not remove $file : $_" -ForegroundColor Yellow
            }
        }
    }
}

#endregion Shim Deployment Functions

function Remove-PendingDeleteDirs {
    <#
    .SYNOPSIS
        Clean up any .pending-delete directories from previous uninstalls.
        Automatically removes stale *.pending-delete folders in PowerShell module paths.
        Falls back to child process if direct delete fails.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    $moduleDirs = @(
        "$myDocs\WindowsPowerShell\Modules\"
        "$myDocs\PowerShell\Modules\"
    )

    $childShell = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
    $cleaned = 0

    foreach ($dir in $moduleDirs) {
        if (-not (Test-Path $dir)) { continue }

        Get-ChildItem -Path $dir -Directory -Filter "*.pending-delete" -ErrorAction SilentlyContinue | ForEach-Object {
            $pendingPath = $_.FullName
            Write-Host "[INFO] Cleaning up stale .pending-delete: $($pendingPath)" -ForegroundColor DarkGray

            # Try direct delete first
            try {
                Remove-Item -Path $pendingPath -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Removed .pending-delete: $pendingPath" -ForegroundColor Green
                $cleaned++
                return
            }
            catch {
                Write-Host "[INFO] Direct delete failed, trying child process..." -ForegroundColor DarkGray
            }

            # Try child process delete
            $deleteScript = "Remove-Item -Path '$($pendingPath -replace "'","''")' -Recurse -Force -ErrorAction SilentlyContinue"
            $null = Start-Process -FilePath $childShell -ArgumentList @(
                '-NoProfile', '-NonInteractive', '-Command', $deleteScript
            ) -Wait -NoNewWindow

            if (-not (Test-Path $pendingPath)) {
                Write-Host "[OK] Removed .pending-delete (via child): $pendingPath" -ForegroundColor Green
                $cleaned++
            }
            else {
                Write-Host "[WARN] .pending-delete still locked: $pendingPath" -ForegroundColor Yellow
            }
        }
    }

    if ($cleaned -eq 0) {
        Write-Host "[INFO] No .pending-delete directories found" -ForegroundColor DarkGray
    }
}
