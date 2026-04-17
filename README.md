# hkt-ipswitch

HKT 香港服务器 IP 被墙自动切换 + 阿里云 DNS 联动更新工具。

## 功能

- 50 个大陆知名站点轮询探测，判断 IP 是否被 GFW 屏蔽
- 确认被墙后，调用 VPS 商家 API 更换 IP
- 自动更新阿里云 DNS A 记录
- Telegram 实时告警
- 冷却保护、连续失败熔断、多点确认防误判
- 单静态二进制，systemd 托管

## 一键安装

```bash
curl -sSL https://raw.githubusercontent.com/skwoksn12/ssshhhttt/main/scripts/install.sh | sudo bash
```

安装向导会交互式收集：
- SynexVM `service_id` + `token`
- 完整域名（如 `xxx.example.com`）
- 阿里云 AccessKey（建议 RAM 子账号，仅 `AliyunDNSFullAccess` 权限）
- Telegram Bot Token + Chat ID
- 监控参数（周期 / 冷却 / 重试）

## 常用命令

```bash
hkt-ipswitch status         # 查看当前 IP / DNS / 统计
hkt-ipswitch test-tg        # 测试 Telegram
hkt-ipswitch test-dns       # 测试阿里云 DNS
hkt-ipswitch test-synexvm   # 测试 SynexVM API
hkt-ipswitch test-detect    # 跑一次随机探测
hkt-ipswitch switch         # 强制换一次 IP
hkt-ipswitch uninstall      # 卸载
```

查看日志：
```bash
journalctl -u hkt-ipswitch -f
tail -f /var/log/hkt-ipswitch.log
```

## 文件位置

| 路径 | 说明 |
|---|---|
| `/opt/hkt-ipswitch/hkt-ipswitch` | 主二进制 |
| `/opt/hkt-ipswitch/targets.txt` | 50 个检测目标（可编辑） |
| `/etc/hkt-ipswitch/config.yaml` | 敏感配置 (chmod 600) |
| `/etc/hkt-ipswitch/state.json` | 运行状态（冷却、历史） |
| `/var/log/hkt-ipswitch.log` | 日志 |
| `/etc/systemd/system/hkt-ipswitch.service` | systemd 单元 |

## 卸载

```bash
curl -sSL https://raw.githubusercontent.com/skwoksn12/ssshhhttt/main/scripts/uninstall.sh | sudo bash
```

## 下载二进制

见 [Releases](https://github.com/skwoksn12/ssshhhttt/releases)。

- `hkt-ipswitch-linux-amd64` - x86_64
- `hkt-ipswitch-linux-arm64` - ARM64
