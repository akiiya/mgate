# 🚀 mgate

`mgate` 是一个面向 **随身 WiFi / OpenWrt / 嵌入式 Linux** 的轻量级 Mihomo 网关管理脚本。

它可以自动安装 Mihomo core，并提供统一命令管理 HTTP / SOCKS5 代理入口。
默认支持根据不同用户名，将流量分流到不同国家或地区的代理节点。

## ✨ 特性

* 📶 适合随身 WiFi、OpenWrt、嵌入式 Linux
* 🧠 自动识别 CPU 架构
* ⬇️ 自动下载并安装 Mihomo 内核
* 🌐 同时监听 HTTP 和 SOCKS5 代理端口
* 👥 HTTP / SOCKS5 共用同一批用户
* 🧭 根据用户名自动分流到不同代理组
* 🛡️ 未匹配流量默认拒绝
* ⚙️ 支持服务管理和开机自启
* 🧭 支持 TUI 菜单管理
* 🌍 支持轻量级 Web 管理页面
* 🔁 支持从 GitHub 自更新 mgate 管理脚本
* 📁 所有文件都存放在 `/opt/mgate`
* 🧹 支持完整卸载

## 📌 默认设计

```text
SOCKS5 端口：31800
HTTP   端口：31801
Web    端口：31888

默认用户：
DE / JP / US / UK

默认规则：
DE 用户 -> DE 代理组
JP 用户 -> JP 代理组
US 用户 -> US 代理组
UK 用户 -> UK 代理组
其他流量 -> REJECT
```

## 🚀 安装

> 不建议使用 `curl | sh`。请先下载 `mgate.sh`，再执行安装。

### curl

```sh
cd /tmp && rm -f mgate.sh && curl -fsSL -H "Cache-Control: no-cache" -o mgate.sh "https://raw.githubusercontent.com/akiiya/mgate/main/mgate.sh?ts=$(date +%s)" && sh mgate.sh install
```

### wget

```sh
cd /tmp && rm -f mgate.sh && wget -O mgate.sh "https://raw.githubusercontent.com/akiiya/mgate/main/mgate.sh?ts=$(date +%s)" && sh mgate.sh install
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

会进入交互式菜单，可进行初始化工作区、更新管理脚本、安装内核、启动服务、停止服务、编辑配置、查看日志、Web 管理、卸载等操作。

## ⌨️ 常用命令

```sh
mgate install          # 初始化/修复 mgate 工作区
mgate self-update      # 从 GitHub 更新 mgate 管理脚本
mgate update           # self-update 的别名

mgate install-core     # 安装/更新 Mihomo 内核
mgate uninstall-core   # 仅卸载 Mihomo 内核
mgate uninstall        # 完整卸载 mgate

mgate start            # 启动服务
mgate stop             # 停止服务
mgate restart          # 重启服务
mgate status           # 查看服务状态

mgate enable           # 设置开机启动
mgate disable          # 关闭开机启动

mgate config           # 查看配置
mgate edit             # 编辑配置
mgate test             # 测试配置
mgate logs             # 查看日志
mgate version          # 查看版本
```

> `mgate install` 用于初始化或修复本地工作区，不会从 GitHub 拉取最新 `mgate.sh`。
> 如需更新管理脚本，请使用 `mgate self-update` 或 `mgate update`。

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

### Web 管理页面支持

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
查看 / 重置 Web Token
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

## 🔁 自更新

更新 mgate 管理脚本：

```sh
mgate self-update
```

或者：

```sh
mgate update
```

自更新会自动从本项目 GitHub 仓库拉取最新 `mgate.sh`，并执行：

```text
1. 下载最新 mgate.sh
2. 自动添加时间戳参数，避免缓存
3. 校验脚本有效性
4. 备份当前 /opt/mgate/mgate
5. 覆盖安装新版管理脚本
6. 保留 Mihomo 内核、配置和服务状态
```

> 自更新不会自动刷新 Web 页面文件。
> 如需刷新 Web 文件，请执行 `mgate web-refresh`。

## 📂 工作目录

```text
/opt/mgate/
├── mgate                    # 安装后的管理脚本
├── bin/
│   └── mihomo               # Mihomo 内核
├── config/
│   ├── config.yaml          # 主配置文件
│   └── config.example.yaml  # 示例配置
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
  - "DE:change_me_de"
  - "JP:change_me_jp"
  - "US:change_me_us"
  - "UK:change_me_uk"

listeners:
  - name: socks-users
    type: socks
    listen: 0.0.0.0
    port: 31800
    udp: true

  - name: http-users
    type: http
    listen: 0.0.0.0
    port: 31801

rules:
  - IN-USER,DE,DE
  - IN-USER,JP,JP
  - IN-USER,US,US
  - IN-USER,UK,UK
  - MATCH,REJECT
```

你需要修改：

```text
1. authentication 里的用户密码
2. proxies 里的节点信息
3. proxy-groups 里的节点绑定关系
```

## 🔌 客户端连接

假设设备 IP 是：

```text
192.168.8.1
```

HTTP 代理：

```text
http://DE:change_me_de@192.168.8.1:31801
```

SOCKS5 代理：

```text
socks5://DE:change_me_de@192.168.8.1:31800
```

测试出口：

```sh
curl -x http://DE:change_me_de@127.0.0.1:31801 https://ipinfo.io/country
curl -x socks5h://DE:change_me_de@127.0.0.1:31800 https://ipinfo.io/country
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

* 不要把 HTTP / SOCKS5 代理端口直接暴露到公网
* 不要把 Web 管理端口暴露到公网
* 使用强密码
* 妥善保管 Web Token
* 不要提交真实节点 UUID 和密码到 GitHub
* 尽量只在 LAN 内使用
* 如需公网访问，请配合防火墙限制来源 IP

## 📄 License

MIT License
