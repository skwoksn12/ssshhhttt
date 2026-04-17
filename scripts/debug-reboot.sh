#!/usr/bin/env bash
# 一键升级 + 测试 reboot 机制（默认 dry-run，不真重启）
#
# 用法:
#   curl -sSL https://raw.githubusercontent.com/skwoksn12/ssshhhttt/main/scripts/debug-reboot.sh | sudo bash
#
#   或指定版本:
#   curl -sSL ... | sudo bash -s -- v0.2.6
#
#   或真实重启（会 reboot VM！）:
#   curl -sSL ... | sudo bash -s -- latest --real

set -e

VER="${1:-latest}"
MODE="${2:-dry-run}"

# 颜色
R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; N=$'\033[0m'
say() { echo "${G}▶${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
err() { echo "${R}✘${N} $*" >&2; }

[[ $EUID -ne 0 ]] && { err "请用 sudo 运行"; exit 1; }

# 识别架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) err "不支持的架构: $ARCH"; exit 1 ;;
esac

REPO="skwoksn12/ssshhhttt"
if [[ "$VER" == "latest" ]]; then
  URL="https://github.com/$REPO/releases/latest/download/hkt-ipswitch-linux-$ARCH"
else
  URL="https://github.com/$REPO/releases/download/$VER/hkt-ipswitch-linux-$ARCH"
fi

echo
say "========================================"
say "hkt-ipswitch reboot 调度一键测试脚本"
say "版本: $VER   架构: $ARCH   模式: $MODE"
say "========================================"
echo

# ===== 1. 停服务 =====
say "[1/7] 停止 daemon (如果在跑)"
systemctl stop hkt-ipswitch 2>/dev/null || true
echo

# ===== 2. 升级二进制 =====
say "[2/7] 下载 $VER 二进制: $URL"
if ! curl -fsSL -o /opt/hkt-ipswitch/hkt-ipswitch.new "$URL"; then
  err "下载失败"
  exit 1
fi
mv /opt/hkt-ipswitch/hkt-ipswitch.new /opt/hkt-ipswitch/hkt-ipswitch
chmod +x /opt/hkt-ipswitch/hkt-ipswitch
ACTUAL_VER=$(/opt/hkt-ipswitch/hkt-ipswitch version 2>&1 | head -1)
say "安装完成: $ACTUAL_VER"
echo

# ===== 3. 清理旧审计日志 =====
say "[3/7] 清理旧审计日志和辅助脚本"
rm -f /var/log/hkt-reboot-audit.log
rm -f /var/lib/hkt-ipswitch-reboot.sh
rm -f /tmp/hkt-reboot-pending.log
echo

# ===== 4. 环境诊断 =====
say "[4/7] 环境诊断"
echo "  OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "  systemd: $(systemctl --version | head -1)"
echo "  systemd-run: $(which systemd-run) $(systemd-run --version 2>&1 | head -1)"
echo "  /tmp 挂载: $(findmnt /tmp -o FSTYPE -n 2>/dev/null || echo unknown)"
echo "  /var/log 挂载: $(findmnt /var/log -o FSTYPE -n 2>/dev/null || echo unknown)"
echo "  当前 uptime: $(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo

# ===== 5. 执行 test-reboot =====
say "[5/7] 执行 test-reboot"
if [[ "$MODE" == "--real" ]]; then
  warn "真实重启模式！5 秒后开始..."
  /opt/hkt-ipswitch/hkt-ipswitch test-reboot --real
  echo
  say "已触发真实重启，连接即将断开"
  exit 0
else
  /opt/hkt-ipswitch/hkt-ipswitch test-reboot
fi
echo

# ===== 6. 详细诊断 =====
say "[6/7] 等额外 3 秒后收集所有证据"
sleep 3
echo
echo "${B}--- /var/log/hkt-reboot-audit.log (完整内容) ---${N}"
cat /var/log/hkt-reboot-audit.log 2>/dev/null || echo "(文件不存在)"
echo "${B}------------------------------------------------${N}"
echo
echo "${B}--- /var/lib/hkt-ipswitch-reboot.sh (内容) ---${N}"
cat /var/lib/hkt-ipswitch-reboot.sh 2>/dev/null || echo "(文件不存在)"
echo "${B}------------------------------------------------${N}"
echo
echo "${B}--- systemd-run 单元痕迹 (journal 最近 20 行) ---${N}"
journalctl --since="2 minutes ago" --no-pager 2>/dev/null | grep -iE "systemd-run|hkt|run-[a-f0-9]" | tail -20 || echo "(无匹配)"
echo "${B}------------------------------------------------${N}"
echo
echo "${B}--- 当前活跃/残留 transient units ---${N}"
systemctl list-units --all --no-legend 2>/dev/null | grep -iE "run-|hkt" | head -5 || echo "(无匹配)"
echo "${B}------------------------------------------------${N}"
echo

# ===== 7. 判定 =====
say "[7/7] 自动判定"
if [[ ! -f /var/log/hkt-reboot-audit.log ]]; then
  err "审计日志文件不存在——代码可能 crash 了"
  exit 2
fi
LINES=$(wc -l < /var/log/hkt-reboot-audit.log)
echo "  audit log 行数: $LINES"

if grep -q "would execute: systemctl reboot --force" /var/log/hkt-reboot-audit.log; then
  # Count how many times
  FIRE_COUNT=$(grep -c "would execute" /var/log/hkt-reboot-audit.log)
  if [[ $FIRE_COUNT -ge 2 ]]; then
    echo "  ${G}✓ reboot 调度机制完全正常${N}（同步自测 + 定时触发都成功）"
    echo "  ${G}可以用 'curl ... | sudo bash -s -- latest --real' 真实测试${N}"
    exit 0
  elif [[ $FIRE_COUNT -eq 1 ]]; then
    warn "只有同步自测触发了，systemd-run 定时任务没触发"
    echo "  →  需要看上面的 journal 诊断输出"
    exit 3
  fi
elif grep -q "systemd-run EXIT ERROR" /var/log/hkt-reboot-audit.log; then
  err "systemd-run 命令本身执行失败"
  echo "  →  看上面的 'systemd-run stdout/stderr' 行"
  exit 4
elif grep -q "sanity exec.*FAILED" /var/log/hkt-reboot-audit.log; then
  err "辅助脚本同步自测就失败了 → 脚本本身有问题"
  exit 5
else
  err "意料之外的状态，贴完整输出给开发者"
  exit 6
fi
