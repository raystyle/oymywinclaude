set windows-shell := ["pwsh", "-NoLogo", "-NoProfileLoadTime", "-Command"]

scripts   := justfile_directory() / "scripts"
templates := justfile_directory() / "templates"

# Nerd Fonts patched Cascadia Code (CaskaydiaCove)
cascadia_font_url     := "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/CascadiaCode.zip"
cascadia_font_name    := "CascadiaCode"
cascadia_font_pattern := "CaskaydiaCove"

# Claude Code default API endpoint (ZhiPu)
cc_default_api := "https://open.bigmodel.cn/api/anthropic"

[group('default')]
default:
    @just --list

# =============================================
#  install
# =============================================

[doc('Set execution policy and unblock downloaded files (idempotent)')]
[group('config')]
unblock:
    @Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force 2>$null
    @Get-ChildItem -Path (Get-Item ".").FullName -Recurse -File -ErrorAction SilentlyContinue | Unblock-File

[doc('Install all development tools (cli + database)')]
[group('default')]
install-base:                                      (unblock) (install-fzf) (install-jq) (install-ripgrep) (install-psmux) (install-mq) (install-python) (install-node) (install-playwright) (install-font) (install-typescript-lsp) (install-markdownlint) (install-database)

[doc('Install Git for Windows (Portable, D:\\DevEnvs)')]
[group('claude-cli')]
install-git:
    @& "{{scripts}}/install-git.ps1"

[doc('Install fzf')]
[group('base')]
install-fzf:
    @& "{{scripts}}/install-tool.ps1" \
        -Repo "junegunn/fzf" \
        -ExeName "fzf.exe" \
        -ArchiveName "fzf-{version}-windows_amd64.zip" \
        -TagPrefix "v" \
        -CacheDir "fzf"

[doc('Install jq - Command-line JSON processor')]
[group('base')]
install-jq:
    @& "{{scripts}}/install-jq.ps1"

[doc('Install ripgrep - Fast text search tool')]
[group('base')]
install-ripgrep:
    @& "{{scripts}}/install-tool.ps1" \
        -Repo "BurntSushi/ripgrep" \
        -ExeName "rg.exe" \
        -ArchiveName "ripgrep-{version}-x86_64-pc-windows-msvc.zip" \
        -TagPrefix "" \
        -CacheDir "ripgrep"

[doc('Install PowerShell 7 (pwsh) from GitHub Releases MSI')]
[group('shell')]
install-powershell7:
    @& "{{scripts}}/install-powershell7.ps1"

[doc('Install PSFzf module')]
[group('shell')]
install-psfzf:
    @& "{{scripts}}/install-module.ps1" \
        -Repo "kelleyma49/PSFzf" \
        -ModuleName "PSFzf" \
        -TagPrefix "v"
    @& "{{scripts}}/profile-entry.ps1" \
        -Action add \
        -Line 'if (Get-Command fzf -ErrorAction SilentlyContinue) { Import-Module PSFzf; Set-PsFzfOption -PSReadLineChordProvider ''Ctrl+t'' -PSReadLineChordReverseHistory ''Ctrl+r'' }' \
        -Comment "PSFzf fuzzy finder"

[doc('Install PowerShell LSP module')]
[group('shell')]
install-powershell-lsp:
    @& "{{scripts}}/install-pslsp.ps1"

[doc('Install PSScriptAnalyzer from GitHub Releases')]
[group('shell')]
install-psscriptanalyzer:
    @& "{{scripts}}/install-psscriptanalyzer.ps1"

[doc('Install starship prompt')]
[group('shell')]
install-starship:
    @& "{{scripts}}/install-tool.ps1" \
        -Repo "starship/starship" \
        -ExeName "starship.exe" \
        -ArchiveName "starship-x86_64-pc-windows-msvc.zip" \
        -TagPrefix "v" \
        -CacheDir "starship"
    @& "{{scripts}}/profile-entry.ps1" \
        -Action add \
        -Line 'Invoke-Expression (&starship init powershell)' \
        -Comment "Starship prompt"
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.config\starship.toml" \
        -TemplatePath "{{templates}}/starship.toml" \
        -EditAfter $false

[doc('Install psmux terminal multiplexer')]
[group('base')]
install-psmux:
    @& "{{scripts}}/install-tool.ps1" \
        -Repo "psmux/psmux" \
        -ExeName "psmux.exe" \
        -ArchiveName "psmux-{tag}-windows-x64.zip" \
        -TagPrefix "v" \
        -CacheDir "psmux"

[doc('Install mq - Markdown query language tools')]
[group('base')]
install-mq:
    @& "{{scripts}}/install-mq.ps1"

[doc('Create VS Build Tools offline layout (~3-5 GB download)')]
[group('build')]
create-vsbuildtools-layout:
    @& "{{scripts}}/create-vsbuildtools-layout.ps1"

[doc('Install VS Build Tools (Rust MSVC deps) — requires admin')]
[group('build')]
install-vsbuildtools:
    @& "{{scripts}}/install-vsbuildtools.ps1"

[doc('Install Rust toolchain (D:\\DevEnvs)')]
[group('build')]
install-rust version="stable":
    @& "{{scripts}}/install-rust.ps1" -Version "{{version}}"

[doc('Install Python + uv (D:\\DevEnvs)')]
[group('base')]
install-python version="3.14.4":
    @& "{{scripts}}/install-python.ps1" \
        -PythonVersion "{{version}}"

[doc('Install Node.js (D:\\DevEnvs\\node)')]
[group('base')]
install-node version="24.14.1":
    @& "{{scripts}}/install-node.ps1" -Version "{{version}}"

[doc('Install Playwright CLI (@playwright/cli)')]
[group('base')]
install-playwright:
    @& "{{scripts}}/install-playwright.ps1"

[doc('Install CaskaydiaCove Nerd Font (Cascadia Code + Nerd Font icons)')]
[group('base')]
install-font:
    @& "{{scripts}}/install-font.ps1" \
        -Url "{{cascadia_font_url}}" \
        -FontName "{{cascadia_font_name}}" \
        -FilePattern "{{cascadia_font_pattern}}"

[doc('Install TypeScript LSP for Claude Code')]
[group('base')]
install-typescript-lsp:
    @& "{{scripts}}/install-typescript-lsp.ps1"

[doc('Install markdownlint-cli2 (markdownlint via npm + shim)')]
[group('base')]
install-markdownlint:
    @& "{{scripts}}/install-markdownlint.ps1"

[doc('Install Claude Code CLI (GCS distribution)')]
[group('claude-cli')]
install-claude-cli *args:
    @& "{{scripts}}/install-claude.ps1" {{args}}

[doc('Setup Claude Code API credentials (interactive)')]
[group('claude-cli')]
setup-claude *args:
    @echo ""
    @echo "🤖 Claude Code Configuration"
    @echo ""
    @& "{{scripts}}/set-claude-env.ps1" -Interactive {{args}}

[doc('Install all build tools')]
[group('default')]
install-build:                                  (create-vsbuildtools-layout) (install-vsbuildtools) (install-rust) (install-go) (install-jupyter)

[doc('Show status of all build tools')]
[group('default')]
status-build:                                   (status-vsbuildtools-layout) (status-vsbuildtools) (status-rust) (status-go) (status-jupyter)

[doc('Uninstall all build tools')]
[group('default')]
uninstall-build:                                (uninstall-vsbuildtools) (uninstall-rust) (uninstall-go) (uninstall-jupyter)

[doc('Install Claude Code and all plugins')]
[group('default')]
install-claude:                                  (install-git) (install-claude-cli) (setup-claude) (install-claude-marketplace) (install-claude-plugin) (install-playwright-skills)

[doc('Configure Claude plugins marketplace (local only, skips official marketplace)')]
[group('claude-plugin')]
install-claude-marketplace:
    @& "{{scripts}}/install-claude-marketplace.ps1"

[doc('Install jupyter-core via uv tool')]
[group('build')]
install-jupyter:
    @& "{{scripts}}/install-jupyter.ps1"

[doc('Install Go (D:\\DevEnvs\\Go)')]
[group('build')]
install-go:
    @& "{{scripts}}/install-go.ps1"

[doc('Install all database tools')]
[group('default')]
install-database:                                  (install-duckdb) (install-sqlite) (install-duckdb-extension)

[doc('Install DuckDB CLI')]
[group('database')]
install-duckdb:
    @& "{{scripts}}/install-tool.ps1" \
        -Repo "duckdb/duckdb" \
        -ExeName "duckdb.exe" \
        -ArchiveName "duckdb_cli-windows-amd64.zip" \
        -TagPrefix "v" \
        -CacheDir "duckdb"

[doc('Install SQLite CLI tools')]
[group('database')]
install-sqlite:
    @& "{{scripts}}/install-sqlite.ps1"

[doc('Install DuckDB extensions (shellfs, httpfs)')]
[group('database')]
install-duckdb-extension *args:
    @& "{{scripts}}/install-duckdb-extension.ps1" {{args}}

[doc('Install all shell tools')]
[group('default')]
install-shell:                                    (install-powershell7) (install-psfzf) (install-powershell-lsp) (install-psscriptanalyzer) (install-starship) (install-nushell)

[doc('Install Nushell')]
[group('shell')]
install-nushell *args:
    @& "{{scripts}}/install-nushell.ps1" {{ args }}

[doc('Register TypeScript LSP plugin')]
[group('claude-plugin')]
install-claude-plugin-typescript:
    @& "{{scripts}}/install-claude-plugin.ps1" typescript

[doc('Register PowerShell LSP plugin (local-dev marketplace)')]
[group('claude-plugin')]
install-claude-plugin-powershell:
    @& "{{scripts}}/install-claude-plugin.ps1" powershell

[doc('Register Astral plugin (uv, ruff, ty skills + ty LSP)')]
[group('claude-plugin')]
install-claude-plugin-astral:
    @& "{{scripts}}/install-claude-plugin.ps1" astral

[doc('Register mq-lsp plugin (mq language server)')]
[group('claude-plugin')]
install-claude-plugin-mqlsp:
    @& "{{scripts}}/install-claude-plugin.ps1" mq-lsp

[doc('Install Nushell LSP plugin for Claude Code')]
[group('claude-plugin')]
install-claude-plugin-nushell:
    @& "{{scripts}}/install-claude-plugin.ps1" nushell

[doc('Register Rust Analyzer LSP plugin (rust-analyzer)')]
[group('claude-plugin')]
install-claude-plugin-rust-analyzer:
    @& "{{scripts}}/install-claude-plugin.ps1" rust-analyzer

[doc('Register Claude Code plugin by name')]
[group('claude-plugin')]
install-claude-plugin *args:
    @& "{{scripts}}/install-claude-plugin.ps1" {{args}}

[doc('Install Playwright skills for Claude Code')]
[group('claude-plugin')]
install-playwright-skills:
    @& "{{scripts}}/install-playwright-skills.ps1"

# =============================================
#  WSL Management
# =============================================

# WSL 默认配置
wsl_base_dir := "D:/WSL"
wsl_image := "D:/WSL/ubuntu-24.04.4-wsl-amd64.wsl"
wsl_distro := "ai-linux"
wsl_user := "ray"
wsl_pass := "ubuntu"

[doc('Install default WSL environment (Ubuntu 24.04 + ai-linux)')]
[group('wsl')]
install-wsl:
    @& "{{scripts}}/install-wsl.ps1" \
        -DistroName "{{wsl_distro}}" \
        -OriginalWslFile "{{wsl_image}}" \
        -TargetDir "{{wsl_base_dir}}/{{wsl_distro}}" \
        -LinuxUser "{{wsl_user}}" \
        -LinuxPass "{{wsl_pass}}" \
        -InitScriptPath "{{scripts}}/Ubuntu-Init.sh"

# =============================================
#  uninstall
# =============================================

[doc('Uninstall all development tools (cli + database)')]
[group('default')]
uninstall-base:                                   (uninstall-fzf) (uninstall-jq) (uninstall-ripgrep) (uninstall-psmux) (uninstall-mq) (uninstall-python) (uninstall-node) (uninstall-playwright) (uninstall-font) (uninstall-typescript-lsp) (uninstall-markdownlint) (uninstall-database)

[doc('Uninstall Git for Windows')]
[group('claude-cli')]
uninstall-git:
    @& "{{scripts}}/uninstall-git.ps1"

[doc('Uninstall fzf')]
[group('base')]
uninstall-fzf:
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "fzf.exe"

[doc('Uninstall jq')]
[group('base')]
uninstall-jq:
    @& "{{scripts}}/uninstall-jq.ps1"

[doc('Uninstall ripgrep')]
[group('base')]
uninstall-ripgrep:
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "rg.exe"

[doc('Uninstall PowerShell 7 (pwsh)')]
[group('shell')]
uninstall-powershell7:
    @& "{{scripts}}/uninstall-powershell7.ps1"

[doc('Uninstall PSFzf module')]
[group('shell')]
uninstall-psfzf:
    @& "{{scripts}}/profile-entry.ps1" \
        -Action remove \
        -Line 'if (Get-Command fzf -ErrorAction SilentlyContinue) { Import-Module PSFzf; Set-PsFzfOption -PSReadLineChordProvider ''Ctrl+t'' -PSReadLineChordReverseHistory ''Ctrl+r'' }' \
        -Comment "PSFzf fuzzy finder"
    @& "{{scripts}}/uninstall-module.ps1" -ModuleName "PSFzf"

[doc('Uninstall PowerShell LSP module')]
[group('shell')]
uninstall-powershell-lsp:
    @& "{{scripts}}/uninstall-pslsp.ps1"

[doc('Uninstall PSScriptAnalyzer')]
[group('shell')]
uninstall-psscriptanalyzer:
    @& "{{scripts}}/uninstall-psscriptanalyzer.ps1"

[doc('Uninstall starship prompt')]
[group('shell')]
uninstall-starship:
    @& "{{scripts}}/profile-entry.ps1" \
        -Action remove \
        -Line 'Invoke-Expression (&starship init powershell)' \
        -Comment "Starship prompt"
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "starship.exe"

[doc('Uninstall psmux')]
[group('base')]
uninstall-psmux:
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "psmux.exe"
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "pmux.exe"
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "tmux.exe"

[doc('Uninstall mq')]
[group('base')]
uninstall-mq:
    @& "{{scripts}}/uninstall-mq.ps1" -Force

[doc('Uninstall VS Build Tools')]
[group('build')]
uninstall-vsbuildtools:
    @& "{{scripts}}/uninstall-vsbuildtools.ps1" -Force

[doc('Uninstall Rust toolchain')]
[group('build')]
uninstall-rust:
    @& "{{scripts}}/uninstall-rust.ps1"

[doc('Uninstall Python + uv')]
[group('base')]
uninstall-python:
    @& "{{scripts}}/uninstall-python.ps1"

[doc('Uninstall fnm + Node.js')]
[group('base')]
uninstall-node:
    @& "{{scripts}}/uninstall-node.ps1"

[doc('Uninstall Playwright CLI')]
[group('base')]
uninstall-playwright:
    @& "{{scripts}}/uninstall-playwright.ps1" -Force

[doc('Uninstall CaskaydiaCove Nerd Font')]
[group('base')]
uninstall-font:
    @& "{{scripts}}/uninstall-font.ps1" \
        -FontName "{{cascadia_font_name}}" \
        -FilePattern "{{cascadia_font_pattern}}"

[doc('Uninstall TypeScript LSP for Claude Code')]
[group('base')]
uninstall-typescript-lsp:
    @& "{{scripts}}/uninstall-typescript-lsp.ps1"

[doc('Uninstall markdownlint-cli2 (npm + shim)')]
[group('base')]
uninstall-markdownlint:
    @& "{{scripts}}/uninstall-markdownlint.ps1" -Force


[doc('Uninstall default WSL environment')]
[group('wsl')]
uninstall-wsl:
    @& "{{scripts}}/uninstall-wsl.ps1" -DistroName "{{wsl_distro}}" -TargetDir "{{wsl_base_dir}}/{{wsl_distro}}" -RemoveBackup

[doc('Uninstall Claude Code and all plugins')]
[group('default')]
uninstall-claude:                                (uninstall-playwright-skills) (uninstall-claude-plugin) (uninstall-claude-marketplace) (uninstall-claude-cli) (uninstall-git)

[doc('Uninstall Claude Code CLI and configuration')]
[group('claude-cli')]
uninstall-claude-cli:
    @& "{{scripts}}/uninstall-claude.ps1"

[doc('Remove official Claude plugins marketplace')]
[group('claude-plugin')]
uninstall-claude-marketplace:
    @& "{{scripts}}/uninstall-claude-marketplace.ps1"

[doc('Uninstall jupyter-core via uv tool')]
[group('build')]
uninstall-jupyter:
    @& "{{scripts}}/uninstall-jupyter.ps1"

[doc('Uninstall Go')]
[group('build')]
uninstall-go:
    @& "{{scripts}}/uninstall-go.ps1"

[doc('Uninstall all database tools')]
[group('default')]
uninstall-database:                                (uninstall-duckdb) (uninstall-sqlite) (uninstall-duckdb-extension)

[doc('Uninstall DuckDB CLI')]
[group('database')]
uninstall-duckdb:
    @& "{{scripts}}/uninstall-tool.ps1" -ExeName "duckdb.exe"

[doc('Uninstall SQLite CLI tools')]
[group('database')]
uninstall-sqlite:
    @& "{{scripts}}/uninstall-sqlite.ps1"

[doc('Uninstall DuckDB community extensions')]
[group('database')]
uninstall-duckdb-extension *args:
    @& "{{scripts}}/uninstall-duckdb-extension.ps1" {{args}}

[doc('Uninstall all shell tools')]
[group('default')]
uninstall-shell:                                  (uninstall-psfzf) (uninstall-powershell7) (uninstall-powershell-lsp) (uninstall-psscriptanalyzer) (uninstall-starship) (uninstall-nushell)

[doc('Uninstall Nushell')]
[group('shell')]
uninstall-nushell:
    @& "{{scripts}}/uninstall-nushell.ps1"

[doc('Unregister TypeScript LSP plugin')]
[group('claude-plugin')]
uninstall-claude-plugin-typescript:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" typescript

[doc('Unregister PowerShell LSP plugin + local-dev marketplace')]
[group('claude-plugin')]
uninstall-claude-plugin-powershell:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" powershell

[doc('Unregister Astral plugin')]
[group('claude-plugin')]
uninstall-claude-plugin-astral:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" astral

[doc('Unregister mq-lsp plugin')]
[group('claude-plugin')]
uninstall-claude-plugin-mqlsp:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" mq-lsp

[doc('Unregister Nushell LSP plugin')]
[group('claude-plugin')]
uninstall-claude-plugin-nushell:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" nushell

[doc('Unregister Rust Analyzer LSP plugin')]
[group('claude-plugin')]
uninstall-claude-plugin-rust-analyzer:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" rust-analyzer

[doc('Unregister Claude Code plugin by name')]
[group('claude-plugin')]
uninstall-claude-plugin *args:
    @& "{{scripts}}/uninstall-claude-plugin.ps1" {{args}}

[doc('Uninstall Playwright skills from Claude Code')]
[group('claude-plugin')]
uninstall-playwright-skills:
    @& "{{scripts}}/uninstall-playwright-skills.ps1" -Force

# =============================================
#  status
# =============================================

[doc('Show status of all development tools (cli + database)')]
[group('default')]
status-base:                                      (status-fzf) (status-jq) (status-ripgrep) (status-psmux) (status-mq) (status-python) (status-node) (status-playwright) (status-font) (status-typescript-lsp) (status-markdownlint) (status-database)

[doc('Show Git status')]
[group('claude-cli')]
status-git:
    @& "{{scripts}}/check-git.ps1"

[doc('Show fzf status')]
[group('base')]
status-fzf:
    @& "{{scripts}}/check-tool.ps1" \
        -ExeName "fzf.exe"

[doc('Show jq status')]
[group('base')]
status-jq:
    @& "{{scripts}}/check-jq.ps1"

[doc('Show ripgrep status')]
[group('base')]
status-ripgrep:
    @& "{{scripts}}/check-ripgrep.ps1"

[doc('Show PowerShell 7 status')]
[group('shell')]
status-powershell7:
    @& "{{scripts}}/check-powershell7.ps1"

[doc('Show PSFzf status')]
[group('shell')]
status-psfzf:
    @& "{{scripts}}/check-module.ps1" -ModuleName "PSFzf"

[doc('Show PowerShell LSP status')]
[group('shell')]
status-powershell-lsp:
    @& "{{scripts}}/check-pslsp.ps1"

[doc('Show PSScriptAnalyzer status')]
[group('shell')]
status-psscriptanalyzer:
    @& "{{scripts}}/check-psscriptanalyzer.ps1"

[doc('Show starship status')]
[group('shell')]
status-starship:
    @& "{{scripts}}/check-tool.ps1" \
        -ExeName "starship.exe" \
        -ProfileLine "Invoke-Expression (&starship init powershell)" \
        -ProfileLabel "Starship prompt"

[doc('Show psmux status')]
[group('base')]
status-psmux:
    @& "{{scripts}}/check-tool.ps1" \
        -ExeName "psmux.exe"

[doc('Show mq status')]
[group('base')]
status-mq:
    @& "{{scripts}}/check-mq.ps1"

[doc('Show VS Build Tools layout status')]
[group('build')]
status-vsbuildtools-layout:
    @& "{{scripts}}/check-vsbuildtools-layout.ps1"

[doc('Show VS Build Tools status')]
[group('build')]
status-vsbuildtools:
    @& "{{scripts}}/check-vsbuildtools.ps1"

[doc('Show Rust status')]
[group('build')]
status-rust:
    @& "{{scripts}}/check-rust.ps1"

[doc('Show Python + uv status')]
[group('base')]
status-python:
    @& "{{scripts}}/check-python.ps1"

[doc('Show fnm + Node.js status')]
[group('base')]
status-node:
    @& "{{scripts}}/check-node.ps1"

[doc('Show font status')]
[group('base')]
status-font:
    @& "{{scripts}}/check-font.ps1" \
        -FontName "{{cascadia_font_name}}" \
        -FilePattern "{{cascadia_font_pattern}}"

[doc('Show TypeScript LSP status')]
[group('base')]
status-typescript-lsp:
    @& "{{scripts}}/check-typescript-lsp.ps1"

[doc('Show markdownlint status')]
[group('base')]
status-markdownlint:
    @& "{{scripts}}/check-markdownlint.ps1"


[doc('Show Playwright CLI status')]
[group('base')]
status-playwright:
    @& "{{scripts}}/check-playwright.ps1"

[doc('Show WSL status')]
[group('wsl')]
status-wsl:
    @& "{{scripts}}/check-wsl.ps1" -DistroName "{{wsl_distro}}" -ExpectedUser "{{wsl_user}}"

[doc('Show jupyter-core status')]
[group('build')]
status-jupyter:
    @& "{{scripts}}/check-jupyter.ps1"

[doc('Show Go status')]
[group('build')]
status-go:
    @& "{{scripts}}/check-go.ps1"

[doc('Show status of all database tools')]
[group('default')]
status-database:                                  (status-duckdb) (status-sqlite) (status-duckdb-extension)

[doc('Show DuckDB status')]
[group('database')]
status-duckdb:
    @& "{{scripts}}/check-tool.ps1" \
        -ExeName "duckdb.exe"

[doc('Show SQLite status')]
[group('database')]
status-sqlite:
    @& "{{scripts}}/check-sqlite.ps1"

[doc('Show DuckDB extensions status')]
[group('database')]
status-duckdb-extension:
    @& "{{scripts}}/check-duckdb-extension.ps1"

[doc('Show status of all shell tools')]
[group('default')]
status-shell:                                     (status-powershell7) (status-psfzf) (status-powershell-lsp) (status-psscriptanalyzer) (status-starship) (status-nushell)

[doc('Show Nushell status + registered plugins')]
[group('shell')]
status-nushell:
    @& "{{scripts}}/check-nushell.ps1"

[doc('Show Claude Code status')]
[group('default')]
status-claude:                                    (status-git) (status-claude-cli) (status-claude-marketplace) (status-playwright-skills)

[doc('Show Claude Code CLI status')]
[group('claude-cli')]
status-claude-cli:
    @& "{{scripts}}/check-claude.ps1"

[doc('Show official Claude plugins marketplace status')]
[group('claude-plugin')]
status-claude-marketplace:
    @& "{{scripts}}/check-claude-marketplace.ps1"

[doc('Show Playwright skills status')]
[group('claude-plugin')]
status-playwright-skills:
    @& "{{scripts}}/check-playwright-skills.ps1"

[doc('Show Claude Code plugin status')]
[group('claude-plugin')]
status-claude-plugin *args:
    @& "{{scripts}}/check-claude-plugin.ps1" {{args}}

[doc('Show TypeScript LSP plugin status')]
[group('claude-plugin')]
status-claude-plugin-typescript:
    @& "{{scripts}}/check-claude-plugin.ps1" typescript

[doc('Show PowerShell LSP plugin status')]
[group('claude-plugin')]
status-claude-plugin-powershell:
    @& "{{scripts}}/check-claude-plugin.ps1" powershell

[doc('Show Astral plugin status')]
[group('claude-plugin')]
status-claude-plugin-astral:
    @& "{{scripts}}/check-claude-plugin.ps1" astral

[doc('Show mq-lsp plugin status')]
[group('claude-plugin')]
status-claude-plugin-mqlsp:
    @& "{{scripts}}/check-claude-plugin.ps1" mq-lsp

[doc('Check Nushell LSP plugin status')]
[group('claude-plugin')]
status-claude-plugin-nushell:
    @& "{{scripts}}/check-claude-plugin.ps1" nushell

[doc('Check Rust Analyzer LSP plugin status')]
[group('claude-plugin')]
status-claude-plugin-rust-analyzer:
    @& "{{scripts}}/check-claude-plugin.ps1" rust-analyzer

# =============================================
#  config
# =============================================

[doc('Reset starship config (force overwrite from template)')]
[group('config')]
config-starship:
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.config\starship.toml" \
        -TemplatePath "{{templates}}/starship.toml"

[doc('Reset psmux config (force overwrite from template)')]
[group('config')]
config-psmux:
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.config\psmux\psmux.conf" \
        -TemplatePath "{{templates}}/psmux.conf"

[doc('Deploy markdownlint-cli2 config to user home')]
[group('config')]
config-markdownlint:
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.markdownlint-cli2.jsonc" \
        -TemplatePath "{{templates}}/markdownlint-cli2.jsonc"

[doc('Add convenience aliases to PS5 + PS7 profiles')]
[group('config')]
config-alias:
    @Write-Host "[INFO] No aliases configured" -ForegroundColor Cyan

[doc('Configure VS Code to use CaskaydiaCove Nerd Font')]
[group('config')]
config-vscode-font:
    @& "{{scripts}}/config-vscode-font.ps1"

[doc('Run all tests (structure + lint + status)')]
[group('dev')]
test: (test-structure) (test-lint) (test-status)

[doc('Validate script structure (headers, pairing, conventions)')]
[group('dev')]
test-structure:
    @& "{{scripts}}/test-structure.ps1"

[doc('Run PSScriptAnalyzer lint on all scripts')]
[group('dev')]
test-lint:
    @& "{{scripts}}/test-lint.ps1"

[doc('Run all status checks (base + build + claude + wsl)')]
[group('dev')]
test-status: (status-base) (status-build) (status-claude) (status-wsl)

[doc('Lock tool version (prevent upgrades)')]
[group('config')]
lock *args:
    @& "{{scripts}}/lock-version.ps1" {{args}}

[doc('Unlock tool version (allow upgrades)')]
[group('config')]
unlock *args:
    @& "{{scripts}}/lock-version.ps1" -Remove {{args}}

[doc('Show all version locks')]
[group('config')]
lock-status:
    @& "{{scripts}}/check-lock.ps1"

[doc('Deploy Claude Code config (deep merge from template) and hooks')]
[group('config')]
config-claude:
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.claude\settings.json" \
        -TemplatePath "{{templates}}/claude-settings.json" \
        -Merge
    @& "{{scripts}}/ensure-config.ps1" \
        -Path "$env:USERPROFILE\.claude\hooks\fix-bash.py" \
        -TemplatePath "{{templates}}/hooks\fix-bash.py" \
        -EditAfter:$false
    @Write-Host "[INFO] Hooks deployed:" -ForegroundColor Cyan
    @Write-Host "  PreToolUse   fix-bash.py" -ForegroundColor DarkGray

