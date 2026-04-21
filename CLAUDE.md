# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Oh My WinClaude — Windows 开发环境一键配置工具。基于
[just](https://github.com/casey/just) 任务 runner，通过幂等 PowerShell
脚本管理开发工具的安装、更新和卸载。支持中国网络环境
（直连 → gh-proxy.org 自动回退）。

## Commands

```bash
just --list                    # 列出所有命令（按组分类）
just install-base              # 安装所有开发工具（cli + build + database + shell）
just install-cli               # 安装 CLI 工具（含自动解除安全限制）
just install-build             # 安装构建工具
just install-shell             # 安装 Shell 工具
just install-claude            # 安装 Claude Code + 插件 + Playwright
just status-base               # 检查所有开发工具状态
just config-claude             # 深度合并 Claude Code 配置（从模板）
just test                      # 运行全部测试（结构 + Lint + 状态）
just test-structure            # 仅结构检查
just test-lint                 # 仅 Lint 检查
just lock <tool> [ver]         # 锁定工具版本（阻止升级）
just unlock <tool>             # 解除版本锁定
```

单工具操作示例：
```bash
just install-fzf               # 安装单个工具
just status-fzf                # 检查单个工具
just uninstall-fzf             # 卸载单个工具
powershell -File scripts/install-tool.ps1 -Repo "owner/repo" -ExeName "tool.exe" -ArchiveName "tool.zip" -TagPrefix "v" -CacheDir "tool"  # 直接调用脚本
```

## Architecture

四层结构：justfile → scripts/ → helpers.ps1 → templates/marketplace

### justfile

入口，定义 install/uninstall/status/config 四类命令。`just --list` 按组显示。
复合命令用依赖语法 `(install-git) (install-fzf) ...` 串联，忽略失败用 `-` 前缀。
变量定义在顶部（字体 URL/名称、WSL 配置等），通过 `{{变量名}}` 传入脚本。

### Script Layer (scripts/)

四种安装器模式：

1. **通用安装器** `install-tool.ps1` — 参数化 GitHub Release 工具
   （fzf, ripgrep, starship, psmux, duckdb, nushell）。参数：`-Repo`、
   `-ExeName`、`-ArchiveName`（支持 `{version}`/`{tag}` 模板）、
   `-TagPrefix`、`-CacheDir`、`-Force`、`-NoBackup`、`-DirectExe`。
2. **模块安装器** `install-module.ps1` — PSGallery nupkg 安装
   （PSFzf 等），自动安装到 PS5 和 PS7 模块路径。参数：`-Repo`、`-ModuleName`、`-TagPrefix`。
3. **MSI 安装器** `install-powershell7.ps1` — 通过 `msiexec /quiet` 安装。
4. **专用脚本** — 复杂工具各有独立脚本（Git, Python, Node, Go, Claude, SQLite, WSL, Font, mq, jq 等）。

每个 install 都有对应的 `check-*.ps1` 和 `uninstall-*.ps1`。
所有脚本通过 `. "$PSScriptRoot\helpers.ps1"` 加载共享函数
（独立脚本见 test-structure.ps1 的 `$standaloneScripts` 和 `$genericModuleScripts`）。

### helpers.ps1

dot-source 时自动设置：`$script:DevSetupRoot`（`D:\DevSetup`）、
`$script:VSBuildTools_*`、`[Console]::OutputEncoding = UTF8`。

函数按 `#region` 分组：环境（PATH 管理）、下载（代理回退 + 缓存 + SHA256）、
GitHub API（限速回退）、版本管理（比较 + 锁定 + 备份回滚）、
Profile 条目、统一输出、Shim 部署、锁定目录清理。

### templates/ 与 marketplace/

`ensure-config.ps1` 从 templates/ 部署配置，支持 `-Merge`（JSON 深度合并）和直接覆盖。

本地市场插件定义在 `marketplace/plugins/<name>/.claude-plugin/plugin.json`，
LSP 配置内联在 `lspServers` 字段。`install-claude-plugin.ps1` 的
`Register-Plugin` / `Enable-Plugin` 处理注册和启用。

## Testing

```bash
just test-structure   # 结构验证：#Requires 头部、CmdletBinding、helpers.ps1 引用、install/check/uninstall 配对
just test-lint        # PSScriptAnalyzer Lint（6 个排除规则）
just test-status      # 运行所有 status 命令验证工具状态
just test             # 以上全部
```

## Conventions

### PowerShell Scripts

- **最低兼容**: `#Requires -Version 5.1`（Windows PowerShell 5.1）
- **幂等性**: 所有安装脚本可安全重复执行
- **参数块**: 使用 `[CmdletBinding()]` 和 `param()`
- **Profile 管理**: 通过 `profile-entry.ps1`，禁止直接操作 `$PROFILE`
- **依赖刷新**: 脚本开头调用 `Refresh-Environment` 获取前序步骤安装的工具
- **错误处理**: 禁止空 catch 块

### Output Format

- 标签: `[OK]` `[INFO]` `[WARN]` `[ERROR]` `[UPGRADE]`
- 颜色: Green=OK, Cyan=INFO, Yellow=WARN, Red=ERROR
- 标题用 `--- Title ---`，不使用 `===`
- 使用 `Show-*` 辅助函数保持统一

### Installation Paths

- 便携式 CLI: `%USERPROFILE%\.local\bin`（fzf, ripgrep, starship, psmux, mq, duckdb, sqlite3, nu, just）
- 系统级 MSI: `%ProgramFiles%\PowerShell\7\`（PowerShell 7）
- 开发环境: `D:\DevEnvs\`（Git, Rust, Python, Node.js, Go, VS Build Tools）
- 下载缓存: `D:\DevSetup\` + `.sha256` 校验文件
- 版本锁定: `D:\DevSetup\version-lock.json`

### Download Strategy

直连优先，失败自动切换 `gh-proxy.org`。GitHub API 支持 `GITHUB_TOKEN`，
限速回退 `gh-proxy.com`。优先使用 GitHub Release `assets[].digest` 做 SHA256 校验。

### Version Management

升级流程: backup → uninstall → install → verify → 失败回滚。
`Test-UpgradeRequired` 返回 `{Required, Reason}`，支持 `-ToolName` 检查版本锁定。
锁定后跳过升级（`-Force` 可覆盖）。

### Git Commit Messages

Conventional Commits: `type(scope): description`

| type | 用途 |
|------|------|
| `feat` | 新增功能/工具 |
| `fix` | 修复 bug |
| `perf` | 性能优化 |
| `refactor` | 代码重构 |
| `docs` | 文档变更 |
| `chore` | 构建/CI/杂项 |
| `revert` | 回退提交 |

规则：scope 可选（目录或模块名），英文祈使句不超过 72 字符，单次提交只做一类变更。

### File Encoding (.gitattributes)

`.sh`: LF | `.ps1/.psm1/.psd1`: CRLF | `.json/.toml/.yaml/.md`: LF

## Coding Guidelines

- 每个脚本独立可调用 — `install-*.ps1` / `check-*.ps1` / `uninstall-*.ps1` 独立运行
- 优先复用 helpers.ps1 中的函数，避免重复逻辑
- 新增通用工具遵循 `install-tool.ps1` 模式（Repo/Exe/Archive/Tag 参数），单 exe 用 `-DirectExe`
- 复杂工具（VS Build Tools, WSL, Python, Node, Go）使用专用脚本
- 新增 LSP 插件：创建 `marketplace/plugins/<name>/.claude-plugin/plugin.json`，
  `lspServers` 内联，然后在 marketplace.json 注册，更新 `ValidateSet` 和注册逻辑
- VS Build Tools 路径必须引用 helpers.ps1 中的 `$script:VSBuildTools_*` 共享常量
- 卸载脚本必须声明 `[switch]$Force` 参数（即使未使用），确保非交互升级时 `-Force` 传递不报错
- Claude Code 插件操作必须检查 `$LASTEXITCODE`，不得用 `*>$null` 吞掉错误输出
- `claude plugin list` 输出匹配使用非贪婪 `[\s\S]*?`，避免跨插件误匹配
- 插件注册后自动调用 `Enable-Plugin`；缓存 list output 避免重复调用 `claude plugin list`
