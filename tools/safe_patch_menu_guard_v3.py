#!/usr/bin/env python3
from pathlib import Path
import hashlib
import re
import subprocess
import sys
import time

MODULES = [
    "00_ui.sh",
    "01_system.sh",
    "02_service_firewall.sh",
    "03_env_core.sh",
    "04_install_nodes.sh",
    "05_subscription.sh",
    "06_panel_tools.sh",
    "07_menu.sh",
    "08_update.sh",
]

TARGETS = ["install.sh", "VERSION"] + [f"lib/{x}" for x in MODULES]
ROOT = Path.cwd()
ORIG = None
BACKUP = None

def run(cmd, check=True):
    r = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True)
    if check and r.returncode != 0:
        raise RuntimeError(
            "命令失败: " + " ".join(cmd) + "\n" +
            (r.stdout or "") + (r.stderr or "")
        )
    return r

def msg(s):
    print("[safe-patch-v3]", s, flush=True)

def read(p):
    return (ROOT / p).read_text(encoding="utf-8")

def write(p, s):
    (ROOT / p).write_text(s, encoding="utf-8")

def sha(p):
    return hashlib.sha256((ROOT / p).read_bytes()).hexdigest()

def rollback(reason):
    print("\n[safe-patch-v3] 补丁失败，开始回滚。", file=sys.stderr)
    print("[safe-patch-v3] 失败原因:", reason, file=sys.stderr)
    if ORIG:
        run(["git", "reset", "--hard", ORIG], check=False)
        run(["git", "reset"], check=False)
        print("[safe-patch-v3] 已回滚到:", ORIG, file=sys.stderr)
    if BACKUP:
        print("[safe-patch-v3] 保留备份分支:", BACKUP, file=sys.stderr)

def ensure_clean():
    run(["git", "rev-parse", "--show-toplevel"])
    if run(["git", "diff", "--quiet"], check=False).returncode != 0:
        raise RuntimeError("当前 tracked 工作区有未提交修改，请先处理。")
    if run(["git", "diff", "--cached", "--quiet"], check=False).returncode != 0:
        raise RuntimeError("当前暂存区不为空，请先 git reset。")

def backup():
    global ORIG, BACKUP
    ORIG = run(["git", "rev-parse", "HEAD"]).stdout.strip()
    BACKUP = f"backup/before-menu-guard-v3-{int(time.time())}"
    run(["git", "branch", BACKUP, ORIG])
    msg(f"已创建回滚分支: {BACKUP}")
    msg(f"原始 HEAD: {ORIG}")

def bump_version():
    v = read("VERSION").strip()
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", v)
    if not m:
        raise RuntimeError(f"VERSION 格式异常: {v}")
    a, b, c = map(int, m.groups())
    nv = f"{a}.{b}.{c + 1}"
    write("VERSION", nv + "\n")
    msg(f"版本更新: {v} -> {nv}")
    return nv

def patch_install(version):
    t = read("install.sh").replace("\r\n", "\n").replace("\r", "\n")

    for key in ["MODULES=(", "validate_local_bundle()", "install_self_shortcut()", "ensure_modules || exit 1"]:
        if key not in t:
            raise RuntimeError(f"install.sh 缺少关键结构: {key}")

    helper_and_validate = r'''
validate_required_symbols() {
 local menu_file="$SCRIPT_DIR/lib/07_menu.sh"

 if [[ ! -s "$menu_file" ]]; then
 echo " [错误] 菜单模块为空或不存在：$menu_file" >&2
 return 1
 fi

 if ! grep -qE '^[[:space:]]*menu[[:space:]]*\(\)[[:space:]]*\{' "$menu_file"; then
 echo " [错误] 菜单模块未定义 menu()：$menu_file" >&2
 echo " [诊断] 可能原因：07_menu.sh 是旧版、下载损坏、复制失败，或 /usr/bin/666 指向了旧安装目录。" >&2
 return 1
 fi

 return 0
}

load_modules() {
 local module=""
 local module_path=""

 for module in "${MODULES[@]}"; do
 module_path="$SCRIPT_DIR/lib/$module"

 if [[ ! -s "$module_path" ]]; then
 echo " [错误] 模块为空或不存在：$module_path" >&2
 return 1
 fi

 # shellcheck source=/dev/null
 if ! source "$module_path"; then
 echo " [错误] 模块加载失败：$module_path" >&2
 return 1
 fi
 done

 if ! declare -F menu >/dev/null 2>&1; then
 echo " [错误] 主菜单函数 menu 未加载，已停止进入主循环。" >&2
 echo " [诊断] SCRIPT_DIR=$SCRIPT_DIR" >&2
 echo " [诊断] 请检查：ls -l \"$SCRIPT_DIR/lib/07_menu.sh\" && grep -n '^menu[[:space:]]*()' \"$SCRIPT_DIR/lib/07_menu.sh\"" >&2
 return 1
 fi

 return 0
}

validate_local_bundle() {
 local module=""

 if [[ ! -s "$SCRIPT_DIR/install.sh" ]]; then
 echo " [错误] 找不到入口文件或入口文件为空：$SCRIPT_DIR/install.sh" >&2
 return 1
 fi

 if ! bash -n "$SCRIPT_DIR/install.sh"; then
 echo " [错误] install.sh 语法检查失败。" >&2
 return 1
 fi

 for module in "${MODULES[@]}"; do
 if [[ ! -s "$SCRIPT_DIR/lib/$module" ]]; then
 echo " [错误] 模块文件缺失或为空：$module" >&2
 return 1
 fi

 if ! bash -n "$SCRIPT_DIR/lib/$module"; then
 echo " [错误] 模块语法检查失败：$module" >&2
 return 1
 fi
 done

 validate_required_symbols || return 1

 echo " [安全] 入口和全部模块语法检查通过。"
}'''

    t, n = re.subn(
        r'\nvalidate_local_bundle\(\) \{.*?\n\}\s*\nensure_modules\(\) \{',
        "\n" + helper_and_validate + "\n\nensure_modules() {",
        t,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise RuntimeError("未能整体替换 validate_local_bundle()。")

    t = t.replace('[[ ! -f "$SCRIPT_DIR/lib/$module" ]]', '[[ ! -s "$SCRIPT_DIR/lib/$module" ]]')

    new_shortcut = r'''install_self_shortcut() {
 # 模块化后不能再只把单个 install.sh 复制到 /usr/bin/666。
 # 正确做法：把入口和 lib/ 一起落盘到 /opt，再创建 666 包装器。
 mkdir -p "$INSTALL_DIR/lib"

 if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
 cp -f "$SCRIPT_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || cp -f "$SCRIPT_PATH" "$INSTALL_DIR/install.sh" || return 1

 local module=""
 for module in "${MODULES[@]}"; do
 if [[ ! -s "$SCRIPT_DIR/lib/$module" ]]; then
 echo " [错误] 无法落盘快捷入口：模块缺失或为空：$SCRIPT_DIR/lib/$module" >&2
 return 1
 fi
 cp -f "$SCRIPT_DIR/lib/$module" "$INSTALL_DIR/lib/$module" || return 1
 done

 cp -f "$SCRIPT_DIR/$VERSION_FILE" "$INSTALL_DIR/$VERSION_FILE" 2>/dev/null || echo "$HY2_VLESS_VERSION" > "$INSTALL_DIR/$VERSION_FILE"
 cp -f "$SCRIPT_DIR/SHA256SUMS" "$INSTALL_DIR/SHA256SUMS" 2>/dev/null || true
 chmod +x "$INSTALL_DIR/install.sh"
 chmod +x "$INSTALL_DIR"/lib/*.sh 2>/dev/null || true
 fi

 cat > /usr/bin/666 <<EOF_WRAPPER
#!/usr/bin/env bash
cd "$INSTALL_DIR" || exit 1
exec bash "$INSTALL_DIR/install.sh" "\$@"
EOF_WRAPPER

 chmod +x /usr/bin/666
}'''

    t, n = re.subn(
        r'\ninstall_self_shortcut\(\) \{.*?\n\}\s*\nensure_modules \|\| exit 1',
        "\n" + new_shortcut + "\n\nensure_modules || exit 1",
        t,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise RuntimeError("未能整体替换 install_self_shortcut()。")

    new_bottom = '''ensure_modules || exit 1

validate_local_bundle || exit 1

load_modules || exit 1

install_self_shortcut || exit 1

while true; do
 menu
done
'''

    t, n = re.subn(
        r'ensure_modules \|\| exit 1.*\Z',
        new_bottom,
        t,
        count=1,
        flags=re.S,
    )
    if n != 1:
        raise RuntimeError("未能整体替换底部主流程。")

    t = re.sub(
        r"# V[0-9.]+ 全局防并发排他锁",
        f"# V{version} 全局防并发排他锁",
        t,
        count=1,
    )

    write("install.sh", t)
    msg("install.sh 已写入补丁。")

def rebuild_sha():
    lines = []
    for p in TARGETS:
        if not (ROOT / p).exists():
            raise RuntimeError(f"缺少文件，无法生成 SHA256SUMS: {p}")
        lines.append(f"{sha(p)}  {p}")
    write("SHA256SUMS", "\n".join(lines) + "\n")
    msg("SHA256SUMS 已重建。")

def validate():
    run(["bash", "-n", "install.sh"])
    for m in MODULES:
        run(["bash", "-n", f"lib/{m}"])

    t = read("install.sh")
    markers = [
        "validate_required_symbols()",
        "load_modules()",
        "declare -F menu",
        "validate_required_symbols || return 1",
        "load_modules || exit 1",
        "install_self_shortcut || exit 1",
        "无法落盘快捷入口：模块缺失或为空",
        "主菜单函数 menu 未加载，已停止进入主循环",
    ]
    for x in markers:
        if x not in t:
            raise RuntimeError(f"补丁标记缺失: {x}")

    if t.count("validate_required_symbols()") != 1:
        raise RuntimeError("validate_required_symbols() 数量异常。")
    if t.count("load_modules()") != 1:
        raise RuntimeError("load_modules() 数量异常。")

    menu = read("lib/07_menu.sh")
    if not re.search(r"(^|\n)[ \t]*menu[ \t]*\(\)[ \t]*\{", menu):
        raise RuntimeError("lib/07_menu.sh 中未找到 menu() 定义。")

    lines = read("SHA256SUMS").splitlines()
    if len(lines) != len(TARGETS):
        raise RuntimeError(f"SHA256SUMS 行数异常: {len(lines)}，应为 {len(TARGETS)}。")

    seen = {}
    for line in lines:
        if not re.match(r"^[0-9a-f]{64}  .+$", line):
            raise RuntimeError(f"SHA256SUMS 格式异常: {line!r}")
        h, name = line.split("  ", 1)
        seen[name] = h

    for p in TARGETS:
        if seen.get(p) != sha(p):
            raise RuntimeError(f"SHA256SUMS 校验失败: {p}")

    msg("语法验证、补丁标记验证、菜单函数验证、SHA256 验证全部通过。")

def commit():
    run(["git", "add", "install.sh", "VERSION", "SHA256SUMS"])
    if run(["git", "diff", "--cached", "--quiet"], check=False).returncode == 0:
        raise RuntimeError("没有可提交变更，补丁可能没有写入。")
    version = read("VERSION").strip()
    run(["git", "commit", "-m", f"fix: guard menu loading and bump to v{version}"])
    msg("已自动提交。")

def main():
    try:
        ensure_clean()
        backup()
        version = bump_version()
        patch_install(version)
        rebuild_sha()
        validate()
        commit()
        msg("补丁成功打入。")
        print()
        print("请继续执行：")
        print('grep -n "validate_required_symbols\\|load_modules\\|declare -F menu" install.sh')
        print("head -n 5 SHA256SUMS")
        print("git show --stat --oneline HEAD")
        print("git push --force-with-lease origin main")
        return 0
    except Exception as e:
        rollback(str(e))
        return 1

if __name__ == "__main__":
    sys.exit(main())
