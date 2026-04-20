#Requires -Version 5.1

# =============================================
# just 一键部署脚本（中国网络友好版 · 最终版）
# 功能：自动获取最新版本 / 下载（直连→gh-proxy回退） / 解压 / PATH / 验证
# 安装目录：%USERPROFILE%\.local\bin
# 特性：完全幂等，支持 -version 手动指定版本
# =============================================

param(
    [string]$version  # 留空则自动获取最新版本
)

# ---- 配置 ----
$repo    = "casey/just"
$exeName = "just.exe"
$binDir  = "$env:USERPROFILE\.local\bin"
$exePath = "$binDir\$exeName"

# ---- 辅助函数：双通道下载 ----
function Save-WithProxy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [int]$TimeoutSec = 30
    )

    $proxyUrl = "https://gh-proxy.org/$Url"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        Write-Host "  ✅ 下载成功（直连）" -ForegroundColor Green
        return
    } catch {
        Write-Host "  ⚠️ 直连失败，切换 gh-proxy..." -ForegroundColor Yellow
    }

    try {
        Invoke-WebRequest -Uri $proxyUrl -OutFile $OutFile -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
        Write-Host "  ✅ 下载成功（gh-proxy）" -ForegroundColor Green
    } catch {
        throw "两个通道均下载失败，请检查网络。URL: $Url"
    }
}

# ---- 辅助函数：确保 PATH ----
function Assert-UserPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Dir
    )

    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = ($currentPath -split ';') | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ -ne '' }
    $dirNorm = $Dir.TrimEnd('\')

    if ($entries -notcontains $dirNorm) {
        [Environment]::SetEnvironmentVariable("Path", "$currentPath;$Dir", "User")
        $env:Path = "$env:Path;$Dir"
        Write-Host "🔧 已将 $Dir 添加到用户 PATH" -ForegroundColor Green
    } else {
        Write-Host "🔧 $Dir 已在 PATH 中" -ForegroundColor Yellow
    }
}

# ---- 1. 获取目标版本号 ----
if (-not $version) {
    Write-Host "🔍 正在从 GitHub API 获取最新版本..." -ForegroundColor Cyan
    $apiUrl = "https://api.github.com/repos/$repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 15 -ErrorAction Stop
        $version = $release.tag_name
        Write-Host "  📌 最新版本: $version" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ GitHub API 请求失败（$($_.Exception.Message)）" -ForegroundColor Yellow
        # 注意：gh-proxy 主要用于文件下载代理，API JSON 请求不一定支持
        # 此处作为 fallback 尝试，失败则要求用户手动指定版本
        try {
            $proxyApi = "https://gh-proxy.org/$apiUrl"
            $release = Invoke-RestMethod -Uri $proxyApi -TimeoutSec 15 -ErrorAction Stop
            $version = $release.tag_name
            Write-Host "  📌 最新版本: $version（via gh-proxy）" -ForegroundColor Green
        } catch {
            Write-Host "❌ 无法获取最新版本，请手动指定：" -ForegroundColor Red
            Write-Host "   .\install-just.ps1 -version '1.49.0'" -ForegroundColor Gray
            exit 1
        }
    }
}

Write-Host "📦 目标版本: just $version" -ForegroundColor Cyan
Write-Host "📁 安装目录: $binDir" -ForegroundColor Cyan

# ---- 2. 幂等检查：已安装且版本一致则跳过 ----
if (Test-Path $exePath) {
    try {
        $installedRaw = & $exePath --version 2>$null
        # 用正则提取纯版本号，兼容未来可能的输出格式变化
        $installed = if ($installedRaw -match '(\d+\.\d+\.\d+)') { $Matches[1] } else { '' }
        if ($installed -eq $version) {
            Write-Host "`n✅ just $version 已安装，无需操作。" -ForegroundColor Green
            Write-Host "   位置: $exePath" -ForegroundColor Gray
            Assert-UserPath -Dir $binDir
            exit 0
        }
        Write-Host "🔄 检测到 just $installed → 升级到 $version" -ForegroundColor Cyan
    } catch {
        Write-Host "⚠️ 已有 $exeName 但无法获取版本，将重新安装" -ForegroundColor Yellow
    }
}

# ---- 3. 下载 ----
$archiveName = "just-$version-x86_64-pc-windows-msvc.zip"
$downloadUrl = "https://github.com/$repo/releases/download/$version/$archiveName"
$zipFile     = "$env:TEMP\$archiveName"

Write-Host "`n🚀 下载 $archiveName ..." -ForegroundColor Cyan
try {
    Save-WithProxy -Url $downloadUrl -OutFile $zipFile
} catch {
    Write-Host "❌ $_" -ForegroundColor Red
    exit 1
}

# ---- 4. 解压 ----
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    Write-Host "📁 已创建: $binDir" -ForegroundColor Green
}

try {
    Expand-Archive -Path $zipFile -DestinationPath $binDir -Force -ErrorAction Stop
} catch {
    Write-Host "❌ 解压失败，文件可能已损坏。" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

if (-not (Test-Path $exePath)) {
    Write-Host "❌ 解压后未找到 $exeName，版本号或架构可能有误。" -ForegroundColor Red
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

# ---- 5. PATH ----
Assert-UserPath -Dir $binDir

# ---- 6. 清理 ----
Remove-Item $zipFile -Force -ErrorAction SilentlyContinue

# ---- 7. 验证 ----
Write-Host "`n🔍 验证安装..." -ForegroundColor Cyan
try {
    $result = & $exePath --version
    Write-Host "🎉 安装成功！$result" -ForegroundColor Green
    Write-Host "   位置: $exePath" -ForegroundColor Cyan
    Write-Host "`n✅ 现在可以在任意命令行使用 'just' 了！" -ForegroundColor Magenta
} catch {
    Write-Host "⚠️ 验证失败，请重新打开终端后重试。" -ForegroundColor Red
}

# ---- 8. 提示 ----
Write-Host "`n📋 下一步：" -ForegroundColor Cyan
Write-Host "   1. 项目根目录新建 justfile"
Write-Host '   2. 顶部加: set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]' -ForegroundColor White
Write-Host "   3. 运行 just --list 查看任务"
Write-Host "`n💡 用法：" -ForegroundColor Cyan
Write-Host "   .\install-just.ps1              # 自动安装/升级到最新版" -ForegroundColor Gray
Write-Host "   .\install-just.ps1 -version '1.48.0'  # 安装指定版本" -ForegroundColor Gray