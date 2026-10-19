# AutoDL Mihomo 完整配置与维护（2026-10-18 更新）

本文针对 **AutoDL Linux 容器**，记录 Mihomo 安装、更新订阅、默认节点选择及经重启验证的开机自启动方案。旧版本曾使用 `FlyBit` / 新加坡 13 / `store-selected: true` / `/etc/profile.d` 钩子；当前实测已更改，不要混用。

## 1. 当前环境和架构

```text
AutoDL 容器启动
  └─ 平台启动入口 /init/bin/customer.cmd.sh
      └─ bash /etc/autodl.sh
          └─ /root/start_mihomo.sh
              └─ /usr/local/bin/mihomo -d /etc/mihomo
                  └─ Flybit → 🇸🇬 新加坡 | 03
```

实际确认的配置：
- `mixed-port: 7890`，`mode: rule`，`external-controller: 127.0.0.1:9090`；
- Mihomo `v1.19.32`；策略组名称精确为 `Flybit`（大小写敏感）；
- `default-selected: "🇸🇬 新加坡 | 03"`，`profile.store-selected: false`；
- 平台 PID 1 是 `bash /init/boot/boot.sh`，不是 systemd；虽然有 supervisord 进程，但它的 `/init/supervisor/supervisor.ini` 在运行时不可访问，故不直接改动；
- `/init/bin/customer.cmd.sh` 中调用 `bash /etc/autodl.sh >> /tmp/autodl.sh.log 2>&1`。

同一 AutoDL 实例停止、重新启动后，观察到 `/tmp/autodl.sh.log` 中记录 `2026-10-18 23:36:17`、Mihomo PID 18，且控制 API 显示新加坡 03。**这能验证当前实例重启后的工作流程，但不保证镜像重建或订阅覆盖后仍保持。**

## 2. 初次安装 Mihomo

机器架构先查 `uname -m`，以下为 x86_64 示例。Mihomo 发行版本及下载地址请以 [MetaCubeX/mihomo Releases](https://github.com/MetaCubeX/mihomo/releases) 为准：

```bash
cd /tmp
curl -fL --retry 3 -o mihomo.gz \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-linux-amd64-v1.19.32.gz
gunzip -f mihomo.gz
install -m 755 mihomo /usr/local/bin/mihomo
/usr/local/bin/mihomo -v
install -d -m 700 /etc/mihomo
```

首次安装要在机场后台获取正确的 **Clash / Mihomo YAML 订阅链接**，不要把 Dashboard URL 当作订阅。首次下载也建议借助下面的订阅更新脚本，而不是直接把未经校验的内容覆盖到运行配置里。

出现 GEOIP MMDB 下载超时时，可按需下载：

```bash
curl -fL --retry 3 \
  https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb \
  -o /etc/mihomo/Country.mmdb
```

验证：`mihomo -t -d /etc/mihomo`。

## 3. 更新订阅：保留默认节点并防止坏配置覆盖

**不要在仓库写入真实订阅 URL 或 token。** 本仓库脚本 `scripts/update_subscription.sh` 会：

1. 交互读取订阅 URL（不回显、不保存到仓库）；
2. 下载到 `/etc/mihomo` 下的临时文件；curl 错误则停止；
3. 通过 PyYAML 解析 YAML，检查 `Flybit` 是 `select`、包含 `🇸🇬 新加坡 | 03`；
4. 设定 `default-selected` 与 `profile.store-selected: false`；
5. 通过 `mihomo -t` 校验后，以原子替换写入 `/etc/mihomo/config.yaml`；
6. 若 Mihomo 已在运行，则重启进程、核查控制 API 和当前选择。

```bash
python3 -c 'import yaml' || python3 -m pip install pyyaml
bash scripts/update_subscription.sh
```

> 注意：PyYAML 会规范化 YAML 的文本格式，但目标是保留普通 Clash/Mihomo YAML 的**配置语义**；如果机场使用特殊 YAML 标签或依赖非标准内容，应先单独审查。发生下载、解析、节点检查或配置验证失败时，脚本不会覆盖原配置。运行中更换配置会短暂中断当前代理连接，建议避开训练下载任务。

订阅生成的文件中可能含有服务器地址和认证密钥，**不得将 `config.yaml` 提交公开 GitHub**。若脚本已成功更新但节点状态不符，优先查看 `/tmp/mihomo.log` 与策略组信息。

## 4. 手动切换及固定默认节点

查询全部 Selector 组：

```bash
curl --noproxy '*' -fsS http://127.0.0.1:9090/proxies | python3 -c '
import json,sys
for name,p in json.load(sys.stdin)["proxies"].items():
    if p.get("type") == "Selector":
        print(name,"当前:",p.get("now"))
'
```

临时切换当前节点：

```bash
curl --noproxy '*' -fsS -X PUT -H 'Content-Type: application/json' \
  -d '{"name":"🇸🇬 新加坡 | 03"}' \
  http://127.0.0.1:9090/proxies/Flybit
```

**临时切换不等于重启后的默认选择。** 对当前机场的 YAML 行内策略组：

```yaml
proxy-groups:
  - {name: 'Flybit', type: select, default-selected: "🇸🇬 新加坡 | 03", proxies: ["🇸🇬 新加坡 | 03"]}
profile:
  store-selected: false
```

上面 `proxies` 只是精简示例，**不要拿它覆盖真实订阅的 73 个节点或其他规则**。推荐使用更新脚本按 YAML 结构调整相应字段。关闭 `store-selected` 是为了避免之前手动切换的节点在下一次启动时覆盖默认选择。

如果订阅更改了组名或节点名，需要相应修改脚本中的 `GROUP` / `NODE` 参数，不能假设订阅永远不变。

## 5. AutoDL 容器级开机自启动（已实测）

创建/安装启动脚本：

```bash
install -m 755 scripts/start_mihomo.sh /root/start_mihomo.sh
```

该脚本先检查已运行进程，再测试 Mihomo 配置，使用 `nohup` 在后台启动，并记录 `/tmp/mihomo.log`。它是**单次拉起脚本，不是持续进程守护器**。

在当前 AutoDL 镜像中，`/init/bin/customer.cmd.sh` 含有：

```bash
echo "### /etc/autodl.sh run log file ###" > /tmp/autodl.sh.log
bash /etc/autodl.sh >> /tmp/autodl.sh.log 2>&1
```

如果 `/etc/autodl.sh` 不存在，可创建：

```bash
cat > /etc/autodl.sh <<'EOF'
#!/bin/bash
echo "AutoDL startup hook executed at $(date '+%F %T')"
/root/start_mihomo.sh
EOF
chmod +x /etc/autodl.sh
```

**如果已有 `/etc/autodl.sh`，不能直接覆盖**，只将日志和 `/root/start_mihomo.sh` 加入原文件，并保留其他任务。不要修改由平台管理的 `/init` 文件，也不要依赖 `systemctl enable`。旧版 `/etc/profile.d/00-mihomo-start.sh` 是历史方案；迁移后建议检查并移除旧的重复开机钩子。

当前 `/root/.bashrc` 里曾有 `/root/start_mihomo.sh`，可作为临时兜底；真正验证成功后可以去掉这一行，保留 shell 代理环境变量，避免其掩盖容器级自启动失效。

## 6. 终端代理环境变量

只为交互 shell 配置，不要全局强制 AutoDL 平台服务经代理：

```bash
# 加入 /root/.bashrc，避免重复添加
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
```

修改后在新终端确认 `env | grep -i proxy`。如果当前 shell 临时禁用代理，可 `unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY`，并不会停止 Mihomo。

## 7. 启动验证与排查

```bash
bash -n /etc/autodl.sh
bash -n /root/start_mihomo.sh
bash /etc/autodl.sh
pgrep -af mihomo
curl --noproxy '*' -fsS http://127.0.0.1:9090/version
curl --noproxy '*' -fsS http://127.0.0.1:9090/proxies/Flybit |
  python3 -c 'import json,sys;print(json.load(sys.stdin)["now"])'
curl -sS -L --max-time 15 -o /dev/null -w 'GitHub HTTP=%{http_code}\n' https://github.com
```

停机、重启**同一 AutoDL 实例**之后检查：

```bash
cat /tmp/autodl.sh.log
pgrep -af mihomo
curl --noproxy '*' -fsS http://127.0.0.1:9090/proxies/Flybit |
  python3 -c 'import json,sys;print(json.load(sys.stdin)["now"])'
```

当启动日志时间对应本次实例启动、进程已运行并且 API 返回新加坡 03，才能确认完整链路。仅打开终端后看到进程，可能是 `.bashrc` 的回退脚本启动的。

### 常见问题

- `ss: command not found`：极简容器没有 `ss`，可直接使用 API 检查，不必安装额外工具。
- `/init/boot/boot.sh` / `/init/supervisor/supervisor.ini` 不存在：运行进程可能已经加载随后清理的临时文件；不要据此改写或重启平台 Supervisor。
- `curl 403`：请求已到达 HTTP 服务但被拒绝；本次 `chatgpt.com` 的响应头含 `server: cloudflare`，`api.openai.com/v1/models` 未认证时返回 401；不表示整个网络断开。换节点后要分别检查目标网站连通性。
- `curl 000` / TLS reset：还未得到有效 HTTP 响应，需分别检查直连、代理、DNS 和握手错误。
- Mihomo API 返回 401：控制接口可能配置了 `secret`，请求需带 Bearer 认证。
- `GLOBAL` 显示 DIRECT：在 `mode: rule` 下由分流规则决定出口，不能仅根据 GLOBAL 当前值认定所有流量直连。
- 订阅更新导致固定节点消失：脚本将拒绝覆盖，先检查新订阅的组名/节点名，调整后再更新。

## 8. 维护与安全边界

- 当前启动钩子已通过实际重启验证，但同一容器实例的持久性**不等于**重建实例或恢复镜像时文件仍保留。
- 通过脚本更新订阅可以保留默认节点；使用外部命令直接覆盖 `config.yaml` 时会失去本地修改。
- 不要把 `/etc/mihomo/config.yaml`、包含 token 的命令行、日志、订阅 URL 提交到 GitHub。
- 控制器仅绑定 `127.0.0.1:9090`，不映射 `7890` / `9090` 到公网。
- 机场测速节点的下载速度不代表 ChatGPT 一定可访问；需要分别测试服务可用性。
