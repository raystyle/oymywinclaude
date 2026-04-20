#!/usr/bin/env bash
# =============================================================================
# Ubuntu 自动初始化脚本 v5.5
# =============================================================================
# 功能：在 Ubuntu（中国大陆网络环境）下一键搭建 AI 编程及运行时环境
#   - 更新 Ubuntu 软件源（清华 TUNA）
#   - Python3（系统内置）+ pip（apt 安装）+ uv（pipx 安装）
#   - Node.js LTS（via fnm）+ npm
#   - Rust stable（via rustup）+ Cargo
#
# 设计原则：
#   1. 幂等性：每一步操作前检查是否已完成，重复运行不产生副作用。
#   2. Shell 无关：所有镜像源均写入各工具的原生配置文件，不依赖 Shell 环境变量，
#      确保在 bash / zsh / fish 等任意 Shell 下开箱即用。
#
#   配置文件对应关系（均经官方文档核查）：
#     pip    → ~/.config/pip/pip.conf
#              来源: https://pip.pypa.io/en/stable/topics/configuration/
#
#     uv     → ~/.config/uv/uv.toml
#              来源: https://docs.astral.sh/uv/reference/settings/#index
#              来源: https://docs.astral.sh/uv/reference/settings/#python-install-mirror
#
#     npm    → ~/.npmrc
#              来源: https://docs.npmjs.com/cli/v11/configuring-npm/npmrc
#
#     Cargo  → ~/.cargo/config.toml
#              来源: https://doc.rust-lang.org/cargo/reference/config.html
#              来源: https://doc.rust-lang.org/cargo/reference/source-replacement.html
#              来源: https://rsproxy.cn/
#
#     rustup → RUSTUP_DIST_SERVER / RUSTUP_UPDATE_ROOT 仅为环境变量，
#              无官方配置文件支持；安装时内联传入，日后更新通过
#              Shell RC 中 export 持久化（rustup 的设计局限）。
#              来源: https://rust-lang.github.io/rustup/environment-variables.html
#              来源: https://rsproxy.cn/
#
#     fnm    → fnm 不支持配置文件设置 node-dist-mirror，
#              安装 Node.js 时通过 --node-dist-mirror 命令行参数指定。
#              fnm PATH 初始化必须写入 Shell RC。
#              来源: https://github.com/Schniz/fnm/blob/master/docs/configuration.md
#              来源: https://github.com/Schniz/fnm (README Shell Setup 章节)
#
# 用法：
#   bash Ubuntu-Init.sh               # 安装（幂等，可重复运行）
#   bash Ubuntu-Init.sh --uninstall   # 卸载
#   bash Ubuntu-Init.sh --uninstall --force  # 强制卸载（跳过确认）
# =============================================================================

set -euo pipefail

# ============================================================
# 参数解析
# ============================================================
UNINSTALL=0
FORCE=0

for arg in "$@"; do
    case "$arg" in
        --uninstall|-u) UNINSTALL=1 ;;
        --force|-f)     FORCE=1 ;;
        *)
            echo "[ERROR] 未知参数: $arg"
            echo "用法: bash $0 [--uninstall] [--force]"
            exit 1
            ;;
    esac
done

# ============================================================
# 辅助函数
# ============================================================
print_step() {
    local line="============================================================"
    echo -e "\n\033[1;36m${line}\033[0m"
    echo -e "\033[1;36m  $1\033[0m"
    echo -e "\033[1;36m${line}\033[0m"
}
print_info() { echo -e "  \033[1;32m[INFO]\033[0m $1"; }
print_warn() { echo -e "  \033[1;33m[WARN]\033[0m $1"; }
print_skip() { echo -e "  \033[1;34m[SKIP]\033[0m $1"; }

# 检测 Ubuntu 版本代号
detect_codename() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -cs
    elif [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${VERSION_CODENAME:-jammy}"
    else
        echo "jammy"
    fi
}

# 检测 Ubuntu 主版本号
detect_version_id() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "${VERSION_ID:-22.04}"
    else
        echo "22.04"
    fi
}

# 检查 apt 包是否已安装
is_pkg_installed() {
    dpkg -s "$1" &>/dev/null
}

# 检查配置文件是否已包含标记
is_config_current() {
    local file="$1"
    [ -f "$file" ] && grep -q "Ubuntu-Init.sh" "$file"
}

# ────────────────────────────────────────────────────────────
# get_github_release — 获取 GitHub Release 对象（JSON）
# ────────────────────────────────────────────────────────────
#   用法: get_github_release "owner/repo" ["tag"]
#   - 省略 tag 则获取 latest
#   - 支持 GITHUB_TOKEN 环境变量（避免 API 限流）
#   - 三级降级：API 直连 → gh-proxy 代理 → 失败报错
#   返回: 完整 release JSON（通过 stdout）
# ────────────────────────────────────────────────────────────
get_github_release() {
    local repo="$1"
    local tag="${2:-}"
    local api_base="https://api.github.com/repos/${repo}/releases"
    local url

    if [ -n "$tag" ]; then
        url="${api_base}/tags/${tag}"
    else
        url="${api_base}/latest"
    fi

    local -a curl_opts=(
        -fsSL --retry 2 --connect-timeout 10
        -H "Accept: application/vnd.github+json"
        -H "User-Agent: ubuntu-init-installer"
    )
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_opts+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi

    local response=""

    # 尝试 1: API 直连
    if response=$(curl "${curl_opts[@]}" "$url" 2>/dev/null) && [ -n "$response" ]; then
        print_info "GitHub API 直连成功"
        echo "$response"
        return 0
    fi

    # 尝试 2: gh-proxy 代理
    local proxy_url="https://gh-proxy.org/${url}"
    if response=$(curl "${curl_opts[@]}" "$proxy_url" 2>/dev/null) && [ -n "$response" ]; then
        print_info "GitHub API 通过 gh-proxy 代理获取成功"
        echo "$response"
        return 0
    fi

    # 全部失败
    print_warn "无法获取 GitHub Release: ${repo} (tag=${tag:-latest})"
    return 1
}

# ────────────────────────────────────────────────────────────
# download_with_proxy — 带 gh-proxy 降级的下载函数
# ────────────────────────────────────────────────────────────
#   用法: download_with_proxy "github_url" "output_path"
# ────────────────────────────────────────────────────────────
download_with_proxy() {
    local github_url="$1"
    local output="$2"
    local proxy_url="https://gh-proxy.org/${github_url}"

    if curl -fL --retry 2 --connect-timeout 15 "$proxy_url" -o "$output" 2>/dev/null; then
        print_info "下载成功（gh-proxy 代理）"
        return 0
    fi

    print_warn "gh-proxy 下载失败，尝试直连 GitHub..."
    if curl -fL --retry 3 --connect-timeout 30 "$github_url" -o "$output"; then
        print_info "下载成功（GitHub 直连）"
        return 0
    fi

    return 1
}

# ────────────────────────────────────────────────────────────
# verify_sha256 — SHA256 完整性校验
# ────────────────────────────────────────────────────────────
#   用法: verify_sha256 "file_path" "expected_hash"
#   expected_hash 为空则跳过校验
# ────────────────────────────────────────────────────────────
verify_sha256() {
    local file="$1"
    local expected="$2"

    if [ -z "$expected" ]; then
        print_warn "无 SHA256 校验值可用，跳过校验"
        return 0
    fi

    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')

    if [ "$actual" = "$expected" ]; then
        print_info "SHA256 校验通过 ✅ ($actual)"
        return 0
    else
        echo "[ERROR] SHA256 校验失败！"
        echo "  期望: $expected"
        echo "  实际: $actual"
        echo "  文件可能被篡改，终止安装。"
        rm -f "$file"
        return 1
    fi
}

# ============================================================
# 卸载逻辑
# ============================================================
if [ "$UNINSTALL" -eq 1 ]; then
    print_step "环境卸载"

    if [ "$FORCE" -eq 0 ]; then
        echo ""
        read -rp "  确认卸载所有配置？输入 YES 继续: " confirm
        if [ "$confirm" != "YES" ]; then
            print_info "已取消卸载。"
            exit 0
        fi
    fi

    # 卸载 uv（pipx 安装的）
    if command -v pipx &>/dev/null && pipx list 2>/dev/null | grep -q uv; then
        print_info "正在卸载 uv (pipx)..."
        pipx uninstall uv
    fi

    # 卸载 rustup
    # 来源: https://rust-lang.github.io/rustup/installation/other.html
    if command -v rustup &>/dev/null; then
        print_info "正在卸载 Rust / rustup..."
        rustup self uninstall -y
    fi

    # 卸载 fnm
    # 来源: https://github.com/Schniz/fnm README "Removing" 章节
    for fnm_dir in "$HOME/.local/share/fnm" "$HOME/.fnm"; do
        if [ -d "$fnm_dir" ]; then
            print_info "正在删除 fnm: $fnm_dir"
            rm -rf "$fnm_dir"
        fi
    done

    # 清理各工具配置文件
    [ -f "$HOME/.config/pip/pip.conf" ] && rm -f "$HOME/.config/pip/pip.conf" && print_info "已删除 pip 配置"
    [ -f "$HOME/.config/uv/uv.toml" ]  && rm -f "$HOME/.config/uv/uv.toml"  && print_info "已删除 uv 配置"
    [ -f "$HOME/.cargo/config.toml" ]  && rm -f "$HOME/.cargo/config.toml"  && print_info "已删除 Cargo 配置"

    # 清理 npm 镜像行（仅删除本脚本写入的 registry 行）
    if [ -f "$HOME/.npmrc" ]; then
        sed -i '/^registry=https:\/\/registry\.npmmirror\.com\//d' "$HOME/.npmrc"
        print_info "已清理 npm 镜像配置"
    fi

    # 清理 bash / zsh 中的 fnm 和 Rust 初始化块
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$rc" ]; then
            if grep -q "Ubuntu-Init fnm" "$rc"; then
                sed -i '/# --- Ubuntu-Init fnm ---/,/# --- end Ubuntu-Init fnm ---/d' "$rc"
                print_info "已清理 $rc 中的 fnm 配置"
            fi
            if grep -q "Ubuntu-Init Rust" "$rc"; then
                sed -i '/# --- Ubuntu-Init Rust ---/,/# --- end Ubuntu-Init Rust ---/d' "$rc"
                print_info "已清理 $rc 中的 Rust 配置"
            fi
        fi
    done

    # 清理 fish 配置
    for fish_file in "$HOME/.config/fish/conf.d/fnm.fish" "$HOME/.config/fish/conf.d/cargo.fish"; do
        if [ -f "$fish_file" ]; then
            rm -f "$fish_file"
            print_info "已删除 $fish_file"
        fi
    done

    # 还原 APT 源
    if [ -f /etc/apt/sources.list.bak ]; then
        sudo cp /etc/apt/sources.list.bak /etc/apt/sources.list
        sudo rm -f /etc/apt/sources.list.bak
        print_info "已还原 /etc/apt/sources.list"
    fi
    if [ -f /etc/apt/sources.list.d/ubuntu.sources.bak ]; then
        sudo cp /etc/apt/sources.list.d/ubuntu.sources.bak /etc/apt/sources.list.d/ubuntu.sources
        sudo rm -f /etc/apt/sources.list.d/ubuntu.sources.bak
        print_info "已还原 /etc/apt/sources.list.d/ubuntu.sources"
    fi

    echo ""
    echo -e "\033[1;32m  ✅ 环境卸载完成。请重启终端使变更生效。\033[0m"
    exit 0
fi

# ============================================================
# 检查 sudo 权限
# ============================================================
if [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo "  此脚本需要 sudo 权限，请输入密码："
    sudo true
fi

echo ""
echo "============================================================"
echo "  Ubuntu 初始化脚本 v5.5（幂等模式）"
echo "  开始时间: $(date)"
echo "============================================================"

# ============================================================
# 步骤 0: 配置中文 locale 并更新 Ubuntu 软件源
# ============================================================
print_step "步骤 0/4: 配置中文 locale 并更新 Ubuntu 软件源"

export DEBIAN_FRONTEND=noninteractive

CODENAME=$(detect_codename)
VERSION_ID=$(detect_version_id)
MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
print_info "检测到 Ubuntu 版本: $VERSION_ID ($CODENAME)"

# --- 配置中文 locale（幂等：检查是否已生成）---
if ! locale -a | grep -q "zh_CN.utf8"; then
    print_info "正在配置中文 locale (zh_CN.UTF-8)..."
    sudo sed -i 's/^# *zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen zh_CN.UTF-8
    sudo update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    print_info "中文 locale 已生成"
else
    print_skip "中文 locale 已存在，跳过"
fi

# --- APT 源配置（幂等：检查是否已是 TUNA 源）---
APT_NEEDS_UPDATE=0

if [ "$MAJOR_VERSION" -ge 24 ] && [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    # Ubuntu 24.04+ DEB822 格式
    if grep -q "mirrors.tuna.tsinghua.edu.cn" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
        print_skip "APT 源已是清华 TUNA 镜像 (DEB822)，跳过"
    else
        if [ ! -f /etc/apt/sources.list.d/ubuntu.sources.bak ]; then
            sudo cp /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
            print_info "已备份原始 ubuntu.sources → ubuntu.sources.bak"
        fi
        sudo tee /etc/apt/sources.list.d/ubuntu.sources > /dev/null << EOF
# Ubuntu ${CODENAME} - 清华 TUNA 镜像源 (DEB822 格式)
# 由 Ubuntu-Init.sh 生成于 $(date)
# 来源: https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu/

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/ubuntu/
Suites: ${CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        print_info "Ubuntu 软件源已替换为清华 TUNA 镜像 (DEB822 格式)"
        APT_NEEDS_UPDATE=1
    fi
else
    # Ubuntu 22.04 及更早：传统 sources.list 格式
    if grep -q "mirrors.tuna.tsinghua.edu.cn" /etc/apt/sources.list 2>/dev/null; then
        print_skip "APT 源已是清华 TUNA 镜像，跳过"
    else
        if [ ! -f /etc/apt/sources.list.bak ]; then
            sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
            print_info "已备份原始 sources.list → /etc/apt/sources.list.bak"
        fi
        sudo tee /etc/apt/sources.list > /dev/null << EOF
# Ubuntu ${CODENAME} - 清华 TUNA 镜像源
# 由 Ubuntu-Init.sh 生成于 $(date)
# 来源: https://mirrors.tuna.tsinghua.edu.cn/help/ubuntu/
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${CODENAME} main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${CODENAME}-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${CODENAME}-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${CODENAME}-security main restricted universe multiverse
EOF
        print_info "Ubuntu 软件源已替换为清华 TUNA 镜像 (传统格式)"
        APT_NEEDS_UPDATE=1
    fi
fi

# --- 基础依赖安装（幂等：逐个检查）---
BASE_PKGS=(curl wget git unzip ca-certificates build-essential libssl-dev)
MISSING_PKGS=()
for pkg in "${BASE_PKGS[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ "$APT_NEEDS_UPDATE" -eq 1 ] || [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    sudo apt-get update -y
fi

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
    print_info "正在安装缺失的基础依赖: ${MISSING_PKGS[*]}"
    sudo apt-get install -y "${MISSING_PKGS[@]}"
else
    print_skip "基础依赖已全部安装，跳过"
fi

# ============================================================
# 步骤 1: 安装 Python3 + pip + uv
# ============================================================
print_step "步骤 1/4: 安装 Python3 / pip / uv"

# 1-a. pip 和 pipx（apt 安装）
PY_PKGS=(python3-pip pipx)
PY_MISSING=()
for pkg in "${PY_PKGS[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        PY_MISSING+=("$pkg")
    fi
done

if [ "${#PY_MISSING[@]}" -gt 0 ]; then
    print_info "正在安装: ${PY_MISSING[*]}"
    sudo apt-get install -y "${PY_MISSING[@]}"
    pipx ensurepath
else
    print_skip "python3-pip 和 pipx 已安装，跳过"
fi
print_info "Python3: $(python3 --version)"
print_info "pip3:    $(pip3 --version)"

# 1-b. pip 镜像 → ~/.config/pip/pip.conf
#   来源: https://pip.pypa.io/en/stable/topics/configuration/
if is_config_current "$HOME/.config/pip/pip.conf"; then
    print_skip "pip 镜像配置已存在，跳过"
else
    mkdir -p "$HOME/.config/pip"
    cat > "$HOME/.config/pip/pip.conf" << 'EOF'
# pip 用户级配置 - 由 Ubuntu-Init.sh 生成
# 来源: https://pip.pypa.io/en/stable/topics/configuration/

[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
    print_info "pip 镜像已写入 ~/.config/pip/pip.conf"
fi

# 1-c. 安装 uv（通过 pipx，隔离环境）
#   来源: https://docs.astral.sh/uv/getting-started/installation/
if command -v uv &>/dev/null; then
    print_skip "uv 已安装: $(uv --version)，跳过"
else
    print_info "正在通过 pipx 安装 uv..."
    pipx install uv
    print_info "uv: $(uv --version)"
fi

# 1-d. uv 镜像 → ~/.config/uv/uv.toml
#   来源: https://docs.astral.sh/uv/concepts/configuration-files/
#   来源: https://docs.astral.sh/uv/reference/settings/#index
if is_config_current "$HOME/.config/uv/uv.toml"; then
    print_skip "uv 镜像配置已存在，跳过"
else
    mkdir -p "$HOME/.config/uv"
    cat > "$HOME/.config/uv/uv.toml" << 'EOF'
# uv 用户级配置 - 由 Ubuntu-Init.sh 生成
# 来源: https://docs.astral.sh/uv/concepts/configuration-files/
# 来源: https://docs.astral.sh/uv/reference/settings/

[[index]]
name = "tuna"
url = "https://pypi.tuna.tsinghua.edu.cn/simple"
default = true

# 来源: https://docs.astral.sh/uv/reference/settings/#python-install-mirror
python-install-mirror = "https://mirror.nju.edu.cn/github-release/astral-sh/python-build-standalone/"
EOF
    print_info "uv 镜像已写入 ~/.config/uv/uv.toml"
fi

# ============================================================
# 步骤 2: 安装 Node.js（fnm + npmmirror）
# ============================================================
print_step "步骤 2/4: 安装 Node.js (fnm + npmmirror)"

FNM_INSTALL_DIR="$HOME/.local/share/fnm"

# 2-a. 下载 fnm 二进制
#   来源: https://github.com/Schniz/fnm README Installation 章节
#   通过 GitHub Releases API 获取版本信息和 SHA256 digest
if [ -f "$FNM_INSTALL_DIR/fnm" ]; then
    print_skip "fnm 已存在，跳过下载"
else
    mkdir -p "$FNM_INSTALL_DIR"
    FNM_ZIP="/tmp/fnm-linux.zip"
    FNM_ASSET_NAME="fnm-linux.zip"

    # ── 通过 API 获取 release 信息 ──
    print_info "正在通过 GitHub API 获取 fnm 最新版本..."
    FNM_RELEASE_JSON=""
    FNM_DOWNLOAD_URL=""
    FNM_EXPECTED_SHA256=""

    if FNM_RELEASE_JSON=$(get_github_release "Schniz/fnm"); then
        FNM_TAG=$(echo "$FNM_RELEASE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('tag_name', ''))" 2>/dev/null)
        print_info "fnm 最新版本: ${FNM_TAG:-unknown}"

        # 从 assets 中提取下载 URL 和 SHA256 digest
        read -r FNM_DOWNLOAD_URL FNM_EXPECTED_SHA256 < <(echo "$FNM_RELEASE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for asset in data.get('assets', []):
    if asset['name'] == '${FNM_ASSET_NAME}':
        url = asset.get('browser_download_url', '')
        digest = asset.get('digest', '') or ''
        sha = digest.split(':', 1)[1] if digest.startswith('sha256:') else ''
        print(url, sha)
        sys.exit(0)
print('', '')
" 2>/dev/null)
    fi

    # ── 下载 ──
    if [ -n "$FNM_DOWNLOAD_URL" ]; then
        print_info "正在下载 fnm: $FNM_DOWNLOAD_URL"
        download_with_proxy "$FNM_DOWNLOAD_URL" "$FNM_ZIP"
    else
        # API 失败时的 fallback：使用 /latest/download/ 固定路径
        print_warn "API 获取失败，使用 fallback 下载路径"
        FNM_FALLBACK_URL="https://github.com/Schniz/fnm/releases/latest/download/${FNM_ASSET_NAME}"
        download_with_proxy "$FNM_FALLBACK_URL" "$FNM_ZIP"
    fi

    # ── SHA256 校验 ──
    verify_sha256 "$FNM_ZIP" "${FNM_EXPECTED_SHA256:-}"

    unzip -o "$FNM_ZIP" -d "$FNM_INSTALL_DIR"
    chmod +x "$FNM_INSTALL_DIR/fnm"
    rm -f "$FNM_ZIP"
    print_info "fnm 已安装至 $FNM_INSTALL_DIR/fnm"
fi

# 2-b. 安装 Node.js LTS
#   来源: https://github.com/Schniz/fnm/blob/master/docs/configuration.md
if "$FNM_INSTALL_DIR/fnm" list 2>/dev/null | grep -q "lts-latest"; then
    print_skip "Node.js LTS 已安装，跳过"
else
    print_info "正在安装 Node.js LTS（npmmirror 加速）..."
    "$FNM_INSTALL_DIR/fnm" install --lts \
        --node-dist-mirror "https://npmmirror.com/mirrors/node/"
    "$FNM_INSTALL_DIR/fnm" default lts-latest
fi

# 临时激活 fnm 环境
eval "$("$FNM_INSTALL_DIR/fnm" env)"
print_info "Node.js: $(node --version)"

# 2-c. npm 镜像 → ~/.npmrc
#   来源: https://docs.npmjs.com/cli/v11/configuring-npm/npmrc
if grep -q "registry=https://registry.npmmirror.com/" "$HOME/.npmrc" 2>/dev/null; then
    print_skip "npm 镜像已配置，跳过"
else
    npm config set registry https://registry.npmmirror.com/
    print_info "npm 镜像已写入 ~/.npmrc"
fi
print_info "npm: $(npm --version)"

# 2-d. fnm PATH 初始化写入 Shell RC
#   来源: https://github.com/Schniz/fnm README Shell Setup 章节

# bash
[ -f "$HOME/.bashrc" ] || touch "$HOME/.bashrc"
if grep -q "Ubuntu-Init fnm" "$HOME/.bashrc"; then
    print_skip "fnm 初始化已存在于 ~/.bashrc，跳过"
else
    cat >> "$HOME/.bashrc" << 'BASHEOF'

# --- Ubuntu-Init fnm ---
# 来源: https://github.com/Schniz/fnm README Shell Setup - Bash
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell bash)"
# --- end Ubuntu-Init fnm ---
BASHEOF
    print_info "fnm 初始化已写入 ~/.bashrc"
fi

# zsh（仅在文件已存在时写入）
if [ -f "$HOME/.zshrc" ]; then
    if grep -q "Ubuntu-Init fnm" "$HOME/.zshrc"; then
        print_skip "fnm 初始化已存在于 ~/.zshrc，跳过"
    else
        cat >> "$HOME/.zshrc" << 'ZSHEOF'

# --- Ubuntu-Init fnm ---
# 来源: https://github.com/Schniz/fnm README Shell Setup - Zsh
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd --shell zsh)"
# --- end Ubuntu-Init fnm ---
ZSHEOF
        print_info "fnm 初始化已写入 ~/.zshrc"
    fi
fi

# fish
FISH_CONF_D="$HOME/.config/fish/conf.d"
FISH_FNM_FILE="$FISH_CONF_D/fnm.fish"
if [ -d "$(dirname "$FISH_CONF_D")" ]; then
    mkdir -p "$FISH_CONF_D"
    if [ -f "$FISH_FNM_FILE" ]; then
        print_skip "$FISH_FNM_FILE 已存在，跳过"
    else
        cat > "$FISH_FNM_FILE" << 'FISHEOF'
# Ubuntu-Init fnm - 由 Ubuntu-Init.sh 生成
# 来源: https://github.com/Schniz/fnm README Shell Setup - Fish shell
fish_add_path "$HOME/.local/share/fnm"
fnm env --use-on-cd --shell fish | source
FISHEOF
        print_info "fnm 初始化已写入 $FISH_FNM_FILE"
    fi
fi

# ============================================================
# 步骤 3: 安装 Rust（rustup + rsproxy.cn 字节跳动镜像）
# ============================================================
print_step "步骤 3/4: 安装 Rust (rustup + rsproxy.cn)"

# 3-a. 安装 rustup + Rust stable
#   来源: https://rsproxy.cn/
if command -v rustc &>/dev/null; then
    print_skip "Rust 已安装: $(rustc --version)，跳过"
else
    print_info "正在从 rsproxy.cn 安装 rustup..."

    # 先设置环境变量，rustup-init.sh 会读取
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"

    curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh \
        | sh -s -- -y --no-modify-path \
            --default-toolchain stable \
            --profile default
fi

# 加载 Cargo 环境
# shellcheck source=/dev/null
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
print_info "rustc:  $(rustc --version)"
print_info "cargo:  $(cargo --version)"

# 3-b. Cargo 镜像 → ~/.cargo/config.toml
#   来源: https://rsproxy.cn/
#   来源: https://doc.rust-lang.org/cargo/reference/config.html
#   来源: https://doc.rust-lang.org/cargo/reference/source-replacement.html
if is_config_current "$HOME/.cargo/config.toml"; then
    print_skip "Cargo 镜像配置已存在，跳过"
else
    mkdir -p "$HOME/.cargo"
    cat > "$HOME/.cargo/config.toml" << 'EOF'
# Cargo 用户级配置 - 由 Ubuntu-Init.sh 生成
# 来源: https://rsproxy.cn/
# 来源: https://doc.rust-lang.org/cargo/reference/config.html

# ---- crates.io 源替换（rsproxy.cn 字节跳动镜像）----
# sparse+ 前缀：HTTP 稀疏索引协议（Cargo 1.68+ 稳定，性能远优于 Git 协议）
[source.crates-io]
replace-with = 'rsproxy-sparse'

[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"

[net]
git-fetch-with-cli = true
EOF
    print_info "Cargo 镜像已写入 ~/.cargo/config.toml"
fi

# 3-c. Rust 环境加载 + rustup 镜像变量写入 Shell RC
#   来源: https://rust-lang.github.io/rustup/installation/other.html
#   来源: https://rust-lang.github.io/rustup/environment-variables.html
#   来源: https://rsproxy.cn/
#
#   注：rustup 不支持配置文件，RUSTUP_DIST_SERVER / RUSTUP_UPDATE_ROOT
#   只能通过环境变量传入。此处 export 是唯一可靠的持久化方式，
#   确保 `rustup update` / `rustup install` 走镜像。
#   这是对"不依赖 Shell 环境变量"原则的已知例外。

# bash
if grep -q "Ubuntu-Init Rust" "$HOME/.bashrc"; then
    print_skip "Rust 环境加载已存在于 ~/.bashrc，跳过"
else
    cat >> "$HOME/.bashrc" << 'BASHEOF'

# --- Ubuntu-Init Rust ---
# 来源: https://rust-lang.github.io/rustup/installation/other.html
# 来源: https://rsproxy.cn/
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
# --- end Ubuntu-Init Rust ---
BASHEOF
    print_info "Rust 环境加载已写入 ~/.bashrc"
fi

# zsh
if [ -f "$HOME/.zshrc" ]; then
    if grep -q "Ubuntu-Init Rust" "$HOME/.zshrc"; then
        print_skip "Rust 环境加载已存在于 ~/.zshrc，跳过"
    else
        cat >> "$HOME/.zshrc" << 'ZSHEOF'

# --- Ubuntu-Init Rust ---
# 来源: https://rust-lang.github.io/rustup/installation/other.html
# 来源: https://rsproxy.cn/
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
# --- end Ubuntu-Init Rust ---
ZSHEOF
        print_info "Rust 环境加载已写入 ~/.zshrc"
    fi
fi

# fish
FISH_CARGO_FILE="$FISH_CONF_D/cargo.fish"
if [ -d "$FISH_CONF_D" ]; then
    if [ -f "$FISH_CARGO_FILE" ]; then
        print_skip "$FISH_CARGO_FILE 已存在，跳过"
    else
        cat > "$FISH_CARGO_FILE" << 'FISHEOF'
# Ubuntu-Init Rust - 由 Ubuntu-Init.sh 生成
# 来源: https://rust-lang.github.io/rustup/installation/other.html
# 来源: https://rsproxy.cn/
# fish 不兼容 POSIX sh，直接添加 cargo bin 到 PATH 并设置 rustup 镜像
fish_add_path "$HOME/.cargo/bin"
set -gx RUSTUP_DIST_SERVER "https://rsproxy.cn"
set -gx RUSTUP_UPDATE_ROOT "https://rsproxy.cn/rustup"
FISHEOF
        print_info "Rust 环境加载已写入 $FISH_CARGO_FILE"
    fi
fi

# ============================================================
# 验证安装结果
# ============================================================
print_step "验证安装结果"

ALL_OK=1
check_tool() {
    local label="$1" cmd="$2"
    if command -v "$cmd" &>/dev/null; then
        print_info "${label}: $("$cmd" --version 2>&1 | head -1)"
    else
        print_warn "${label}: 未找到 '$cmd'（重启终端后再验证）"
        ALL_OK=0
    fi
}

check_tool "Python3" "python3"
check_tool "pip3"    "pip3"
check_tool "uv"      "uv"
check_tool "fnm"     "$FNM_INSTALL_DIR/fnm"
check_tool "node"    "node"
check_tool "npm"     "npm"
check_tool "rustc"   "rustc"
check_tool "cargo"   "cargo"

echo ""
if [ "$ALL_OK" -eq 1 ]; then
    echo -e "\033[1;32m  ╔══════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;32m  ║        ✅ 环境安装完成                       ║\033[0m"
    echo -e "\033[1;32m  ╚══════════════════════════════════════════════╝\033[0m"
else
    echo -e "\033[1;33m  ╔══════════════════════════════════════════════╗\033[0m"
    echo -e "\033[1;33m  ║     ⚠️  安装完成（部分工具待验证）           ║\033[0m"
    echo -e "\033[1;33m  ╚══════════════════════════════════════════════╝\033[0m"
fi
echo ""
echo -e "  \033[1;36m配置文件汇总：\033[0m"
echo -e "  \033[1;36m  pip    → ~/.config/pip/pip.conf          (清华 TUNA)\033[0m"
echo -e "  \033[1;36m  uv     → ~/.config/uv/uv.toml            (清华 TUNA)\033[0m"
echo -e "  \033[1;36m  npm    → ~/.npmrc                        (npmmirror)\033[0m"
echo -e "  \033[1;36m  Cargo  → ~/.cargo/config.toml            (rsproxy.cn)\033[0m"
echo -e "  \033[1;36m  rustup → Shell RC 中 export              (rsproxy.cn)\033[0m"
echo -e "  \033[1;36m  fnm    → ~/.bashrc / ~/.zshrc / ~/.config/fish/conf.d/fnm.fish\033[0m"
echo -e "  \033[1;36m  Rust   → ~/.bashrc / ~/.zshrc / ~/.config/fish/conf.d/cargo.fish\033[0m"
echo -e "  \033[1;33m🔄 请重新打开终端使所有 PATH 变更生效\033[0m"
echo ""