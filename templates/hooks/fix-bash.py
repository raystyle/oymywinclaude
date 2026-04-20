import sys
import os
import json

try:
    data = json.loads(sys.stdin.read())
    original_cmd = data.get("tool_input", {}).get("command", "")

    # ── UTF-8 编码前缀 ──
    prefix_parts = [
        "chcp.com 65001 > /dev/null 2>&1",
        "export LANG=zh_CN.UTF-8",
        "export LC_ALL=zh_CN.UTF-8",
        "export PYTHONUTF8=1",
        "export PYTHONIOENCODING=utf-8",
        "export LESSCHARSET=utf-8",
    ]

    # ── 自动检测并激活 venv ──
    # 获取 Claude Code 当前工作目录（hook 进程继承）
    cwd = os.getcwd()

    # 按优先级查找 venv 目录：.venv > venv
    venv_dir = None
    for candidate in [".venv", "venv"]:
        candidate_path = os.path.join(cwd, candidate)
        # Windows Git Bash 下 Scripts 目录，同时兼容 Linux/macOS 的 bin 目录
        scripts_win = os.path.join(candidate_path, "Scripts", "activate")
        scripts_unix = os.path.join(candidate_path, "bin", "activate")
        if os.path.isfile(scripts_win) or os.path.isfile(scripts_unix):
            venv_dir = candidate_path
            break

    if venv_dir:
        # 将 Windows 路径转为 Git Bash 兼容的 POSIX 路径
        # D:\oymywinclaude\.venv → /d/oymywinclaude/.venv
        venv_posix = venv_dir.replace("\\", "/")
        if len(venv_posix) >= 2 and venv_posix[1] == ":":
            drive = venv_posix[0].lower()
            venv_posix = "/" + drive + venv_posix[2:]

        # 判断 activate 脚本位置（Windows 用 Scripts，Unix 用 bin）
        if os.path.isdir(os.path.join(venv_dir, "Scripts")):
            activate_path = venv_posix + "/Scripts/activate"
        else:
            activate_path = venv_posix + "/bin/activate"

        # 直接 source activate 脚本
        prefix_parts.append(f'source "{activate_path}"')

    prefix = "; ".join(prefix_parts) + "; "

    sys.stdout.write(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "allow",
            "updatedInput": {
                "command": prefix + original_cmd
            }
        }
    }))
except Exception:
    pass

sys.exit(0)