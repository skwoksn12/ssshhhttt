#!/usr/bin/env bash
# hkt-ipswitch 一键管理脚本
# 用法:
#   curl -sSL https://raw.githubusercontent.com/skwoksn12/ssshhhttt/main/scripts/hkt-admin.sh | sudo bash -s -- <命令>
#
# 命令:
#   upgrade       升级到最新版本 (保留配置)
#   switch        手动触发换 IP (tmux 后台跑)
#   restart       重启 daemon
#   status        查看状态 + 日志
#   install       重新安装 (交互式向导)
#   uninstall     彻底卸载
#   logs          实时看日志 (Ctrl+C 退出)
#
# 示例:
#   curl -sSL .../hkt-admin.sh | sudo bash -s -- upgrade
#   curl -sSL .../hkt-admin.sh | sudo bash -s -- switch
#   curl -sSL .../hkt-admin.sh | sudo bash -s -- status

set -e

REPO="skwoksn12/ssshhhttt"
R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[34m'; N=$'\033[0m'
say() { echo "${G}▶${N} $*"; }
warn() { echo "${Y}⚠${N} $*"; }
err() { echo "${R}✘${N} $*" >&2; }

[[ $EUID -ne 0 ]] && { err "请用 sudo 运行"; exit 1; }

CMD="${1:-status}"

case "$CMD" in
  upgrade)
    say "升级 hkt-ipswitch 到最新版"
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64|amd64) ARCH=amd64 ;;
      aarch64|arm64) ARCH=arm64 ;;
      *) err "不支持的架构: $ARCH"; exit 1 ;;
    esac
    URL="https://github.com/$REPO/releases/latest/download/hkt-ipswitch-linux-$ARCH"

    say "停止 daemon"
    systemctl stop hkt-ipswitch 2>/dev/null || true

    say "下载 $URL"
    curl -fsSL -o /opt/hkt-ipswitch/hkt-ipswitch.new "$URL"
    mv /opt/hkt-ipswitch/hkt-ipswitch.new /opt/hkt-ipswitch/hkt-ipswitch
    chmod +x /opt/hkt-ipswitch/hkt-ipswitch

    VER=$(/opt/hkt-ipswitch/hkt-ipswitch version)
    say "已安装: $VER"

    say "启动 daemon"
    systemctl start hkt-ipswitch
    sleep 2
    systemctl status hkt-ipswitch --no-pager | head -5
    say "升级完成。看日志: sudo tail -f /var/log/hkt-ipswitch.log"
    ;;

  switch)
    say "手动触发换 IP (dhcp_renew 模式)"
    warn "SSH 将在 ~5 秒后断开，1-2 分钟后用新 IP 重连"
    warn "换 IP 过程 + TG 发送最长 4 分钟 (tmux 保证完成)"

    systemctl stop hkt-ipswitch 2>/dev/null || true

    # 清旧日志
    rm -f /tmp/hkt-switch-latest.log

    # tmux 后台跑
    if ! command -v tmux &>/dev/null; then
      say "装 tmux..."
      apt install -y tmux
    fi
    tmux kill-session -t hkt-switch 2>/dev/null || true
    tmux new-session -d -s hkt-switch 'hkt-ipswitch switch 2>&1 | tee /tmp/hkt-switch-latest.log'

    say "已后台触发。重连后查看完整日志:"
    echo "  cat /tmp/hkt-switch-latest.log"
    say "重连后记得启动 daemon:"
    echo "  sudo systemctl start hkt-ipswitch"
    echo ""
    say "前 10 秒日志 (之后 SSH 会断):"
    sleep 3
    tail /tmp/hkt-switch-latest.log 2>/dev/null || echo "(日志还没开始写)"
    ;;

  restart)
    say "重启 daemon"
    systemctl restart hkt-ipswitch
    sleep 2
    systemctl status hkt-ipswitch --no-pager | head -5
    ;;

  status)
    say "daemon 状态"
    systemctl status hkt-ipswitch --no-pager | head -8
    echo ""
    say "版本 + 当前 IP + DNS"
    /opt/hkt-ipswitch/hkt-ipswitch version 2>/dev/null || echo "(未安装)"
    /opt/hkt-ipswitch/hkt-ipswitch status 2>/dev/null || true
    echo ""
    say "最近 10 行日志"
    tail -n 10 /var/log/hkt-ipswitch.log 2>/dev/null || echo "(无日志)"
    ;;

  install)
    say "启动安装向导"
    curl -sSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | bash
    ;;

  uninstall)
    warn "即将卸载 hkt-ipswitch（保留配置和日志）"
    read -p "确认 (yes/N): " ans
    [[ "$ans" != "yes" ]] && { say "已取消"; exit 0; }
    systemctl stop hkt-ipswitch 2>/dev/null || true
    systemctl disable hkt-ipswitch 2>/dev/null || true
    /opt/hkt-ipswitch/hkt-ipswitch uninstall 2>/dev/null || true
    rm -f /etc/systemd/system/hkt-ipswitch.service
    rm -rf /opt/hkt-ipswitch
    rm -f /usr/local/bin/hkt-ipswitch
    systemctl daemon-reload
    say "已卸载。配置保留: /etc/hkt-ipswitch/"
    say "彻底清除: sudo rm -rf /etc/hkt-ipswitch /var/log/hkt-*.log"
    ;;

  logs)
    say "实时日志 (Ctrl+C 退出)"
    tail -f /var/log/hkt-ipswitch.log
    ;;

  *)
    err "未知命令: $CMD"
    echo ""
    echo "可用命令:"
    echo "  upgrade     升级到最新版本"
    echo "  switch      手动换 IP (tmux 后台)"
    echo "  restart     重启 daemon"
    echo "  status      看状态"
    echo "  install     重装 (向导)"
    echo "  uninstall   卸载"
    echo "  logs        实时日志"
    exit 1
    ;;
esac
