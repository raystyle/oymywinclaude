# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Oh My WinClaude — Windows 开发环境一键配置工具。基于 [just](https://github.com/casey/just) 任务 runner，通过幂等 PowerShell 脚本管理开发工具的安装、更新和卸载。支持中国网络环境（直连 → gh-proxy.org 自动回退）。

## Commands

justfile 中命令分 10 组，`just --list` 按组显示：

| 组 | 用途 |
|----|------|
| `default` | 聚合命令（install-base, install-cli, install-build, install-claude 等批量操作） |
| `cli` | CLI 工具（fzf, jq, ripgrep, starship, psmux, mq, Python, Node, Playwright, 字体, TS LSP） |
| `claude-cli` | Git for Windows + Claude Code CLI 二进制安装 + API 密钥配置 |
| `claude-plugin` | Claude Code 插件市场注册 + LSP/技能插件安装 + Playwright 技能 |
| `build` | 构建工具（VS Build Tools, Rust, Go, Jupyter） |
| `database` | 数据库 CLI（DuckDB, SQLite） |
| `shell` | Shell 工具（PowerShell 7, PSFzf, PSLSP, PSScriptAnalyzer, Nushell） |
| `wsl` | WSL (Ubuntu 24.04) |
| `config` | 配置管理（starship, psmux, VS Code 字体, Claude 配置, 版本锁定） |
| `dev` | 测试（结构检查 + Lint + 状态检查） |

Claude Code 相关命令分三层，`just install-claude` 串联前两层：

| 层级 | 组 | 职责 | 命令示例 |
|------|----|------|----------|
| 二进制+配置 | `claude-cli` | Git、Claude CLI 安装/卸载，API 密钥设置 | `install-git`, `install-claude-cli`, `setup-claude` |
| 插件+技能 | `claude-plugin` | 市场注册、LSP 插件、Playwright 技能 | `install-claude-marketplace`, `install-claude-plugin astral` |
| 聚合入口 | `default` | 一键安装全部（= git + cli + 插件 + 技能 + 配置） | `install-claude`, `uninstall-claude`, `status-claude` |

常用聚合命令：

```bash
just install-base        # 安装所有开发工具（cli + build + database + shell）
just install-cli         # 安装 CLI 工具（含自动解除安全限制）
just install-build       # 安装构建工具
just install-shell       # 安装 Shell 工具（pwsh + PSFzf + PSLSP + PSSA + Nushell）
just install-claude      # 安装 Claude Code + 插件 + Playwright 技能
just status-base         # 检查所有开发工具状态
just config-claude       # 深度合并 Claude Code 配置（从模板）
just test                # 运行全部测试（结构 + Lint + 状态）
just lock <tool> [ver]   # 锁定工具版本（阻止升级）
```

## Architecture

四层结构：justfile → scripts/ → helpers.ps1 → templates/marketplace

### Task Runner Layer (justfile)

入口，定义 install/uninstall/status/config 四类命令。每个命令调用 `scripts/` 下对应的 PowerShell 脚本。复合命令用依赖语法 `(install-git) (install-fzf) ...` 串联。忽略失败的命令用 `-` 前缀。

### Script Layer (scripts/)

四种脚本模式：

1. **通用安装器** `install-tool.ps1` — 参数化 GitHub Release 工具（fzf, ripgrep, starship, psmux, mq, duckdb, nushell）。支持 zip 解压和 `-DirectExe` 单 exe 复制。
2. **模块安装器** `install-module.ps1` — PSGallery nupkg 安装（PSReadLine, PSFZF 等）。
3. **MSI 安装器** `install-powershell7.ps1` — 通过 `msiexec /quiet` 安装。
4. **专用脚本** `install-*.ps1` — 复杂工具各有独立脚本（VS Build Tools, Python, Go, Claude, SQLite 等）。

每个安装脚本都有对应的 `check-*.ps1` 和 `uninstall-*.ps1`。所有脚本通过 `. "$PSScriptRoot\helpers.ps1"` 加载共享函数。

### Shared Helpers (scripts/helpers.ps1)

dot-source 时自动设置顶层变量：`$script:DevSetupRoot`（`D:\DevSetup`）、`$script:VSBuildTools_*`、`[Console]::OutputEncoding = UTF8`。

核心函数：`Save-WithProxy`（下载+代理回退）、`Save-WithCache`（SHA256 缓存）、`Get-GitHubRelease`/`Get-LatestGitHubVersion`、`Add-UserPath`/`Remove-UserPath`/`Refresh-Environment`、`Compare-SemanticVersion`/`Test-UpgradeRequired`/`Test-VersionLocked`/`Set-VersionLock`、`Backup-ToolVersion`/`Restore-ToolVersion`、`Show-*`（统一输出）、`Install-ShimExe`/`Remove-ShimExe`。

### Config & Plugin Layer

- **templates/** — `ensure-config.ps1` 从此处部署配置文件（starship.toml, psmux.conf, claude-settings.json, hooks），支持覆盖和深度合并（`-Merge`）。
- **marketplace/** — 本地开发市场，插件放在 `marketplace/plugins/<name>/.claude-plugin/plugin.json`，LSP 配置内联在 `lspServers` 字段中。
  - **LSP 插件**: powershell-lsp, typescript-lsp, astral (含 ty LSP)
  - **技能插件**: skill-creator (创建、测试和改进 Claude 技能)
  - 插件管理脚本支持 `typescript`、`powershell`、`astral`、`skill-creator`、`all` 五种类型。

## Conventions

### PowerShell Scripts
- **最低兼容**: `#Requires -Version 5.1`（Windows PowerShell 5.1）
- **幂等性**: 所有安装脚本可安全重复执行
- **参数块**: 使用 `[CmdletBinding()]` 和 `param()`
- **Profile 管理**: 通过 `profile-entry.ps1`，禁止直接操作 `$PROFILE`
- **依赖刷新**: 脚本开头调用 `Refresh-Environment` 以获取前序步骤安装的工具
- **错误处理**: 禁止空 catch 块，使用 `Write-Verbose` 或具体错误处理
- **输出风格**: 标题使用 `--- Title ---` 格式，不使用 `===`

### Output Format
- 标签: `[OK]` `[INFO]` `[WARN]` `[ERROR]` `[UPGRADE]`
- 颜色: Green=OK, Cyan=INFO, Yellow=WARN, Red=ERROR
- 使用 `Show-*` 辅助函数保持统一

### Installation Paths
- 便携式 CLI: `%USERPROFILE%\.local\bin`（fzf, ripgrep, starship, psmux, mq, duckdb, sqlite3, nu, just）
- 系统级 MSI: `%ProgramFiles%\PowerShell\7\`（PowerShell 7）
- 开发环境: `D:\DevEnvs\`（Git, Rust, Python, Node.js, Go, VS Build Tools）
- 下载缓存: `D:\DevSetup\` + `.sha256` 校验文件
- 版本锁定: `D:\DevSetup\version-lock.json`

### Download Strategy
- 直连优先，失败自动切换 `gh-proxy.org`
- GitHub API 支持 `GITHUB_TOKEN`；限速回退 `gh-proxy.com`
- SHA256 校验（优先使用 GitHub Release `assets[].digest`）
- SHA3-256 校验（SQLite 专用，PS 5.1 不支持时跳过）

### Version Management
- 升级流程: backup → uninstall → install → verify → 失败回滚
- `Test-UpgradeRequired` 返回 `{Required, Reason}`，支持 `-ToolName` 检查版本锁定
- 锁定后跳过升级（`-Force` 可覆盖）

### Git Commit Messages

使用 Conventional Commits 格式，`type(scope): description`：

| type | 用途 | 示例 |
|------|------|------|
| `feat` | 新增功能/工具 | `feat(cli): add uv package manager support` |
| `fix` | 修复 bug | `fix(install): resolve proxy fallback loop on timeout` |
| `perf` | 性能优化 | `perf(helpers): skip SHA256 check when digest unavailable` |
| `refactor` | 代码重构（不改变行为） | `refactor(install-tool): extract version compare logic` |
| `docs` | 文档变更 | `docs: update CLAUDE.md with git conventions` |
| `chore` | 构建/CI/杂项 | `chore: update .gitattributes encoding rules` |
| `revert` | 回退提交 | `revert: revert feat(cli): add uv package manager` |

规则：
- `feat` / `fix` / `perf` 应出现在 CHANGELOG 中
- scope 为可选的目录或模块名（如 `cli`、`helpers`、`claude-plugin`）
- 描述用英文祈使句，不超过 72 字符
- 单次提交只做一类变更，不要混合 `feat` + `fix`

### File Encoding (.gitattributes)
- `.sh`: LF | `.ps1/.psm1/.psd1`: CRLF | `.json/.toml/.yaml/.md`: LF

## Coding Guidelines

- 每个脚本独立可调用 — `install-*.ps1` / `check-*.ps1` / `uninstall-*.ps1` 独立运行
- 优先复用 helpers.ps1 中的函数，避免重复逻辑
- 新增通用工具遵循 `install-tool.ps1` 模式（Repo/Exe/Archive/Tag 参数）
- 单 exe 分发的工具（非 zip）使用 `-DirectExe` 开关
- 复杂工具（VS Build Tools, WSL, Python, Node）使用专用脚本
- 新增本地市场 LSP 插件：创建 `marketplace/plugins/<name>/.claude-plugin/plugin.json`，`lspServers` 内联，然后在 `marketplace/.claude-plugin/marketplace.json` 注册，并更新插件脚本（install/check/uninstall）的 `ValidateSet`、注册逻辑和汇总列表
- 新增技能插件：创建 `marketplace/plugins/<name>/skills/<skill-name>/SKILL.md`，可选包含 scripts/、agents/、references/ 子目录
- VS Build Tools 相关路径必须引用 helpers.ps1 中的 `$script:VSBuildTools_*` 共享常量
- 卸载脚本必须将 `$Force` 传递给子脚本，确保非交互运行
- Claude Code 插件操作必须检查 `$LASTEXITCODE`，不得用 `*>$null` 吞掉错误输出
- `claude plugin list` 输出匹配使用非贪婪 `[\s\S]*?`，避免跨插件误匹配
- 插件注册后自动调用 `Enable-Plugin`；缓存 list output 避免重复调用 `claude plugin list`
