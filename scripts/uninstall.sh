#!/usr/bin/env bash
# HKT IP 监控 - 卸载脚本
set -euo pipefail
[[ $EUID -ne 0 ]] && { echo "请用 sudo 运行" >&2; exit 1; }

systemctl stop hkt-ipswitch 2>/dev/null || true
systemctl disable hkt-ipswitch 2>/dev/null || true
rm -f /etc/systemd/system/hkt-ipswitch.service
systemctl daemon-reload || true

rm -rf /opt/hkt-ipswitch
rm -f /usr/local/bin/hkt-ipswitch

echo "✓ 二进制与 systemd 已移除"
echo "配置/日志保留，如需彻底清除："
echo "  rm -rf /etc/hkt-ipswitch /var/log/hkt-ipswitch.log"
