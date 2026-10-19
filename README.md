# AutoDL Mihomo：订阅更新、固定节点与容器自启动

适用于 AutoDL Linux 容器的 Mihomo 独立代理部署说明。**2026-10-18 已在实际 AutoDL 容器停止并重启后验证启动钩子生效**。

## 本次已验证的配置

| 项目 | 配置 |
| --- | --- |
| Mihomo | v1.19.32，`/usr/local/bin/mihomo` |
| 配置 | `/etc/mihomo/config.yaml` |
| 代理 | `127.0.0.1:7890`（mixed-port） |
| 控制 API | `127.0.0.1:9090`（仅本机） |
| 策略组 | `Flybit`（大小写敏感） |
| 固定默认节点 | `🇸🇬 新加坡 \| 03` |
| 选择恢复 | `profile.store-selected: false` |
| AutoDL 启动入口 | `/etc/autodl.sh` → `/root/start_mihomo.sh` |

旧版文档的 `FlyBit`、新加坡 13、`store-selected: true` 与 `/etc/profile.d` 开机钩子是**历史配置**，不再作为当前推荐方案。

## 已安装 Mihomo：快速配置

先阅读 [完整教程](autodl_mihomo_setup.md)，然后将仓库的启动脚本安装到 AutoDL：

```bash
install -m 755 scripts/start_mihomo.sh /root/start_mihomo.sh
```

确保 `/etc/autodl.sh` **保留已有任务**，包含以下两行即可：

```bash
echo "AutoDL startup hook executed at $(date '+%F %T')"
/root/start_mihomo.sh
```

首次创建 `/etc/autodl.sh` 时添加 `#!/bin/bash` 并设置 `chmod +x /etc/autodl.sh`。AutoDL 内部的 `/init/bin/customer.cmd.sh` 会调用 `bash /etc/autodl.sh`；不需要修改 `/init`、Supervisor 或 systemd。

## 更新订阅并保持默认新加坡 03

该脚本不会在仓库或命令中写入订阅凭据，运行时交互输入真实的 Clash/Mihomo 订阅 URL；更新前会验证配置，成功后切换并验证当前节点。

```bash
# Python 依赖（仅安装一次）
python3 -c 'import yaml' || python3 -m pip install pyyaml

# 在仓库目录执行
bash scripts/update_subscription.sh
```

订阅可能更换策略组名称、节点名称或代理端口。如果不包含 `Flybit` 和 `🇸🇬 新加坡 | 03`，脚本会**中止且不覆盖当前配置**。

## 重启后验证

```bash
cat /tmp/autodl.sh.log
pgrep -af mihomo
curl --noproxy '*' -fsS http://127.0.0.1:9090/proxies/Flybit | python3 -c 'import json,sys;print(json.load(sys.stdin)["now"])'
curl -sS -o /dev/null -w 'GitHub HTTP=%{http_code}\n' https://github.com
```

此次实测的开机日志为 `AutoDL startup hook executed at 2026-10-18 23:36:17`；Mihomo 作为 PID 18 运行，并使用新加坡 03。

> 注意：该验证适用于**同一实例停止再启动**。容器重建、更换镜像或更新程序覆盖 `config.yaml` 时，需要重新检查配置。脚本启动后不提供崩溃自动拉起功能。

## 安全

**不要上传**真实订阅链接、凭据、`/etc/mihomo/config.yaml`、Mihomo 日志或缓存到公开仓库；尤其不要把订阅 token 写到脚本或 README。控制 API 仅监听 localhost。代理连接成功不代表 ChatGPT 一定可用：Cloudflare 403 与 OpenAI API 的 401 是不同问题。

完整步骤、诊断与故障处理：[autodl_mihomo_setup.md](autodl_mihomo_setup.md)。
