# mgate.sh

把刷了 Debian 的随身 WiFi 变成可管理的本地网关。

AP 热点、NAT fallback、Mihomo 代理、TProxy 透明代理、Web 后台、TUI 菜单——单文件脚本，无外部依赖。

---

## 🧭 核心能力

| | 能力 |
|---|---|
| 📡 | 管理 `ap0` 热点，提供 AP SSID、DHCP、DNS |
| 🌉 | 普通 NAT fallback：AP 客户端经 `wlan0` 出网 |
| 🧩 | TProxy 透明代理：AP 流量进入 Mihomo，无需客户端配置代理 |
| 🖥️ | Web 管理后台（端口 31888），慢操作 job 化 |
| 🧭 | TUI 菜单：`mgate tui` |
| 🔎 | health / doctor / debug / JSON 状态接口 |
| 🛡️ | 不接管 `wlan0`，不停止系统网络服务 |

---

## 🗺️ 网络路径

**普通 NAT**（默认 fallback）

```
手机 ──► ap0 ──► Debian NAT ──► wlan0 ──► 上级 WiFi ──► 公网
```

**TProxy 透明代理**（开启后）

```
手机 ──► ap0 ──► iptables mangle/TPROXY ──► mihomo :31802 ──► TPROXY-OUT ──► wlan0 ──► 公网
```

tproxy-stop 后自动退回 NAT fallback。

---

## 🚀 快速开始

**安装**（不建议直接 `curl | sh`，请先下载确认）

```sh
cd /tmp && rm -f mgate.sh
curl -fsSL -H "Cache-Control: no-cache" -o mgate.sh https://bit.ly/mgate-install
sh mgate.sh install
```

**初次使用**

```sh
mgate version          # 确认安装
mgate tui              # 进入菜单
mgate web-enable       # 开启 Web 后台
```

**AP + 网关上线**

```sh
mgate ap-check         # 检查网卡支持情况
mgate ap-install-deps  # 安装 hostapd/dnsmasq
mgate ap-start         # 开启热点
mgate gateway-start    # 开启 NAT 出网
```

**TProxy（需要先完成上面步骤）**

```sh
mgate tproxy-check     # 检查内核/iptables 支持
mgate tproxy-plan      # 预览将要执行的操作
mgate tproxy-start     # 启动（需输入 yes 强确认）
```

> AP + managed 并发（`ap0` + `wlan0` 同时工作）取决于网卡和驱动，不保证所有硬件可用。

---

## 🖥️ Web / TUI 管理

**TUI**

```sh
mgate tui
```

提供 AP、网关、TProxy、订阅、Web、诊断、备份等子菜单。危险操作二次确认，tproxy-start 需输入 `yes`。

**Web 管理后台**

```sh
mgate web-enable
mgate web-start
```

默认访问地址：`http://设备IP:31888`

Web 慢操作（订阅更新、启停服务等）通过 job 机制后台执行，不会卡住浏览器。

---

## 📋 常用命令

### 基础服务

```sh
mgate install / self-update / update
mgate start / stop / restart / status
mgate enable / disable
mgate logs 100
mgate doctor
mgate preflight
mgate version
```

### 订阅管理

```sh
mgate sub-set <url>      # 设置订阅地址
mgate sub-update         # 更新订阅（失败不覆盖当前配置）
mgate sub-status         # 订阅状态
mgate sub-nodes          # 查看节点国家识别结果
mgate sub-unmatched      # 查看未识别节点
```

### 账号与代理连接

```sh
mgate account-password
mgate account-password set <password>
mgate proxy-info
```

代理格式：`http://用户:密码@设备IP:31800`（HTTP / SOCKS5 通用端口）

### 📡 AP 热点

```sh
mgate ap-check           # 检查网卡支持
mgate ap-install-deps    # 安装依赖
mgate ap-config          # 查看配置
mgate ap-start / ap-stop
mgate ap-status
mgate ap-json
```

### 🌉 NAT Gateway

```sh
mgate gateway-check
mgate gateway-start / gateway-stop
mgate gateway-status
mgate gateway-debug
mgate gateway-doctor
mgate gateway-json
```

### 🧩 TProxy 透明代理

```sh
mgate tproxy-check       # 检查内核支持
mgate tproxy-plan        # 预览操作（不执行）
mgate tproxy-dry-run     # 干跑模式
mgate tproxy-start       # 启动（需输入 yes）
mgate tproxy-stop        # 停止并回退到 NAT fallback
mgate tproxy-status
mgate tproxy-health
mgate tproxy-doctor
mgate tproxy-debug
mgate tproxy-json
```

### Web 管理

```sh
mgate web-enable / web-disable
mgate web-start / web-stop / web-restart
mgate web-status
mgate web-token / web-token reset
mgate web-refresh
```

---

## ⚙️ 默认值

| 参数 | 值 |
|---|---|
| Web 管理端口 | `31888` |
| mixed-port（代理） | `31800` |
| tproxy-port | `31802` |
| AP interface | `ap0` |
| upstream interface | `wlan0` |
| AP gateway | `10.88.0.1/24` |
| AP SSID | `mgate` |
| AP password | `mgate12345678` |
| TProxy mark | `0x1` |
| TProxy route table | `100` |
| TProxy chain | `MGATE_TPROXY` |
| 工作目录 | `/opt/mgate` |

---

## 🔐 安全边界

mgate 不会触碰系统核心网络配置：

- **不接管** `wlan0`，不 flush 其地址
- **不停止** NetworkManager / wpa_supplicant / systemd-networkd
- **不覆盖** `/etc/hostapd/hostapd.conf` 或 `/etc/dnsmasq.conf`
- AP 使用 `/opt/mgate/run/ap/` 下的隔离配置
- NAT fallback 始终保留，TProxy 不替代它
- `tproxy-start` 失败自动回滚；`tproxy-stop` 可随时退回 NAT fallback
- Web 慢操作必须 job 化，不恢复 CGI 同步阻塞
- JSON 接口（`*-json`）只读，不修改 iptables / ip rule / config.yaml

---

## 🛟 故障排查

优先执行这些命令收集状态：

```sh
mgate preflight          # 检查运行环境
mgate doctor             # 服务状态诊断
mgate ap-check           # AP 网卡支持检查
mgate gateway-doctor     # NAT 路径诊断
mgate tproxy-health      # TProxy 健康检查
mgate tproxy-doctor      # TProxy 完整诊断
mgate tproxy-debug       # TProxy iptables / 路由调试
mgate sub-nodes          # 订阅节点识别结果
mgate sub-unmatched      # 未识别节点
mgate status-json        # 聚合 JSON 状态
```

TProxy 节点不可用时，Mihomo 日志会出现 `dial TPROXY-OUT`、`timeout` 等错误——先确认订阅节点可用，再决定是否执行 `tproxy-stop` 退回 NAT fallback。

---

## 📊 JSON / 自动化接口

以下命令输出结构化 JSON，字段名保持稳定，适合 Web 首页和脚本调用：

```sh
mgate ap-json
mgate gateway-json
mgate tproxy-json
mgate status-json        # 聚合所有模块状态
```

---

## ⚠️ 已知边界

- AP + managed 并发（`ap0` + `wlan0`）取决于网卡/驱动，需真机验证
- TProxy 需要内核支持 `TPROXY` 模块和 `ip_tables`
- 不引入 Python / Node / jq / 数据库 / Web 框架等外部依赖
- 不保证所有随身 WiFi 硬件都可用

---

## ✅ 发布前检查

```sh
sh -n mgate.sh           # 语法检查
mgate preflight          # 环境检查
mgate version
mgate help
mgate status-json
git diff --check
```
