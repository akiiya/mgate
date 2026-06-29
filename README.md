# 🛰️ mgate.sh

把刷了 Debian 的随身 WiFi 变成可管理的本地网关——AP 热点、NAT fallback、Mihomo 代理、TProxy 透明代理、上级 WiFi 管理，单文件脚本，无外部依赖。

## ✨ 能力一览

- 📡 管理 `ap0` 热点，提供 SSID / DHCP / DNS
- 🌉 普通 NAT fallback：AP 客户端经 `wlan0` 出网
- 🧩 TProxy 透明代理：AP 流量无感进入 Mihomo，无需客户端配代理
- 📶 上级 WiFi 管理：通过系统网络管理器管理 `wlan0` 上级连接，不接管 `wlan0`
- 🔁 Clash / Mihomo YAML 订阅，自动识别节点国家/地区并生成代理组
- 🖥️ Web 管理后台，慢操作 job 化，不卡浏览器
- 🧭 TUI 菜单，覆盖所有主要操作
- 🔎 health / doctor / debug / JSON 状态接口
- 🛡️ 不接管 `wlan0`，不停止系统网络服务

## 📌 默认值

```text
Web 管理端口:        31888
mixed-port（代理）:  31800
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

## 🗺️ 网络路径

**普通 NAT**（默认 fallback）

```
手机 ──► ap0 ──► Debian NAT ──► wlan0 ──► 上级 WiFi ──► 公网
```

**TProxy 透明代理**（启动后）

```
手机 ──► ap0 ──► iptables mangle/TPROXY ──► mihomo :31802 ──► TPROXY-OUT ──► wlan0 ──► 公网
```

执行 `tproxy-stop` 后自动退回 NAT fallback。

## 🚀 安装

> 不建议直接 `curl | sh`，请先下载脚本确认后再执行。

**curl**

```sh
cd /tmp && rm -f mgate.sh
curl -fsSL -H "Cache-Control: no-cache" -o mgate.sh https://bit.ly/mgate-install
sh mgate.sh install
```

**wget**

```sh
cd /tmp && rm -f mgate.sh
wget -O mgate.sh https://bit.ly/mgate-install
sh mgate.sh install
```

安装完成后全局命令为 `mgate`：

```sh
mgate version      # 确认版本
mgate web-enable   # 开启 Web 管理（可选）
mgate tui          # 进入 TUI 菜单，从这里开始
```

**推荐上手顺序：** 先配订阅（`sub-set`）→ 再开 AP（`ap-start`）→ 再开 NAT 网关（`gateway-start`）→ 按需开启 TProxy（`tproxy-start`）。

## 🧭 TUI 菜单

```sh
mgate tui
```

或不带参数运行 `mgate` 直接进入。

TUI 覆盖：基础服务、订阅管理、Web 管理、AP 热点、NAT 网关、TProxy 透明代理、状态/诊断/JSON、备份/恢复。危险操作需二次确认；`tproxy-start` 需输入 `yes` 强确认。

## ⌨️ 常用命令

### ⚙️ 基础服务

```sh
mgate install          # 初始化/修复工作区
mgate self-update      # 从 GitHub 更新 mgate 脚本
mgate install-core     # 安装/更新 Mihomo 内核
mgate start            # 启动服务
mgate stop             # 停止服务
mgate restart          # 重启服务
mgate enable           # 设置开机自启
mgate disable          # 取消开机自启
mgate status
mgate logs 100
mgate doctor
mgate preflight        # 运行环境检查
mgate version
```

### 🔁 订阅管理

```sh
mgate sub-set <url>    # 设置订阅并立即拉取
mgate sub-update       # 更新订阅（失败不覆盖现有配置）
mgate sub-status       # 订阅状态
mgate sub-nodes        # 查看节点国家识别结果
mgate sub-unmatched    # 查看未识别节点
mgate sub-debug
mgate sub-clear        # 清除订阅
```

### 🔑 账号与代理连接

```sh
mgate account-password
mgate account-password set <password>
mgate proxy-info
```

代理格式：

```text
HTTP:   http://用户:密码@设备IP:31800
SOCKS5: socks5://用户:密码@设备IP:31800
```

### 📡 AP 热点

```sh
mgate ap-check         # 检查网卡支持情况
mgate ap-install-deps  # 安装 hostapd / dnsmasq
mgate ap-config        # 查看 AP 配置
mgate ap-start         # 启动热点
mgate ap-stop          # 停止热点
mgate ap-status
mgate ap-json
```

`ap-start` 只管理 `ap0`，使用 `/opt/mgate/run/ap/` 下的隔离配置，不覆盖系统 hostapd/dnsmasq。AP + managed 并发（`ap0` + `wlan0` 同时工作）取决于网卡/驱动，需真机验证。

### 🌉 NAT Gateway

```sh
mgate gateway-check
mgate gateway-start / gateway-stop
mgate gateway-status
mgate gateway-debug
mgate gateway-doctor
mgate gateway-json
```

使用 mgate 独立的 iptables chain，不影响系统其他 NAT 规则。`gateway-stop` 只清理 mgate 写入的规则。

### 🧩 TProxy 透明代理

```sh
mgate tproxy-check     # 检查内核/iptables 支持
mgate tproxy-plan      # 预览将要执行的操作（不执行）
mgate tproxy-dry-run   # 干跑模式
mgate tproxy-start     # 启动 TProxy
mgate tproxy-stop      # 停止并退回 NAT fallback
mgate tproxy-status
mgate tproxy-health
mgate tproxy-doctor
mgate tproxy-debug
mgate tproxy-json
```

`tproxy-start` 检查环境健康后添加 `tproxy-port: 31802`、ip rule、route table 100、iptables mangle chain，并保留 NAT fallback。启动失败会自动回滚。

### 🖥️ Web 管理

```sh
mgate web-enable       # 开启后台并设置开机自启
mgate web-disable      # 关闭后台
mgate web-start / web-stop / web-restart
mgate web-status
mgate web-token / web-token reset
mgate web-refresh      # 重新生成 Web 文件
```

默认访问地址：`http://设备IP:31888`

慢操作（启停、更新、订阅等）通过后台 job 执行，页面会跳转至 job 状态页，不会卡住浏览器。

### 📶 上级 WiFi 管理

通过系统现有网络管理器（优先 NetworkManager）管理 `wlan0` 的上级 WiFi 连接，不接管 `wlan0`，不破坏已有网络配置。

```sh
mgate wifi-status          # 查看连接状态、IP、信道、DNS
mgate wifi-scan            # 扫描附近 WiFi
mgate wifi-list            # 列出已保存 WiFi 配置
mgate wifi-add <ssid> [pw] # 添加 WiFi 配置（不立即连接）
mgate wifi-connect <ssid>  # 切换上级 WiFi
mgate wifi-reconnect       # 重连当前 WiFi
mgate wifi-disconnect      # 断开上级 WiFi
mgate wifi-delete <ssid>   # 删除已保存配置
mgate wifi-doctor          # 诊断上级连接
mgate wifi-json            # JSON 状态输出
```

> ⚠️ **高风险操作**：`wifi-connect` / `wifi-reconnect` / `wifi-disconnect` 可能导致 SSH 断线、AP 信道变化、AP 客户端短暂掉线、NAT/TProxy 暂时不可用。执行前会提示确认，`wifi-disconnect` 需输入 `yes` 强确认。

### 📊 JSON / 自动化接口

```sh
mgate ap-json
mgate gateway-json
mgate tproxy-json
mgate status-json          # 聚合所有模块状态
mgate wifi-json
mgate agent-snapshot       # agent 专用完整快照（推荐采集入口）
mgate capabilities-json    # 能力声明
```

只读接口，不修改 iptables / ip rule / config.yaml。所有 JSON 接口均包含 `schema_version: 1`，字段名保持稳定。

### 🤖 mgate-agent 对接

**推荐采集入口**（高频，目标 < 1s）：

```sh
mgate agent-snapshot
```

一次性输出完整只读快照：WiFi / AP / Gateway / TProxy / Web / 订阅 / Mihomo 状态，无 ping、无 sleep、无服务变更。

**能力声明**（低频，agent 启动时查询）：

```sh
mgate capabilities-json
```

告知 agent 当前版本支持哪些特性、哪些命令是只读安全的、哪些是危险操作。

**诊断采样**（低频，人工触发或问题排查）：

```sh
mgate wifi-doctor
mgate gateway-doctor
mgate tproxy-health
mgate tproxy-doctor
```

> ⚠️ **agent 边界**：agent 不应直接调用危险或交互式命令（`wifi-connect`、`tproxy-start`、`self-update`、`tui` 等）。未来如需远程控制，须单独设计带白名单、参数校验、超时、锁和审计的 action API，本版本不包含此能力。

### 💾 备份与恢复

```sh
mgate backup [名称]
mgate backups
mgate restore latest
mgate restore <备份ID>
```

恢复前自动创建 `pre-restore` 备份，误操作可回退。

## 🔐 安全边界

- **不接管** `wlan0`，不 flush 其地址
- **不停止** NetworkManager / wpa_supplicant / systemd-networkd
- **不覆盖** `/etc/hostapd/hostapd.conf` 或 `/etc/dnsmasq.conf`
- AP 使用 `/opt/mgate/run/ap/` 下的隔离配置
- NAT fallback 始终保留；TProxy 不替代它
- `tproxy-start` 失败自动回滚；`tproxy-stop` 可随时退回 NAT fallback
- Web 慢操作必须 job 化，不恢复 CGI 同步阻塞
- JSON 接口只读，不修改系统网络状态
- 不要将 Web / 代理端口暴露到公网

## 🛟 故障排查

```sh
mgate preflight        # 运行环境检查
mgate doctor           # 服务诊断
mgate ap-check         # AP 网卡检查
mgate gateway-doctor   # NAT 路径诊断
mgate tproxy-health    # TProxy 健康检查
mgate tproxy-doctor    # TProxy 完整诊断
mgate tproxy-debug     # iptables / 路由调试
mgate sub-nodes        # 节点识别结果
mgate sub-unmatched    # 未识别节点
mgate status-json      # 聚合状态
```

TProxy 流量不通时，先执行 `mgate logs 100` 查看 Mihomo 日志，确认订阅节点可用后再决定是否执行 `tproxy-stop` 退回 NAT fallback。

## ⚠️ 已知边界

- AP + managed 并发（`ap0` + `wlan0`）取决于网卡/驱动，不保证所有随身 WiFi 硬件可用
- TProxy 需内核支持 `TPROXY` 模块和 `ip_tables`
- 不引入 Python / Node / jq / 数据库 / Web 框架等外部依赖

## ✅ 发布前检查

```sh
sh -n mgate.sh
mgate preflight
mgate version
mgate status-json
git diff --check
```

## 📄 License

MIT
