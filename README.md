# 🚀 mgate

`mgate` 是一个面向 **随身 WiFi / OpenWrt / 嵌入式 Linux** 的轻量级 Mihomo 网关管理脚本。

它可以自动安装 Mihomo core，并提供统一命令管理代理入口。
默认使用 **Mixed 代理端口**，同一个端口同时支持 HTTP 和 SOCKS5，并支持根据用户名自动分流到不同国家或地区的代理节点。

## ✨ 特性

* 📶 适合随身 WiFi、OpenWrt、嵌入式 Linux
* 🧠 自动识别 CPU 架构
* ⬇️ 自动下载并安装 Mihomo 内核
* 🌐 默认使用 Mixed 端口，同时支持 HTTP / SOCKS5
* 👥 多用户认证
* 🧭 根据用户名自动分流到不同代理组
* 🔁 支持 Clash / Mihomo YAML 订阅
* 🗺️ 支持自动识别订阅节点国家/地区
* 🔐 支持统一设置代理账号默认密码
* 🧭 支持 TUI 菜单管理
* 🌍 支持轻量级 Web 管理页面
* 🩺 支持系统诊断
* 💾 支持配置备份与恢复
* 🔁 支持从 GitHub 自更新 mgate 管理脚本
* 📁 所有文件都存放在 `/opt/mgate`
* 🧹 支持完整卸载

## 📌 默认设计

```text
Mixed 代理端口：31800
Web 管理端口：31888

订阅账号默认密码：
12345678

默认规则：
用户名 JP -> JP 代理组
用户名 US -> US 代理组
用户名 DE -> DE 代理组
其他未匹配流量 -> REJECT
```

Mixed 端口同时支持：

```text
HTTP  代理：http://用户:密码@设备IP:31800
SOCKS5代理：socks5://用户:密码@设备IP:31800
```

## 🚀 安装

> 不建议使用 `curl | sh`。请先下载 `mgate.sh`，再执行安装。

### curl

```sh
cd /tmp && rm -f mgate.sh && curl -fsSL -H "Cache-Control: no-cache" -o mgate.sh https://bit.ly/mgate-install && sh mgate.sh install
```

### wget

```sh
cd /tmp && rm -f mgate.sh && wget -O mgate.sh https://bit.ly/mgate-install && sh mgate.sh install
```

安装完成后，全局命令为：

```sh
mgate
```

查看状态：

```sh
mgate status
```

## 🧭 TUI 菜单

不带参数运行：

```sh
mgate
```

会进入交互式菜单，可进行安装、更新、服务管理、配置管理、订阅管理、账号管理、Web 管理、诊断、备份恢复和卸载等操作。

## ⌨️ 常用命令

### 安装与更新

```sh
mgate install          # 初始化/修复 mgate 工作区
mgate self-update      # 从 GitHub 更新 mgate 管理脚本
mgate update           # self-update 的别名
mgate install-core     # 安装/更新 Mihomo 内核
```

> `mgate install` 用于初始化或修复本地工作区，不会从 GitHub 拉取最新 `mgate.sh`。
> 如需更新管理脚本，请使用 `mgate self-update` 或 `mgate update`。

### 服务管理

```sh
mgate start            # 启动服务
mgate stop             # 停止服务
mgate restart          # 重启服务
mgate status           # 查看服务状态
mgate enable           # 设置开机启动
mgate disable          # 关闭开机启动
```

### 配置与诊断

```sh
mgate config           # 查看配置
mgate edit             # 编辑配置
mgate test             # 测试配置
mgate logs             # 查看日志
mgate doctor           # 系统诊断
mgate version          # 查看版本
```

### 账号与连接

```sh
mgate account-password             # 查看代理账号默认密码
mgate account-password set <密码>  # 修改代理账号默认密码

mgate passwd                       # account-password 的别名
mgate passwd set <密码>            # 修改代理账号默认密码

mgate proxy-info                   # 查看代理连接信息
```

默认代理账号密码为：

```text
12345678
```

修改默认密码后，如果已经启用订阅模式，`mgate` 会重新生成账号和配置。

### 备份与恢复

```sh
mgate backup [名称]          # 创建备份
mgate backups               # 查看备份列表
mgate restore latest        # 恢复最新备份
mgate restore <备份ID>       # 恢复指定备份
```

备份内容包括：

```text
/opt/mgate/config/
/opt/mgate/data/
/opt/mgate/service/
```

恢复前会自动创建一份 `pre-restore` 备份，避免误操作后无法回退。

## 🔁 订阅管理

`mgate` 支持 Clash / Mihomo YAML 格式订阅。

### 设置或替换订阅

```sh
mgate sub-set "你的订阅链接"
```

该命令会：

```text
1. 保存新的订阅链接
2. 立即拉取订阅
3. 自动识别节点国家/地区
4. 自动生成代理账号
5. 自动生成 proxy-provider / proxy-groups / rules
6. 测试配置
7. 测试通过后重启服务
```

如果再次执行 `sub-set`，会替换原订阅链接，并立即重新生成最新账号和配置。

### 更新订阅

```sh
mgate sub-update
```

会使用已保存的订阅链接重新拉取最新节点，并更新账号组和节点组。

### 查看订阅状态

```sh
mgate sub-status
```

会显示：

```text
订阅链接
上次更新时间
识别到的国家/地区
自动生成的账号
未识别节点数量
```

### 清除订阅

```sh
mgate sub-clear
```

会清除订阅链接、订阅缓存和自动账号。

## 🌍 Web 管理

`mgate` 支持轻量级 Web 管理页面，基于设备自带的 `busybox httpd` / `httpd` 实现，不依赖 Node.js、Python、PHP 或数据库。

Web 管理默认关闭，需要手动开启：

```sh
mgate web-enable
```

开启后，在同一 WiFi / 局域网内访问：

```text
http://设备IP:31888
```

例如：

```text
http://192.168.8.1:31888
```

首次开启时会生成 Web Token，登录 Web 页面时需要输入该 Token。

### Web 管理命令

```sh
mgate web-enable       # 开启 Web 管理
mgate web-disable      # 关闭 Web 管理并关闭开机自启
mgate web-start        # 启动 Web 管理服务
mgate web-stop         # 停止 Web 管理服务
mgate web-restart      # 重启 Web 管理服务
mgate web-status       # 查看 Web 管理状态

mgate web-token        # 查看 Web Token
mgate web-token reset  # 重置 Web Token
mgate web-refresh      # 重新生成 Web 页面文件
```

### Web 页面支持

当前 Web 页面支持：

```text
查看状态
查看版本
启动服务
停止服务
重启服务
测试配置
查看日志
查看配置
查看代理连接信息
查看 / 修改代理账号默认密码
查看 / 重置 Web Token
订阅状态
设置订阅
更新订阅
清除订阅
创建备份
系统诊断
自更新 mgate 管理脚本
关闭 Web 管理
```

### Web 文件位置

Web 文件由 `mgate.sh` 动态生成，位于：

```text
/opt/mgate/web/
├── index.html
├── favicon.svg
├── favicon.ico
├── static/
│   └── style.css
└── cgi-bin/
    └── mgate.cgi
```

如果更新了 mgate 管理脚本，并且想刷新 Web 页面文件，可以执行：

```sh
mgate web-refresh
mgate web-restart
```

> Web 管理只建议在局域网内使用，不要暴露到公网。

## 🔌 客户端连接

假设设备 IP 是：

```text
192.168.8.1
```

如果账号是：

```text
JP:12345678
```

HTTP 代理：

```text
http://JP:12345678@192.168.8.1:31800
```

SOCKS5 代理：

```text
socks5://JP:12345678@192.168.8.1:31800
```

也可以直接查看当前连接信息：

```sh
mgate proxy-info
```

测试出口：

```sh
curl -x http://JP:12345678@127.0.0.1:31800 https://ipinfo.io/country
curl -x socks5h://JP:12345678@127.0.0.1:31800 https://ipinfo.io/country
```

## 📂 工作目录

```text
/opt/mgate/
├── mgate                    # 安装后的管理脚本
├── bin/
│   └── mihomo               # Mihomo 内核
├── config/
│   ├── config.yaml          # 主配置文件
│   ├── config.example.yaml  # 示例配置
│   └── providers/
│       └── sub.yaml         # 订阅 provider
├── service/
├── web/
├── logs/
├── run/
├── backups/
├── tmp/
└── data/
```

仓库脚本文件：

```text
mgate.sh
```

安装后全局命令：

```text
/usr/bin/mgate -> /opt/mgate/mgate
```

服务名：

```text
mgate
```

Web 服务名：

```text
mgate-web
```

## 🧩 配置

主配置文件：

```text
/opt/mgate/config/config.yaml
```

编辑配置：

```sh
mgate edit
```

测试配置：

```sh
mgate test
```

修改配置后重启：

```sh
mgate restart
```

默认配置核心结构：

```yaml
authentication:
  - "JP:12345678"
  - "US:12345678"
  - "DE:12345678"

listeners:
  - name: mixed-users
    type: mixed
    listen: 0.0.0.0
    port: 31800
    udp: true

rules:
  - IN-USER,JP,JP
  - IN-USER,US,US
  - IN-USER,DE,DE
  - MATCH,REJECT
```

订阅模式下，`mgate` 会自动生成：

```text
authentication
proxy-providers
proxy-groups
rules
```

## 🖥️ 支持系统

* OpenWrt
* 类 OpenWrt 系统
* 嵌入式 Linux
* Debian / Ubuntu
* 其他带有 POSIX shell 的 Linux 系统

服务管理支持：

```text
OpenWrt init.d / procd
systemd
plain background mode
```

Web 管理依赖：

```text
busybox httpd 或 httpd
```

## 🧠 支持架构

```text
x86_64 / amd64 -> linux-amd64-compatible
i386 / i686    -> linux-386
aarch64        -> linux-arm64
armv7l         -> linux-armv7
armv6l         -> linux-armv6
mips           -> linux-mips-softfloat
mipsel         -> linux-mipsle-softfloat
```

## 🧹 卸载

仅卸载 Mihomo 内核：

```sh
mgate uninstall-core
```

完整卸载：

```sh
mgate uninstall
```

完整卸载会删除：

```text
/opt/mgate
/usr/bin/mgate
/etc/init.d/mgate
/etc/init.d/mgate-web
/etc/systemd/system/mgate.service
/etc/systemd/system/mgate-web.service
```

默认需要输入：

```text
UNINSTALL
```

确认卸载。

跳过确认：

```sh
mgate uninstall --yes
```

## 🛡️ 安全提醒

* 不要把 Mixed 代理端口直接暴露到公网
* 不要把 Web 管理端口暴露到公网
* 订阅账号默认密码是 `12345678`，建议按需修改
* 妥善保管 Web Token
* 不要提交真实节点 UUID、订阅链接和密码到 GitHub
* 尽量只在 LAN 内使用
* 如需公网访问，请配合防火墙限制来源 IP

## 📄 License

MIT License
