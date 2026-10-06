# AutoDL 上部署 Mihomo：服务器独立代理、节点持久化与开机自动启动

本文记录在 **AutoDL Ubuntu 22.04 容器实例**中部署 Mihomo 的完整过程。目标是：

- 不再依赖本地电脑长期运行 Clash；
- 不再依赖 `ssh -R` 反向隧道；
- Mihomo 在 AutoDL 实例启动后自动运行；
- 终端中的 `curl`、`wget`、`git`、`pip` 等命令自动使用代理；
- Mihomo 重启后恢复上一次手动选择的节点；
- 保留故障排查方法，便于后续重装或迁移。

> 本文命令基于一次实际配置过程整理。测试环境与订阅服务变化后，版本号、节点名称、订阅格式可能需要相应调整。

---

## 1. 最终架构

最终不再使用：

```text
AutoDL
  ↓
SSH reverse tunnel
  ↓
本地电脑 Clash
  ↓
Internet
```

而是：

```text
AutoDL
  ↓
127.0.0.1:7890
  ↓
Mihomo
  ↓
机场订阅节点
  ↓
Internet
```

本次实际使用的节点为：

```text
🇸🇬 新加坡 | 13 | 直连 *0.3
```

实测从 GitHub 下载约 21.7 MB 文件时：

```text
speed ≈ 2.62 MB/s
time  ≈ 8.7 s
```

相比服务器裸连 GitHub 时只有十几到几十 KB/s，速度明显提升。

---

## 2. 测试环境

服务器环境：

```text
Architecture : x86_64
OS           : Ubuntu 22.04.5 LTS
User         : root
Environment  : AutoDL container
```

检查命令：

```bash
uname -m
cat /etc/os-release | head -n 6
whoami
```

本次安装的 Mihomo：

```text
Mihomo Meta v1.19.32
linux amd64
```

> 后续重新部署时可以使用新的稳定版本，不要求必须使用 v1.19.32。

---

# 3. 安装 Mihomo

## 3.1 清理旧代理环境变量

如果之前使用过 SSH 反向代理，例如服务器代理指向：

```text
127.0.0.1:27890
```

先检查：

```bash
env | grep -i proxy
```

清理旧变量：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
```

再次确认：

```bash
env | grep -i proxy
```

`NO_PROXY` / `no_proxy` 可以保留。

---

## 3.2 下载 Mihomo

进入临时目录：

```bash
cd /tmp
```

本次使用：

```bash
wget -O mihomo.gz \
https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-linux-amd64-v1.19.32.gz
```

如果服务器直连 GitHub 很慢，可以临时恢复本地 Clash + SSH 反向隧道，只用于完成初始安装。

例如服务器侧临时代理端口为 `27890`：

```bash
export http_proxy=http://127.0.0.1:27890
export https_proxy=http://127.0.0.1:27890
```

下载完成后：

```bash
gunzip -f mihomo.gz
install -m 755 mihomo /usr/local/bin/mihomo
```

验证：

```bash
mihomo -v
```

示例：

```text
Mihomo Meta v1.19.32 linux amd64
```

---

# 4. 配置订阅

创建配置目录：

```bash
mkdir -p /etc/mihomo
```

## 4.1 获取正确的订阅 URL

不要把机场的 Dashboard 页面地址当作订阅地址。

错误示例：

```text
https://example.com/#/dashboard
```

需要在机场后台获取真正的 **Clash / Clash Meta / Mihomo 订阅链接**，通常形如：

```text
https://example.com/api/v1/client/subscribe?token=...
```

订阅 URL 中通常含有账户 token，**不要提交到 GitHub，也不要公开分享**。

为避免订阅地址直接进入 shell history，可以：

```bash
read -s -p "Subscription URL: " SUB_URL; echo
```

粘贴真实订阅地址后下载：

```bash
curl -fL -A "clash.meta" "$SUB_URL" \
  -o /etc/mihomo/config.yaml \
  -w '\nHTTP=%{http_code} TYPE=%{content_type} SIZE=%{size_download}\n'
```

检查：

```bash
ls -lh /etc/mihomo/config.yaml
```

正常配置通常至少有几 KB，不应只有十几或几十字节。

---

# 5. 下载 Country.mmdb

第一次校验配置时，如果出现：

```text
Can't find MMDB, start download
Can't initialize GEOIP: can't download MMDB: context deadline exceeded
```

可手动下载：

```bash
cd /etc/mihomo
curl -fL --retry 3 \
  https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb \
  -o Country.mmdb
```

检查：

```bash
ls -lh /etc/mihomo/Country.mmdb
```

本次实际下载约：

```text
7.4M
```

---

# 6. 校验 Mihomo 配置

执行：

```bash
mihomo -t -d /etc/mihomo
```

成功时：

```text
configuration file /etc/mihomo/config.yaml test is successful
```

只有配置校验成功后再正式启动。

---

# 7. 启动 Mihomo

后台启动：

```bash
nohup mihomo -d /etc/mihomo > /tmp/mihomo.log 2>&1 &
```

检查进程：

```bash
pgrep -af mihomo
```

检查日志：

```bash
tail -n 50 /tmp/mihomo.log
```

本次订阅配置中：

```text
mixed-port: 7890
external-controller: 127.0.0.1:9090
```

因此：

- `127.0.0.1:7890`：HTTP / SOCKS mixed proxy；
- `127.0.0.1:9090`：Mihomo REST API。

建议不要把 `7890` 或 `9090` 映射到公网。

---

# 8. 查看并选择代理节点

## 8.1 查看策略组

执行：

```bash
curl -s http://127.0.0.1:9090/proxies | \
python3 -c 'import sys,json; p=json.load(sys.stdin)["proxies"]; [print(k, "|", v.get("type"), "| 当前:", v.get("now","")) for k,v in p.items() if v.get("type") in {"Selector","URLTest","Fallback","LoadBalance"}]'
```

本次主策略组为：

```text
FlyBit
```

## 8.2 列出 FlyBit 可选节点

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; d=json.load(sys.stdin); print("当前:",d.get("now")); print("\n可选节点:"); [print(i,x) for i,x in enumerate(d.get("all",[]),1)]'
```

订阅中可能混入并非真实节点的提示项，例如：

```text
剩余：xxx GB，到期：长期有效
邀请返佣...
有问题重新从网站获取订阅
请关注网站首页的公告信息
```

不要选择这些信息项。

## 8.3 选择新加坡节点

本次实测使用：

```text
🇸🇬 新加坡 | 13 | 直连 *0.3
```

切换：

```bash
curl -X PUT http://127.0.0.1:9090/proxies/FlyBit \
  -H 'Content-Type: application/json' \
  -d '{"name":"🇸🇬 新加坡 | 13 | 直连 *0.3"}'
```

检查：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print("当前节点:",json.load(sys.stdin)["now"])'
```

---

# 9. 保存节点选择

如果希望 Mihomo 重启后继续使用上次手工选择的节点，需要：

```yaml
profile:
  store-selected: true
```

先检查是否已存在：

```bash
grep -A 3 '^profile:' /etc/mihomo/config.yaml
```

如果没有，可以先备份：

```bash
cp /etc/mihomo/config.yaml /etc/mihomo/config.yaml.bak
```

然后追加：

```bash
printf '\nprofile:\n  store-selected: true\n' >> /etc/mihomo/config.yaml
```

再次校验：

```bash
mihomo -t -d /etc/mihomo
```

> 如果配置文件本身已经有 `profile:`，不要追加第二个同名 YAML key，应修改已有的 `profile` 节点。

重新启动 Mihomo 后，检查节点是否仍为新加坡节点：

```bash
pkill -x mihomo
/root/start_mihomo.sh
```

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print("重启后节点:",json.load(sys.stdin)["now"])'
```

---

# 10. 配置终端自动使用代理

Mihomo 启动本身并不会强制所有应用自动走代理。

对于 `curl`、`wget`、`git`、`pip` 等常见命令，可以通过 shell 环境变量使用 Mihomo。

在 `/root/.bashrc` 中加入：

```bash
# Mihomo proxy
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890

export HTTP_PROXY=http://127.0.0.1:7890
export HTTPS_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost
```

立即加载：

```bash
source /root/.bashrc
```

检查：

```bash
env | grep -i proxy
```

测试时不再手工指定 `-x`：

```bash
curl --max-time 15 https://api.ipify.org
echo
```

能够直接返回代理出口公网 IP，说明当前 shell 已自动使用 Mihomo。

---

# 11. 创建 Mihomo 启动脚本

创建：

```bash
cat > /root/start_mihomo.sh <<'EOF'
#!/bin/bash
if ! pgrep -x mihomo >/dev/null; then
    nohup /usr/local/bin/mihomo -d /etc/mihomo >/tmp/mihomo.log 2>&1 &
fi
EOF
```

添加执行权限：

```bash
chmod +x /root/start_mihomo.sh
```

这个脚本具有幂等性：

- Mihomo 已运行时，不重复启动；
- Mihomo 未运行时，后台启动。

手动测试：

```bash
/root/start_mihomo.sh
pgrep -af mihomo
```

---

# 12. AutoDL 实例开机自动启动 Mihomo

这是本次配置中比较特殊的一部分。

## 12.1 确认 AutoDL PID 1

检查：

```bash
ps -p 1 -o pid,comm,args
```

本次实例显示：

```text
PID  COMMAND
1    bash    bash /init/boot/boot.sh
```

因此该 AutoDL 容器不是标准 systemd 主机。

不要直接依赖：

```bash
systemctl enable mihomo
```

---

## 12.2 检查 AutoDL 启动流程

AutoDL 的 `/init/boot/boot.sh` 在实例启动后会被删除，但 PID 1 的 bash 仍持有该脚本文件描述符。

检查：

```bash
ls -l /proc/1/fd | tail -n 20
```

本次可见：

```text
255 -> /init/boot/boot.sh (deleted)
```

读取脚本中的关键启动逻辑：

```bash
cat /proc/1/fd/255 | \
grep -nE 'rc.local|bashrc|profile|startup|start|supervisor|/root|source|run-parts'
```

实际发现：

```text
source /etc/profile
```

而且发生在 AutoDL 后续启动 Supervisor 之前。

因此可以利用 `/etc/profile.d/` 作为实例启动钩子。

---

## 12.3 创建 AutoDL 开机启动钩子

创建：

```bash
cat > /etc/profile.d/00-mihomo-start.sh <<'EOF'
#!/bin/bash

if [ -x /root/start_mihomo.sh ]; then
    /root/start_mihomo.sh
fi
EOF
```

添加权限：

```bash
chmod +x /etc/profile.d/00-mihomo-start.sh
```

最终启动链路：

```text
AutoDL instance boot
        ↓
/init/boot/boot.sh
        ↓
source /etc/profile
        ↓
/etc/profile.d/00-mihomo-start.sh
        ↓
/root/start_mihomo.sh
        ↓
Mihomo starts automatically
```

这不是“打开终端后才启动”，而是在当前这套 AutoDL 镜像的实例启动流程中自动运行。

> 注意：这是根据本次实际 AutoDL 容器的 `boot.sh` 行为确认的。如果以后换了镜像、AutoDL 修改了启动流程，建议重新检查 `ps -p 1` 和启动脚本。

---

# 13. 为什么代理变量不放到 `/etc/profile.d/00-mihomo-start.sh`

AutoDL 启动流程是：

```text
source /etc/profile
↓
继续启动 AutoDL 自身系统服务
```

如果在这个阶段直接全局：

```bash
export http_proxy=...
export https_proxy=...
```

后续 AutoDL 自身服务可能继承这些代理环境变量。

因此本次采用分层：

### 开机层

`/etc/profile.d/00-mihomo-start.sh`

只负责：

```text
启动 Mihomo
```

### 用户 shell 层

`/root/.bashrc`

负责：

```text
http_proxy
https_proxy
all_proxy
```

这样 AutoDL 系统服务不需要强制走代理，而用户终端可以自动走 Mihomo。

---

# 14. 开机自动启动验证

关闭 AutoDL 实例，然后重新启动。

进入实例后：

```bash
pgrep -af mihomo
```

本次重新开机后实际观察到：

```text
13 /usr/local/bin/mihomo -d /etc/mihomo
```

PID 很小，说明 Mihomo 在实例启动的早期阶段已经运行。

检查节点：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print("当前节点:",json.load(sys.stdin)["now"])'
```

结果：

```text
当前节点: 🇸🇬 新加坡 | 13 | 直连 *0.3
```

检查代理变量：

```bash
env | grep -i proxy
```

检查实际联网：

```bash
curl --max-time 15 https://api.ipify.org
echo
```

能够正常返回代理公网出口 IP，说明整套自动化生效。

---

# 15. 日常使用

正常情况下，实例启动后不需要手工运行：

```bash
mihomo -d /etc/mihomo
```

也不需要重复：

```bash
export http_proxy=...
export https_proxy=...
```

更不需要再建立：

```text
ssh -R 27890 ...
```

常用检查：

```bash
pgrep -af mihomo
```

```bash
tail -n 50 /tmp/mihomo.log
```

```bash
curl --max-time 15 https://api.ipify.org
echo
```

查看当前节点：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print(json.load(sys.stdin)["now"])'
```

---

# 16. 临时关闭当前终端代理

只关闭当前 shell 的代理环境变量：

```bash
unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
```

这不会停止 Mihomo。

重新开启当前终端代理：

```bash
source /root/.bashrc
```

如果要停止 Mihomo：

```bash
pkill -x mihomo
```

重新启动：

```bash
/root/start_mihomo.sh
```

---

# 17. 订阅更新注意事项

本次 `config.yaml` 是通过订阅直接下载的：

```text
/etc/mihomo/config.yaml
```

后续如果重新执行：

```bash
curl ... -o /etc/mihomo/config.yaml
```

会覆盖本地修改。

因此本地手工加入的：

```yaml
profile:
  store-selected: true
```

可能被新的订阅配置覆盖。

更新订阅后至少应重新检查：

```bash
grep -A 3 '^profile:' /etc/mihomo/config.yaml
mihomo -t -d /etc/mihomo
```

同时再次确认：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print(json.load(sys.stdin)["now"])'
```

---

# 18. 安全注意事项

1. **不要把订阅 URL 或 token 提交到 GitHub。**
2. 不要把机场账户信息写入公开仓库。
3. `9090` REST API 建议只监听 localhost。
4. `7890` 不需要通过 AutoDL 端口映射暴露到公网。
5. 如果订阅配置启用了 LAN 访问，应确认这符合自己的安全需求。
6. 上传配置文件到 GitHub 前，应先搜索敏感字段：

```bash
grep -nEi 'token|password|uuid|secret|server:' /etc/mihomo/config.yaml
```

正常情况下，**不要上传 `/etc/mihomo/config.yaml` 本身**。

---

# 遇到的问题与解决方法

## 1. `wget` 一直连接 `127.0.0.1:27890` 并提示 `Connection refused`

### 现象

下载 Mihomo 时：

```text
Connecting to 127.0.0.1:27890... failed: Connection refused.
```

### 原因

服务器仍然保留以前 SSH 反向代理使用的：

```bash
http_proxy=http://127.0.0.1:27890
https_proxy=http://127.0.0.1:27890
```

但本地 SSH 隧道已经关闭，因此端口没有服务。

### 解决

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
```

再：

```bash
env | grep -i proxy
```

确认旧代理变量已经清除。

---

## 2. AutoDL 直接从 GitHub 下载 Mihomo 很慢

### 现象

GitHub 约：

```text
33 KB/s
```

SourceForge 镜像甚至只有：

```text
15.5 KB/s
```

### 原因

主要是当前 AutoDL 实例到海外站点的网络链路慢，不是 Mihomo 文件本身的问题。

### 解决

初始安装阶段临时使用原来的：

```text
AutoDL
↓
127.0.0.1:27890
↓
SSH reverse tunnel
↓
本地 Clash
```

把 Mihomo 下载并配置完成。

之后服务器改为自己的 Mihomo，不再依赖本地隧道。

---

## 3. 订阅配置只有 21 字节，Mihomo 报 YAML 错误

### 现象

```text
100    21
```

随后：

```text
yaml: unmarshal errors:
line 1: cannot unmarshal !!str ... into config.RawConfig
```

### 原因

最初使用的不是实际 Clash/Mihomo 订阅 URL，而是机场 Dashboard 页面或返回普通错误文本的地址。

### 解决

从机场后台获取真正的 Clash / Mihomo 订阅链接，并使用：

```bash
curl -fL -A "clash.meta" "$SUB_URL" \
  -o /etc/mihomo/config.yaml \
  -w '\nHTTP=%{http_code} TYPE=%{content_type} SIZE=%{size_download}\n'
```

通过 `SIZE` 快速判断是否拿到了正常配置。

---

## 4. Mihomo 配置测试时自动下载 MMDB 超时

### 现象

```text
Can't find MMDB, start download
Can't initialize GEOIP: can't download MMDB: context deadline exceeded
```

### 原因

Mihomo 需要 GeoIP 数据库，但服务器当时无法及时自动下载。

### 解决

手工下载：

```bash
curl -fL --retry 3 \
  https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb \
  -o /etc/mihomo/Country.mmdb
```

之后：

```bash
mihomo -t -d /etc/mihomo
```

配置校验成功。

---

## 5. FlyBit 默认选中了“剩余流量”而不是真实节点

### 现象

查询：

```text
FlyBit | Selector | 当前: 剩余：104.69 GB，到期：长期有效
```

### 原因

机场把套餐流量、公告等信息作为“伪节点”放进订阅列表。

### 解决

先列出所有节点：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; d=json.load(sys.stdin); [print(i,x) for i,x in enumerate(d.get("all",[]),1)]'
```

然后手工选择真实节点：

```bash
curl -X PUT http://127.0.0.1:9090/proxies/FlyBit \
  -H 'Content-Type: application/json' \
  -d '{"name":"🇸🇬 新加坡 | 13 | 直连 *0.3"}'
```

---

## 6. 需要确认服务器是否真的脱离 Mac SSH 隧道

### 处理方式

在启动 Mihomo 前先清除：

```bash
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
```

Mihomo 独立启动后：

```bash
curl -x http://127.0.0.1:7890 \
  --max-time 15 https://api.ipify.org
```

确认成功后关闭 Mac 上的 `ssh -R`。

再重复测试，如果依然成功，就确认：

```text
AutoDL → Mihomo → subscription node → Internet
```

已经不再经过本地电脑。

---

## 7. 手工选择节点后，担心重启恢复默认节点

### 解决

在 Mihomo 配置中加入：

```yaml
profile:
  store-selected: true
```

再手工选择节点，并重启验证。

最终重启后仍恢复：

```text
🇸🇬 新加坡 | 13 | 直连 *0.3
```

---

## 8. `systemctl` 存在，但 AutoDL 并不是 systemd 主机

### 现象

虽然：

```bash
command -v systemctl
```

能看到：

```text
/usr/bin/systemctl
```

但：

```bash
ps -p 1 -o pid,comm,args
```

显示：

```text
1 bash bash /init/boot/boot.sh
```

### 原因

容器 PID 1 是 AutoDL 自己的启动脚本，不是 `systemd`。

### 结论

不能因为 `systemctl` 命令存在，就直接按普通 Ubuntu 主机方式配置：

```bash
systemctl enable mihomo
```

---

## 9. AutoDL 有 Supervisor，但无法直接用 `supervisorctl`

### 现象

发现：

```text
/bin/supervisord -c /init/supervisor/supervisor.ini
```

但：

```bash
supervisorctl status
```

返回：

```text
http://localhost:9001 refused connection
```

进一步指定配置：

```bash
supervisorctl -c /init/supervisor/supervisor.ini status
```

却提示配置文件不存在。

### 排查

检查 mount namespace：

```bash
readlink /proc/$$/ns/mnt
readlink /proc/<supervisord-pid>/ns/mnt
```

二者相同。

但：

```text
/init/supervisor/supervisor.ini
```

确实已经不存在。

### 原因

AutoDL 启动期间生成并加载 Supervisor 配置，之后清理了临时启动目录。Supervisor 已经把配置读入内存，所以进程仍可运行。

### 解决

不修改 AutoDL 内部 Supervisor 配置，转而寻找官方启动流程中的持久化钩子。

---

## 10. `/init/boot/boot.sh` 已删除，如何确认 AutoDL 开机逻辑

### 现象

PID 1 显示：

```text
bash /init/boot/boot.sh
```

但：

```bash
bash /init/boot/boot.sh
```

提示文件不存在。

### 解决

查看 PID 1 打开的文件描述符：

```bash
ls -l /proc/1/fd
```

发现：

```text
255 -> /init/boot/boot.sh (deleted)
```

因此仍可读取：

```bash
cat /proc/1/fd/255
```

并从中确认 AutoDL 启动阶段执行：

```bash
source /etc/profile
```

最终据此选择：

```text
/etc/profile.d/00-mihomo-start.sh
```

作为开机启动入口。

---

## 11. `/tmp/mihomo_start.log` 不存在

### 现象

```bash
cat /tmp/mihomo_start.log
```

返回：

```text
No such file or directory
```

### 原因

实际使用的 `/root/start_mihomo.sh` 是：

```bash
#!/bin/bash
if ! pgrep -x mihomo >/dev/null; then
    nohup /usr/local/bin/mihomo -d /etc/mihomo >/tmp/mihomo.log 2>&1 &
fi
```

脚本只写：

```text
/tmp/mihomo.log
```

并没有创建 `mihomo_start.log`。

### 解决

查看：

```bash
tail -n 50 /tmp/mihomo.log
```

即可。

---

# 19. 最终状态检查清单

实例重启后：

```bash
pgrep -af mihomo
```

应看到：

```text
/usr/local/bin/mihomo -d /etc/mihomo
```

当前节点：

```bash
curl -s http://127.0.0.1:9090/proxies/FlyBit | \
python3 -c 'import sys,json; print(json.load(sys.stdin)["now"])'
```

应为预期节点。

代理变量：

```bash
env | grep -i proxy
```

应包含：

```text
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
all_proxy=socks5://127.0.0.1:7890
```

实际联网：

```bash
curl --max-time 15 https://api.ipify.org
echo
```

GitHub 测速：

```bash
curl -x http://127.0.0.1:7890 -L -o /dev/null \
  -w 'speed=%{speed_download} bytes/s time=%{time_total}s\n' \
  https://github.com/MetaCubeX/mihomo/releases/download/v1.19.32/mihomo-linux-amd64-v1.19.32.gz
```

满足以上条件后，服务器已实现：

```text
AutoDL 开机
→ Mihomo 自动启动
→ 节点选择恢复
→ shell 自动加载代理变量
→ wget / curl / git / pip 可直接使用代理
→ 不再依赖本地 Clash 和 SSH reverse tunnel
```
