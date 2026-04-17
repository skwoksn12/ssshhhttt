#!/bin/bash
# =============================================================================
# HKT 换IP脚本 v1（仅实现基础手动换IP功能）
# 支持 SSH 下安全执行（自动后台运行，防连接断开导致脚本中止）
# 通过伪造 MAC 地址触发 ISP 分配新 IP（HKT 按 MAC 绑定 IP）
# 日志保存至同目录 change_ip.log
# =============================================================================

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
LOG_FILE="$SCRIPT_DIR/change_ip.log"
LOCK_FILE="/tmp/change_ip.lock"

# log：后台(--detached)模式下 stdout 已被 nohup 重定向到文件，
# 只需 echo 到 stdout 即可，不能再用 tee 否则每行写两遍。
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# =============================================================================
# SSH 防断连：在 SSH 会话中直接执行时，自动用 nohup 切换到后台运行
# dhclient -r 释放 IP 后 SSH 连接必然中断；
# 若未提前脱离会话，脚本收到 SIGHUP 后会被杀死。
# =============================================================================
if [ -n "$SSH_CONNECTION" ] && [ "$1" != "--detached" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 检测到 SSH 环境，切换后台运行..." >> "$LOG_FILE"

    # nohup 只能忽略 SIGHUP，但进程仍属于 SSH 会话的进程组，
    # IP 释放导致 SSH 强制断开时整个进程组仍可能被终止。
    # setsid 创建全新的 session，彻底脱离 SSH 的控制终端，最为可靠。
    # 优先用 setsid，不可用时降级到 nohup。
    SELF="$(realpath "$0")"
    if command -v setsid &>/dev/null; then
        setsid bash "$SELF" --detached >> "$LOG_FILE" 2>&1 &
    else
        nohup bash "$SELF" --detached >> "$LOG_FILE" 2>&1 &
    fi
    BGPID=$!
    disown $BGPID 2>/dev/null   # 从当前 shell 的 job 表移除，防止 shell 退出时发送信号
    echo "已在后台启动 (PID: $BGPID)，SSH 断开后脚本继续运行。"
    echo "实时查看日志: tail -f $LOG_FILE"
    exit 0
fi

# =============================================================================
# 防重复执行
# =============================================================================
if [ -f "$LOCK_FILE" ]; then
    log "错误：检测到锁文件，另一个实例可能正在运行，退出。" >> "$LOG_FILE"
    exit 1
fi
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; log "锁文件已释放。"' EXIT

# =============================================================================
# 工具函数
# =============================================================================

# 自动检测默认出口网卡（如 eth0、ens3 等）
get_iface() {
    ip route show default 2>/dev/null | grep -oP 'dev \K\S+' | head -1
}

get_current_ip() {
    ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' | head -1 \
    || ip addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1
}

# 生成随机 MAC（02:xx:xx:xx:xx:xx，02 表示本地管理地址，合法且不冲突）
random_mac() {
    printf '02:%02x:%02x:%02x:%02x:%02x' \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256)) $((RANDOM % 256)) \
        $((RANDOM % 256))
}

# =============================================================================
# 主流程
# =============================================================================
log "=========================================="
log "开始换IP流程"

IFACE=$(get_iface)
if [ -z "$IFACE" ]; then
    log "错误：无法检测到默认网卡，退出。"
    exit 1
fi
log "网卡: $IFACE"

OLD_IP=$(get_current_ip)
OLD_MAC=$(ip link show "$IFACE" 2>/dev/null | grep -oP 'link/ether \K\S+' | head -1)
log "换IP前 IP : ${OLD_IP:-（未能获取）}"
log "换IP前 MAC: ${OLD_MAC:-（未能获取）}"

# --- 步骤1：释放 DHCP 租约 ---
log "释放 DHCP 租约..."
dhclient -r "$IFACE" 2>&1 | while IFS= read -r line; do [ -n "$line" ] && log "  [dhclient-r] $line"; done
sleep 2

# --- 步骤2：清理旧租约文件 ---
log "清理旧租约文件..."
rm -f /var/lib/dhcp/dhclient* /var/lib/dhclient/dhclient* 2>/dev/null

# --- 步骤3：伪造 MAC 地址（HKT 按 MAC 绑定 IP，不换 MAC 则拿回同一个 IP）---
NEW_MAC=$(random_mac)
log "伪造 MAC: ${OLD_MAC} → ${NEW_MAC}"
ip link set "$IFACE" down
ip link set "$IFACE" address "$NEW_MAC"
ip link set "$IFACE" up
sleep 3

# --- 步骤4：重新申请 DHCP ---
log "重新申请 DHCP 租约..."
dhclient -v "$IFACE" 2>&1 | while IFS= read -r line; do [ -n "$line" ] && log "  [dhclient] $line"; done

# 等待网络稳定
sleep 5

NEW_IP=$(get_current_ip)
log "换IP后 IP : ${NEW_IP:-（未能获取）}"
log "换IP后 MAC: ${NEW_MAC}"

# --- 结果判断 ---
if [ -z "$NEW_IP" ]; then
    log "结果：失败 — 换IP后未获取到 IP，尝试还原 MAC 并重新连接..."
    ip link set "$IFACE" down
    ip link set "$IFACE" address "$OLD_MAC"
    ip link set "$IFACE" up
    dhclient "$IFACE" 2>/dev/null
    sleep 5
    RECOVERED_IP=$(get_current_ip)
    log "已还原 MAC 为 ${OLD_MAC}，当前 IP: ${RECOVERED_IP:-（仍未获取）}"
elif [ "$NEW_IP" = "$OLD_IP" ]; then
    log "结果：未变化 — IP 仍为 ${NEW_IP}（ISP 可能有额外绑定策略）"
else
    log "结果：成功 — ${OLD_IP:-未知} → ${NEW_IP}"
fi

log "换IP流程结束"
log "=========================================="