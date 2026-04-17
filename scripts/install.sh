#!/usr/bin/env bash
# HKT IP 自动切换 + 阿里云 DNS 更新 - 一键安装脚本
# 用法: curl -sSL https://raw.githubusercontent.com/<USER>/<REPO>/main/scripts/install.sh | sudo bash
#      或下载后: sudo bash install.sh

set -euo pipefail

# ============================================================
# 配置：发布仓库位置（部署前请改成你自己的 GitHub 仓库）
# ============================================================
GH_USER="${HKT_GH_USER:-skwoksn12}"
GH_REPO="${HKT_GH_REPO:-ssshhhttt}"
GH_TAG="${HKT_GH_TAG:-latest}"   # 或固定版本号: v0.1.0
# ============================================================

# 颜色
RED=$(printf '\033[31m'); GRN=$(printf '\033[32m'); YLW=$(printf '\033[33m'); RST=$(printf '\033[0m')
say() { echo -e "${GRN}▶${RST} $*"; }
warn() { echo -e "${YLW}⚠${RST} $*"; }
err() { echo -e "${RED}✘${RST} $*" >&2; }

# 必须 root
[[ $EUID -ne 0 ]] && { err "请用 sudo 或 root 运行"; exit 1; }

# 检查依赖
for dep in curl; do
  command -v "$dep" >/dev/null || { err "缺少依赖: $dep"; exit 1; }
done

# 识别架构
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "不支持的架构: $ARCH"; exit 1 ;;
esac
say "检测到架构: $ARCH"

# 下载 URL
if [[ "$GH_TAG" == "latest" ]]; then
  DL_URL="https://github.com/$GH_USER/$GH_REPO/releases/latest/download/hkt-ipswitch-linux-$ARCH"
else
  DL_URL="https://github.com/$GH_USER/$GH_REPO/releases/download/$GH_TAG/hkt-ipswitch-linux-$ARCH"
fi

# 也可以直接用 raw（如果没有用 Release）
ALT_URL="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/main/hkt-ipswitch-linux-$ARCH"

# 创建目录
say "创建 /opt/hkt-ipswitch"
mkdir -p /opt/hkt-ipswitch
mkdir -p /etc/hkt-ipswitch
chmod 700 /etc/hkt-ipswitch

# 下载二进制
TARGET="/opt/hkt-ipswitch/hkt-ipswitch"
say "下载二进制: $DL_URL"
if ! curl -fsSL -o "$TARGET" "$DL_URL" 2>/dev/null; then
  warn "Release 下载失败，尝试 raw 方式: $ALT_URL"
  curl -fsSL -o "$TARGET" "$ALT_URL" || { err "下载失败，请检查网络或仓库地址"; exit 1; }
fi
chmod 755 "$TARGET"

# 建立软链
ln -sf "$TARGET" /usr/local/bin/hkt-ipswitch

# 启动安装向导
say "启动交互式安装向导"
echo ""
exec "$TARGET" install
