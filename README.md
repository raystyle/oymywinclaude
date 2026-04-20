# Oh My WinClaude

Windows 开发环境一键配置工具。基于 [just](https://github.com/casey/just)
任务 runner，通过幂等 PowerShell 脚本管理开发工具的安装、更新和卸载。

## 功能特性

- **幂等安装** — 所有脚本可安全重复执行，已安装的工具自动跳过
- **离线缓存** — 下载文件缓存在本地，支持 SHA256 完整性校验
- **中国网络友好** — 直连失败自动切换 gh-proxy.org 镜像
- **统一输出** — `[OK]` / `[INFO]` / `[WARN]` / `[ERROR]` 彩色标签
- **版本管理** — 自动检测新版本，支持升级与失败回滚
- **版本锁定** — `just lock` 锁定工具版本，阻止自动升级
- **测试框架** — 结构检查 + PSScriptAnalyzer Lint + 状态检查
- **模块化** — 每个工具独立脚本，可单独调用或组合执行

## 快速开始

```powershell
# 1. 安装 just（任务运行器）
.\justinit.ps1

# 2. 安装所有开发工具（CLI + 构建 + 数据库 + Shell）
just install-base

# 3. 安装 Claude Code + 插件
just install-claude

# 4. 检查安装状态
just status-base
```

> **浏览器下载说明**：通过浏览器下载 zip 解压的项目，Windows 会标记文件
> "来自互联网"，导致 PowerShell 拒绝执行脚本。
> `just install-all` 首次运行时会自动执行 `just unblock`，
> 设置 `RemoteSigned` 执行策略并解除所有文件的下载标记。
> `git clone` 克隆的项目无需此步骤。

## 前置要求

- Windows 10/11（64 位）
- PowerShell 5.1+（系统自带）
- 管理员权限（安装 VS Build Tools 时需要）

## 工具分类

| 类别       | 工具                                                |
| ---------- | --------------------------------------------------- |
| CLI 工具   | fzf, jq, ripgrep, mq, mq-crawl, mq-check, markdownlint |
| Shell      | PowerShell 7 (pwsh), Nushell                        |
| Shell 增强 | PSFzf, starship, psmux, CaskaydiaCove Nerd Font     |
| 编程语言   | Rust, Python + uv, Node.js, Go                      |
| 数据库     | DuckDB, SQLite                                      |
| 构建工具   | VS Build Tools (MSVC)                               |
| 语言服务   | ty (Astral), TypeScript LSP, PowerShell LSP, mq-lsp |
| 代码分析   | PSScriptAnalyzer, ruff (Astral), markdownlint       |
| Claude Code | Git, CLI, 插件, MCP, Playwright 技能               |
| 数据科学   | jupyter-core + jupyter-mcp (via uv)                 |
| WSL        | Ubuntu 24.04 (distro: ai-linux, `D:\WSL`)          |

## 常用命令

```bash
# 聚合命令
just install-base            # 安装所有开发工具
just install-cli             # 安装 CLI 工具
just install-build           # 安装构建工具
just install-shell           # 安装 Shell 工具
just install-claude          # 安装 Claude Code + 插件 + Playwright
just install-wsl             # 安装 WSL（需先下载镜像到 D:\WSL）
just uninstall-base          # 卸载所有开发工具
just status-base             # 检查所有开发工具状态
just test                    # 运行全部测试

# Claude Code 配置
just setup-claude <key>     # 配置 API 密钥
just config-claude          # 从模板更新 Claude Code 配置（深度合并）

# 其他配置
just config-starship        # 重置 starship 提示符配置
just config-psmux           # 重置 psmux 配置
just config-alias           # 添加便捷别名（jy = jupyter lab）
just config-vscode-font     # 配置 VS Code 使用 CaskaydiaCove Nerd Font
just config-markdownlint    # 部署 markdownlint 用户级配置
just unblock                # 手动解除安全限制（浏览器下载时）

# 版本锁定
just lock <tool> [version]  # 锁定工具版本
just unlock <tool>          # 解除版本锁定
just lock-status            # 查看所有锁定
```

## Claude Code 安装

Claude Code 相关命令分三层：

| 层级     | 职责                                   | 命令示例                         |
| -------- | -------------------------------------- | -------------------------------- |
| 二进制   | Git、Claude CLI 安装/卸载，API 密钥    | `install-git`, `install-claude-cli` |
| 插件     | 市场注册、LSP 插件、Playwright 技能    | `install-claude-marketplace`     |
| 聚合     | 一键安装全部                          | `install-claude`, `uninstall-claude` |

`just install-claude` 按顺序执行：
Git → Claude CLI → 市场注册 → 插件 → Playwright 技能 → 配置深度合并。
`just uninstall-claude` 按顺序执行：
Playwright 技能 → 插件 → 市场 → Claude CLI → Git。

### LSP 插件（本地市场）

| 插件                        | 说明                                         |
| --------------------------- | -------------------------------------------- |
| `typescript-lsp@local-dev`  | TypeScript LSP（跳转定义、引用查找、补全等） |
| `powershell-lsp@local-dev`  | PowerShell LSP（跳转定义、引用查找、补全等） |
| `astral@local-dev`          | Python 技能（uv, ruff, ty）+ ty LSP          |
| `mq-lsp@local-dev`          | mq 语言服务器（补全、悬停、定义跳转等） |
| `nushell-lsp@local-dev`     | Nushell LSP（`nu --lsp`，补全、悬停、定义跳转等） |
| `skill-creator@local-dev`   | 技能创建工具（创建、测试和改进 Claude 技能） |

### MCP 服务

| 服务    | 说明                                               |
| ------- | -------------------------------------------------- |
| jupyter | Jupyter MCP 服务（通过 `jupyter-mcp-server` 启动） |
| nushell | Nushell MCP 服务（`nu --mcp`）                     |

### Playwright 技能

通过 `playwright-cli install --skills` 注册，提供浏览器自动化能力。

## 安装路径

| 用途        | 路径                                                  |
| ----------- | ----------------------------------------------------- |
| 便携式 CLI  | `%USERPROFILE%\.local\bin`（含 npm 工具 shim）       |
| PowerShell 7 | `%ProgramFiles%\PowerShell\7\`                       |
| 开发环境    | `D:\DevEnvs\`（Git, Rust, Python, Node.js, Go, VSBT）|
| 下载缓存    | `D:\DevSetup\`                                        |
| 版本锁定    | `D:\DevSetup\version-lock.json`                       |
| VS BT 缓存  | `C:\VSBuildToolsCache`                                |
| WSL 发行版  | `D:\WSL\ai-linux\`                                    |

## WSL 安装说明

WSL 不包含在聚合安装命令中，需手动准备：

1. 下载 Ubuntu 24.04 WSL 镜像到 `D:\WSL\ubuntu-24.04.4-wsl-amd64.wsl`
2. 运行 `just install-wsl`

## 许可证

MIT
