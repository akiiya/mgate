# mgate.sh

`mgate.sh` 是面向刷 Debian 的随身 WiFi / 小型 Linux 设备的本地网关管理脚本。安装后全局命令为 `mgate`，默认工作目录为 `/opt/mgate`。

项目坚持单文件主入口：核心逻辑、Web CGI、systemd service、配置模板等都由 `mgate.sh` 生成或管理。当前定位已经不只是本地代理脚本，而是本机 AP、NAT fallback、TProxy 透明代理和 Mihomo 管理的轻量网关工具。

## 当前能力

- Mihomo core 安装、更新、启动、停止、状态、日志、诊断。
- 默认 `mixed-port` 单端口代理，支持 HTTP / SOCKS5 认证。
- Clash / Mihomo YAML 订阅更新、失败不覆盖当前可用配置。
- 根据订阅节点名识别国家/地区并生成代理组。
- `sub-nodes` / `sub-unmatched` 查看节点识别结果和未匹配节点。
- TUI 菜单管理常用操作。
- Web 管理后台，慢操作通过后台 job 执行。
- Web 连接信息基于 `HTTP_HOST` 动态展示。
- AP 热点最小闭环：mgate 只管理 `ap0`。
- 普通 NAT gateway fallback：`ap0 -> wlan0` IPv4 NAT 出网。
- TProxy 透明代理闭环：AP 客户端流量可进入 Mihomo `tproxy-port`。
- `tproxy-health` / `tproxy-doctor` / `tproxy-debug` 排障命令。
- `ap-json` / `gateway-json` / `tproxy-json` / `status-json` 只读 JSON 状态输出。
- `preflight` 和 Git 行尾策略防止 CRLF 破坏 `/bin/sh` 解析。

## 典型网络路径

普通 NAT fallback：

```text
手机 -> ap0 -> Debian IPv4 NAT -> wlan0 -> 上级 WiFi -> 公网
```

TProxy 透明代理：

```text
手机 -> ap0 -> iptables mangle/TPROXY -> mihomo tproxy-port 31802 -> TPROXY-OUT -> wlan0 -> 公网
```

## 默认值

```text
Web 管理端口:        31888
mixed-port:          31800
tproxy-port:         31802
AP interface:        ap0
upstream interface:  wlan0
AP gateway:          10.88.0.1/24
AP SSID:             mgate
AP password:         mgate12345678
TProxy mark:         0x1
TProxy route table:  100
TProxy chain:        MGATE_TPROXY
工作目录:            /opt/mgate
```

## 安装

不建议使用 `curl | sh`。建议先下载脚本，再执行安装。

```sh
cd /tmp
rm -f mgate.sh
curl -fsSL -H "Cache-Control: no-cache" -o mgate.sh https://bit.ly/mgate-install
sh mgate.sh install
```

如果只有 `wget`：

```sh
cd /tmp
rm -f mgate.sh
wget -O mgate.sh https://bit.ly/mgate-install
sh mgate.sh install
```

安装完成后：

```sh
mgate version
mgate status
```

## TUI 菜单

运行下面任一命令进入 TUI：

```sh
mgate
mgate tui
```

TUI 提供基础服务、订阅管理、Web 管理、AP 热点管理、网关 / NAT 管理、TProxy 透明代理、状态 / 诊断 / JSON、备份 / 恢复等入口。危险操作会二次确认；启动 TProxy 需要输入 `yes` 强确认。

## 常用命令

### 基础服务

```sh
mgate install
mgate self-update
mgate update
mgate install-core
mgate start
mgate stop
mgate restart
mgate status
mgate enable
mgate disable
mgate test
mgate doctor
mgate logs 100
mgate version
mgate preflight
```

### Web 管理

```sh
mgate web-enable
mgate web-disable
mgate web-start
mgate web-stop
mgate web-restart
mgate web-status
mgate web-token
mgate web-token reset
mgate web-refresh
```

默认访问地址：

```text
http://设备IP:31888
```

Web 慢操作会进入 job 页面，不应让浏览器长时间等待 CGI 同步执行。

### 订阅管理

```sh
mgate sub-set <url>
mgate sub-update
mgate sub-status
mgate sub-debug
mgate sub-clear
mgate sub-nodes
mgate sub-unmatched
```

订阅更新失败时不会覆盖当前可用配置。`sub-nodes` 用于查看节点识别成了哪些国家/地区，`sub-unmatched` 用于查看未识别节点。

### 账号与连接

```sh
mgate account-password
mgate account-password set <password>
mgate proxy-info
```

默认代理端口：

```text
HTTP:   http://用户:密码@设备IP:31800
SOCKS5: socks5://用户:密码@设备IP:31800
```

Web 页面中的设备地址优先根据当前请求的 `HTTP_HOST` 展示。

### AP 热点

```sh
mgate ap-check
mgate ap-install-deps
mgate ap-config
mgate ap-status
mgate ap-start
mgate ap-stop
mgate ap-json
```

`ap-start` 只管理 `ap0`，使用 `/opt/mgate/run/ap/` 下的隔离 hostapd/dnsmasq 配置。本项目不承诺所有无线网卡都支持 managed + AP 并发；需要真机验证。

### NAT gateway fallback

```sh
mgate gateway-check
mgate gateway-start
mgate gateway-stop
mgate gateway-status
mgate gateway-debug
mgate gateway-doctor
mgate gateway-json
```

NAT fallback 使用 mgate 自己的 iptables chain，不删除系统其它 NAT 规则。`gateway-stop` 只清理 mgate 写入的 NAT gateway 规则。

### TProxy 透明代理

```sh
mgate tproxy-check
mgate tproxy-status
mgate tproxy-plan
mgate tproxy-dry-run
mgate tproxy-start
mgate tproxy-stop
mgate tproxy-health
mgate tproxy-doctor
mgate tproxy-debug
mgate tproxy-json
```

`tproxy-start` 会在确认环境健康后添加 Mihomo `tproxy-port: 31802`、ip rule、route table 100、iptables mangle chain，并保留 NAT fallback。失败会尝试自动回滚。`tproxy-stop` 清理 mgate TProxy 规则并回到 NAT fallback。

### JSON 状态输出

```sh
mgate ap-json
mgate gateway-json
mgate tproxy-json
mgate status-json
```

这些命令是只读接口，供 Web 首页和未来安全调用方使用。字段名应保持稳定。

## 安全边界

mgate 的网络边界是保守的：

- 不接管 `wlan0`。
- 不重配或 flush `wlan0` 地址。
- 不停止 NetworkManager。
- 不停止 `wpa_supplicant`。
- 不停止 `systemd-networkd`。
- 不覆盖 `/etc/hostapd/hostapd.conf`。
- 不覆盖 `/etc/dnsmasq.conf`。
- AP 使用 `/opt/mgate/run/ap/` 下的隔离配置。
- NAT fallback 保留，TProxy 不删除普通 NAT 能力。
- TProxy 启动失败必须回滚，`tproxy-stop` 可回到 NAT fallback。
- 不把 mgate-agent / mgate-cloud 的实现混入本仓库。

## 真机验收建议

### AP

```sh
mgate ap-check
mgate ap-start
mgate ap-status
ip addr show ap0
mgate ap-stop
```

手机应能搜索到默认 SSID `mgate` 并获得 `10.88.0.x` 地址。

### NAT gateway

```sh
mgate ap-start
mgate gateway-start
mgate gateway-status
mgate gateway-doctor
```

手机连接 AP 后应能通过普通 NAT 出网。

### TProxy

```sh
mgate tproxy-check
mgate tproxy-plan
mgate tproxy-start
mgate tproxy-status
mgate tproxy-health
mgate tproxy-doctor
iptables -t mangle -L MGATE_TPROXY -n -v
mgate tproxy-stop
mgate gateway-doctor
```

开启 TProxy 后，AP 客户端流量应进入 Mihomo；停止 TProxy 后应回到 NAT fallback。

### Web

```sh
mgate web-refresh
sh -n /opt/mgate/web/cgi-bin/mgate.cgi
mgate web-restart
mgate web-status
```

浏览器访问：

```text
http://设备IP:31888
```

首页应显示 AP / gateway / NAT fallback / TProxy / final health 摘要；诊断页面应通过 job 页面展示，不应卡住浏览器。

### JSON

```sh
mgate ap-json
mgate gateway-json
mgate tproxy-json
mgate status-json
```

执行前后不应改变 iptables、ip rule、ip route 或 `config.yaml`。

## 故障排查

优先使用这些命令收集状态：

```sh
mgate preflight
mgate doctor
mgate sub-nodes
mgate sub-unmatched
mgate gateway-doctor
mgate gateway-debug
mgate tproxy-health
mgate tproxy-doctor
mgate tproxy-debug
mgate status-json
```

如果 TProxy 节点不可用，Mihomo 日志中可能出现 `dial TPROXY-OUT`、`connect error`、`timeout` 等错误。此时先确认订阅节点健康，再决定是否停止 TProxy 回到 NAT fallback。