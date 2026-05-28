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
* 🔁 支持从 GitHub 自更新 mgate 管理脚本
* 📁 所有文件都存放在 `/opt/mgate`
* 🧹 支持完整卸载

## 📌 默认设计

```text
SOCKS5 端口：31800
HTTP   端口：31801

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

会进入交互式菜单，可进行初始化工作区、更新管理脚本、安装内核、启动服务、停止服务、编辑配置、查看日志、卸载等操作。

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
/etc/systemd/system/mgate.service
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
* 使用强密码
* 不要提交真实节点 UUID 和密码到 GitHub
* 尽量只在 LAN 内使用
* 如需公网访问，请配合防火墙限制来源 IP

## 📄 License

MIT License
