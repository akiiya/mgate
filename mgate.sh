#!/bin/sh
# mgate - Mobile Gateway Manager for Mihomo
# POSIX/BusyBox friendly management script.

set -u
umask 022

APP_NAME="mgate"
APP_DESC="Mobile Gateway Manager"
MGATE_VERSION="0.1.5"

WORKDIR="${MGATE_WORKDIR:-/opt/mgate}"
SCRIPT_PATH="$WORKDIR/mgate"
GLOBAL_BIN="${MGATE_GLOBAL_BIN:-/usr/bin/mgate}"

BIN_DIR="$WORKDIR/bin"
CORE_BIN="$BIN_DIR/mihomo"
CONFIG_DIR="$WORKDIR/config"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
CONFIG_EXAMPLE="$CONFIG_DIR/config.example.yaml"
SERVICE_DIR="$WORKDIR/service"
LOG_DIR="$WORKDIR/logs"
RUN_DIR="$WORKDIR/run"
BACKUP_DIR="$WORKDIR/backups"
TMP_DIR="$WORKDIR/tmp"
DATA_DIR="$WORKDIR/data"
PID_FILE="$RUN_DIR/mihomo.pid"
LOG_FILE="$LOG_DIR/mihomo.log"
README_FILE="$WORKDIR/README.txt"

OPENWRT_SERVICE_FILE="$SERVICE_DIR/mgate.init"
SYSTEMD_SERVICE_FILE="$SERVICE_DIR/mgate.service"
OPENWRT_SERVICE_LINK="/etc/init.d/mgate"
SYSTEMD_SERVICE_LINK="/etc/systemd/system/mgate.service"

DEFAULT_SOCKS_PORT="${SOCKS_PORT:-31800}"
DEFAULT_HTTP_PORT="${HTTP_PORT:-31801}"

REPO="MetaCubeX/mihomo"
GITHUB_RELEASE_BASE="https://github.com/$REPO/releases"
GITHUB_API_LATEST="https://api.github.com/repos/$REPO/releases/latest"
DEFAULT_MIHOMO_VERSION="${MGATE_DEFAULT_MIHOMO_VERSION:-v1.19.25}"
DEFAULT_GITHUB_PROXY="https://gh-proxy.fastly.eu.org/"

# Keep output plain ASCII for embedded routers and SSH terminals.
# No emoji, no ANSI color, no terminal control sequences.
init_output() {
    :
}

say() {
    printf '%s\n' "$*"
}

_msg() {
    level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*"
}

info() { _msg "INFO" "$@"; }
ok() { _msg "OK" "$@"; }
step() { _msg "STEP" "$@"; }
hint() { _msg "TIP" "$@"; }
warn() { _msg "WARN" "$@" >&2; }
err() { _msg "ERROR" "$@" >&2; }

die() {
    err "$*"
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

find_editor() {
    # Prefer user configured editor first, then common editors.
    if [ -n "${EDITOR:-}" ]; then
        editor_bin="$(printf '%s\n' "$EDITOR" | awk '{print $1}')"
        if command -v "$editor_bin" >/dev/null 2>&1; then
            printf '%s\n' "$editor_bin"
            return 0
        fi
        warn "EDITOR 不可用：$EDITOR"
    fi

    if [ -n "${VISUAL:-}" ]; then
        editor_bin="$(printf '%s\n' "$VISUAL" | awk '{print $1}')"
        if command -v "$editor_bin" >/dev/null 2>&1; then
            printf '%s\n' "$editor_bin"
            return 0
        fi
        warn "VISUAL 不可用：$VISUAL"
    fi

    for editor in vi vim nano micro nvim vim.tiny; do
        if command -v "$editor" >/dev/null 2>&1; then
            printf '%s\n' "$editor"
            return 0
        fi
    done

    if command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx vi; then
        printf '%s\n' "busybox vi"
        return 0
    fi

    return 1
}

run_editor() {
    editor_cmd="$1"
    file="$2"

    case "$editor_cmd" in
        "busybox vi")
            busybox vi "$file"
            ;;
        *)
            "$editor_cmd" "$file"
            ;;
    esac
}

need_root() {
    uid="$(id -u 2>/dev/null || echo 1)"
    [ "$uid" = "0" ] || die "please run as root"
}

pause_enter() {
    printf '\nPress Enter to continue... '
    read -r _ans
}

ensure_dirs() {
    mkdir -p "$WORKDIR" "$BIN_DIR" "$CONFIG_DIR" "$SERVICE_DIR" \
        "$LOG_DIR" "$RUN_DIR" "$BACKUP_DIR" "$TMP_DIR" "$DATA_DIR" || die "failed to create $WORKDIR"
}

realpath_simple() {
    if have readlink; then
        readlink -f "$1" 2>/dev/null && return 0
    fi
    printf '%s\n' "$1"
}

with_github_proxy() {
    url="$1"
    proxy="${MGATE_GITHUB_PROXY:-$DEFAULT_GITHUB_PROXY}"

    case "$proxy" in
        ""|direct|DIRECT|none|NONE|0)
            printf '%s' "$url"
            return 0
            ;;
    esac

    case "$proxy" in
        */) printf '%s%s' "$proxy" "$url" ;;
        *) printf '%s/%s' "$proxy" "$url" ;;
    esac
}

current_proxy_label() {
    proxy="${MGATE_GITHUB_PROXY:-$DEFAULT_GITHUB_PROXY}"
    case "$proxy" in
        ""|direct|DIRECT|none|NONE|0) printf '%s' "direct" ;;
        *) printf '%s' "$proxy" ;;
    esac
}

fetch_to_stdout() {
    url="$1"
    if have curl; then
        curl -fsSL --connect-timeout 15 --max-time 30 "$url"
        return $?
    fi
    if have wget; then
        wget -T 30 -qO- "$url"
        return $?
    fi
    return 127
}

download_file() {
    url="$1"
    out="$2"
    if have curl; then
        curl -fL --connect-timeout 30 -o "$out" "$url"
        return $?
    fi
    if have wget; then
        wget -O "$out" "$url"
        return $?
    fi
    die "curl or wget is required"
}

backup_file() {
    file="$1"
    [ -f "$file" ] || return 0
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    base="$(basename "$file")"
    mkdir -p "$BACKUP_DIR"
    cp "$file" "$BACKUP_DIR/$base.$ts" || die "failed to backup $file"
    ok "已备份：$file -> $BACKUP_DIR/$base.$ts"
}

detect_service_mode() {
    case "${MGATE_SERVICE_MODE:-}" in
        openwrt|systemd|plain)
            printf '%s\n' "$MGATE_SERVICE_MODE"
            return 0
            ;;
    esac

    if [ -f /etc/openwrt_release ] || [ -x /sbin/procd ]; then
        printf '%s\n' "openwrt"
        return 0
    fi

    if have systemctl && [ -d /run/systemd/system ]; then
        if systemctl show --property=Version >/dev/null 2>&1 || systemctl is-system-running >/dev/null 2>&1; then
            printf '%s\n' "systemd"
            return 0
        fi
    fi

    printf '%s\n' "plain"
}

detect_arch_asset() {
    if [ -n "${MGATE_MIHOMO_ASSET:-}" ]; then
        printf '%s\n' "$MGATE_MIHOMO_ASSET"
        return 0
    fi

    machine="$(uname -m 2>/dev/null || echo unknown)"
    case "$machine" in
        x86_64|amd64) printf '%s\n' "linux-amd64-compatible" ;;
        i386|i486|i586|i686) printf '%s\n' "linux-386" ;;
        aarch64|arm64) printf '%s\n' "linux-arm64" ;;
        armv7*|armv7l) printf '%s\n' "linux-armv7" ;;
        armv6*|armv6l) printf '%s\n' "linux-armv6" ;;
        mipsel|mipsle) printf '%s\n' "linux-mipsle-softfloat" ;;
        mips) printf '%s\n' "linux-mips-softfloat" ;;
        *) die "unsupported architecture: $machine. You can set MGATE_MIHOMO_ASSET manually." ;;
    esac
}

normalize_version() {
    v="$1"
    case "$v" in
        v*) printf '%s\n' "$v" ;;
        *) printf 'v%s\n' "$v" ;;
    esac
}

get_latest_mihomo_version() {
    want="${MGATE_MIHOMO_VERSION:-latest}"
    if [ -n "$want" ] && [ "$want" != "latest" ]; then
        normalize_version "$want"
        return 0
    fi

    api_direct="$GITHUB_API_LATEST"
    api_proxy="$(with_github_proxy "$GITHUB_API_LATEST")"

    for api_url in "$api_direct" "$api_proxy"; do
        [ -n "$api_url" ] || continue
        json="$(fetch_to_stdout "$api_url" 2>/dev/null || true)"
        tag="$(printf '%s\n' "$json" | awk -F'"' '/"tag_name"[[:space:]]*:/ {print $4; exit}')"
        if [ -n "$tag" ]; then
            printf '%s\n' "$tag"
            return 0
        fi
    done

    warn "获取 latest 失败，使用默认版本：$DEFAULT_MIHOMO_VERSION"
    printf '%s\n' "$DEFAULT_MIHOMO_VERSION"
}

install_self() {
    need_root
    ensure_dirs

    src="$0"
    src_real="$(realpath_simple "$src")"
    dst_real="$(realpath_simple "$SCRIPT_PATH")"

    if [ -f "$src" ] && [ "$src_real" != "$dst_real" ]; then
        cp "$src" "$SCRIPT_PATH" || die "failed to install manager script to $SCRIPT_PATH"
    elif [ ! -f "$SCRIPT_PATH" ]; then
        die "cannot locate script source. Download the script first, then run: sh ./mgate.sh install"
    fi

    chmod 755 "$SCRIPT_PATH" || die "failed to chmod $SCRIPT_PATH"
    mkdir -p "$(dirname "$GLOBAL_BIN")"
    ln -sf "$SCRIPT_PATH" "$GLOBAL_BIN" || die "failed to create $GLOBAL_BIN"
    ok "管理脚本已安装：$SCRIPT_PATH"
    ok "全局命令已创建：$GLOBAL_BIN"
}

install_core() {
    need_root
    ensure_dirs

    asset="$(detect_arch_asset)"
    version="$(get_latest_mihomo_version)"
    [ -n "$version" ] || die "empty Mihomo version"
    asset_name="mihomo-$asset-$version.gz"
    url="$(with_github_proxy "$GITHUB_RELEASE_BASE/download/$version/$asset_name")"
    tmp_gz="$TMP_DIR/$asset_name"
    tmp_bin="$TMP_DIR/mihomo"

    step "正在安装 Mihomo 内核"
    info "版本：$version"
    info "架构资产：$asset_name"
    info "GitHub 代理：$(current_proxy_label)"
    info "下载地址：$url"

    rm -f "$tmp_gz" "$tmp_bin"
    download_file "$url" "$tmp_gz" || die "下载失败：$url"

    if have gzip; then
        gzip -dc "$tmp_gz" > "$tmp_bin" || die "failed to decompress $tmp_gz"
    elif have gunzip; then
        gunzip -c "$tmp_gz" > "$tmp_bin" || die "failed to decompress $tmp_gz"
    else
        die "gzip or gunzip is required"
    fi

    chmod 755 "$tmp_bin" || die "failed to chmod downloaded core"
    "$tmp_bin" -v >/dev/null 2>&1 || die "downloaded core cannot run on this device"

    if [ -f "$CORE_BIN" ]; then
        backup_file "$CORE_BIN"
    fi

    mv "$tmp_bin" "$CORE_BIN" || die "failed to install Mihomo core"
    chmod 755 "$CORE_BIN"
    printf '%s\n' "$version" > "$DATA_DIR/core.version"
    ok "Mihomo 内核已安装：$CORE_BIN"
    "$CORE_BIN" -v 2>/dev/null || true
}

generate_config_content() {
    cat <<'EOF_CONFIG'
mode: rule
log-level: warning
ipv6: false

# HTTP and SOCKS5 listeners share this authentication list.
# Client examples:
#   HTTP   http://DE:change_me_de@192.168.8.1:__HTTP_PORT__
#   SOCKS5 socks5://DE:change_me_de@192.168.8.1:__SOCKS_PORT__
authentication:
  - "DE:change_me_de"
  - "JP:change_me_jp"
  - "US:change_me_us"
  - "UK:change_me_uk"

listeners:
  - name: socks-users
    type: socks
    listen: 0.0.0.0
    port: __SOCKS_PORT__
    udp: true

  - name: http-users
    type: http
    listen: 0.0.0.0
    port: __HTTP_PORT__

proxies:
  - name: node-DE
    type: vmess
    server: fra1.example.com
    port: 443
    uuid: "00000000-0000-0000-0000-000000000000"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: fra1.example.com
    network: grpc
    grpc-opts:
      grpc-service-name: "grpc-service-name"

  - name: node-JP
    type: vmess
    server: tky1.example.com
    port: 443
    uuid: "00000000-0000-0000-0000-000000000000"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: tky1.example.com
    network: grpc
    grpc-opts:
      grpc-service-name: "grpc-service-name"

  - name: node-US
    type: vmess
    server: sjc1.example.com
    port: 443
    uuid: "00000000-0000-0000-0000-000000000000"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: sjc1.example.com
    network: grpc
    grpc-opts:
      grpc-service-name: "grpc-service-name"

  - name: node-UK
    type: vmess
    server: lon1.example.com
    port: 443
    uuid: "00000000-0000-0000-0000-000000000000"
    alterId: 0
    cipher: auto
    udp: true
    tls: true
    servername: lon1.example.com
    network: grpc
    grpc-opts:
      grpc-service-name: "grpc-service-name"

proxy-groups:
  - name: DE
    type: select
    proxies:
      - node-DE

  - name: JP
    type: select
    proxies:
      - node-JP

  - name: US
    type: select
    proxies:
      - node-US

  - name: UK
    type: select
    proxies:
      - node-UK

rules:
  - IN-USER,DE,DE
  - IN-USER,JP,JP
  - IN-USER,US,US
  - IN-USER,UK,UK
  - MATCH,REJECT
EOF_CONFIG
}

render_config_content() {
    generate_config_content | sed \
        -e "s/__SOCKS_PORT__/$DEFAULT_SOCKS_PORT/g" \
        -e "s/__HTTP_PORT__/$DEFAULT_HTTP_PORT/g"
}

generate_config() {
    need_root
    ensure_dirs

    render_config_content > "$CONFIG_EXAMPLE" || die "failed to write $CONFIG_EXAMPLE"

    if [ -f "$CONFIG_FILE" ] && [ "${FORCE:-0}" != "1" ]; then
        warn "配置已存在，未覆盖：$CONFIG_FILE"
        hint "如需备份并重建配置：FORCE=1 mgate install"
        return 0
    fi

    if [ -f "$CONFIG_FILE" ] && [ "${FORCE:-0}" = "1" ]; then
        backup_file "$CONFIG_FILE"
    fi

    render_config_content > "$CONFIG_FILE" || die "failed to write $CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    ok "配置已生成：$CONFIG_FILE"
}

generate_readme() {
    ensure_dirs
    cat > "$README_FILE" <<EOF_README
mgate - Mobile Gateway Manager

Workspace:
  $WORKDIR

Core:
  $CORE_BIN

Config:
  $CONFIG_FILE

Default listeners:
  SOCKS5: 0.0.0.0:$DEFAULT_SOCKS_PORT
  HTTP:   0.0.0.0:$DEFAULT_HTTP_PORT

Default users:
  DE / JP / US / UK

Client examples:
  http://DE:change_me_de@192.168.8.1:$DEFAULT_HTTP_PORT
  socks5://DE:change_me_de@192.168.8.1:$DEFAULT_SOCKS_PORT

Common commands:
  mgate                 Enter TUI menu
  mgate install         Install/update mgate
  mgate install-core    Install/update Mihomo core
  mgate start           Start service
  mgate stop            Stop service
  mgate status          Show service status
  mgate edit            Edit config
  mgate test            Test config
  mgate logs            Show logs
  mgate uninstall       Remove mgate completely

Environment overrides:
  FORCE=1                         overwrite generated config after backup
  MGATE_MIHOMO_VERSION=v1.19.25   install a specific Mihomo version
  MGATE_MIHOMO_ASSET=linux-arm64  force a release asset architecture
  MGATE_GITHUB_PROXY=https://.../ set GitHub proxy prefix; default is $DEFAULT_GITHUB_PROXY
  MGATE_GITHUB_PROXY=direct       disable GitHub proxy and use direct download
  SOCKS_PORT=31800                override default SOCKS5 port during config generation
  HTTP_PORT=31801                 override default HTTP port during config generation
EOF_README
}

create_openwrt_service() {
    cat > "$OPENWRT_SERVICE_FILE" <<EOF_OPENWRT
#!/bin/sh /etc/rc.common

START=99
STOP=10
USE_PROCD=1

PROG="$CORE_BIN"
CONF_DIR="$CONFIG_DIR"

start_service() {
    procd_open_instance
    procd_set_param command "\$PROG" -d "\$CONF_DIR"
    procd_set_param respawn 3600 5 5
    procd_set_param limits nofile=65535
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

reload_service() {
    stop
    start
}
EOF_OPENWRT
    chmod 755 "$OPENWRT_SERVICE_FILE" || die "failed to chmod OpenWrt service"
    ln -sf "$OPENWRT_SERVICE_FILE" "$OPENWRT_SERVICE_LINK" || die "failed to link $OPENWRT_SERVICE_LINK"
    ok "OpenWrt 服务已创建：$OPENWRT_SERVICE_LINK"
}

create_systemd_service() {
    cat > "$SYSTEMD_SERVICE_FILE" <<EOF_SYSTEMD
[Unit]
Description=mgate Mihomo Gateway
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=$WORKDIR
ExecStart=$CORE_BIN -d $CONFIG_DIR
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF_SYSTEMD
    chmod 644 "$SYSTEMD_SERVICE_FILE" || die "failed to chmod systemd service"
    mkdir -p "$(dirname "$SYSTEMD_SERVICE_LINK")"
    ln -sf "$SYSTEMD_SERVICE_FILE" "$SYSTEMD_SERVICE_LINK" || die "failed to link $SYSTEMD_SERVICE_LINK"
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "systemd 服务已创建：$SYSTEMD_SERVICE_LINK"
}

create_service_files() {
    need_root
    ensure_dirs
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt) create_openwrt_service ;;
        systemd) create_systemd_service ;;
        plain) warn "未检测到 OpenWrt procd 或 systemd，将使用普通后台模式" ;;
    esac
}

fallback_status_quiet() {
    [ -f "$PID_FILE" ] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

fallback_start() {
    [ -x "$CORE_BIN" ] || die "Mihomo 内核不存在：$CORE_BIN，请先执行：mgate install-core"
    [ -f "$CONFIG_FILE" ] || die "配置文件不存在：$CONFIG_FILE，请先执行：mgate install"
    ensure_dirs
    if fallback_status_quiet; then
        info "服务已经在运行"
        return 0
    fi
    nohup "$CORE_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    ok "服务已启动，PID：$(cat "$PID_FILE")"
}

fallback_stop() {
    if ! fallback_status_quiet; then
        info "服务当前未运行"
        rm -f "$PID_FILE"
        return 0
    fi
    pid="$(cat "$PID_FILE")"
    kill "$pid" >/dev/null 2>&1 || true
    i=0
    while kill -0 "$pid" >/dev/null 2>&1; do
        i=$((i + 1))
        [ "$i" -ge 10 ] && break
        sleep 1
    done
    if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$PID_FILE"
    ok "服务已停止"
}

service_start() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" start || die "服务启动失败"
            ok "服务已启动"
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl start mgate.service || die "服务启动失败"
            ok "服务已启动"
            ;;
        plain)
            fallback_start
            ;;
    esac
}

service_stop() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if [ -x "$OPENWRT_SERVICE_LINK" ]; then
                "$OPENWRT_SERVICE_LINK" stop || true
                ok "服务已停止"
            else
                fallback_stop
            fi
            ;;
        systemd)
            if [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                systemctl stop mgate.service || true
                ok "服务已停止"
            else
                fallback_stop
            fi
            ;;
        plain)
            fallback_stop
            ;;
    esac
}

service_restart() {
    need_root
    step "正在重启服务"
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" restart || die "服务重启失败"
            ok "服务已重启"
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl restart mgate.service || die "服务重启失败"
            ok "服务已重启"
            ;;
        plain)
            fallback_stop
            fallback_start
            ok "服务已重启"
            ;;
    esac
}

service_enable() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" enable || die "设置开机启动失败"
            ok "已设置开机自启"
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable mgate.service || die "设置开机启动失败"
            ok "已设置开机自启"
            ;;
        plain)
            warn "当前模式不支持开机自启"
            ;;
    esac
}

service_disable() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] && "$OPENWRT_SERVICE_LINK" disable || true
            ok "已关闭开机自启"
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] && systemctl disable mgate.service >/dev/null 2>&1 || true
            ok "已关闭开机自启"
            ;;
        plain)
            warn "当前模式不支持开机自启"
            ;;
    esac
}

service_status() {
    mode="$(detect_service_mode)"
    info "工作目录：$WORKDIR"
    info "服务模式：$mode"
    if [ -x "$CORE_BIN" ]; then
        core_ver="$($CORE_BIN -v 2>/dev/null || true)"
        [ -n "$core_ver" ] || core_ver="$CORE_BIN"
        info "内核版本：$core_ver"
    else
        warn "Mihomo 内核未安装：$CORE_BIN"
    fi
    info "配置文件：$CONFIG_FILE"

    case "$mode" in
        openwrt)
            if [ -x "$OPENWRT_SERVICE_LINK" ]; then
                if "$OPENWRT_SERVICE_LINK" status >/dev/null 2>&1; then
                    ok "服务状态：running"
                else
                    warn "服务状态：stopped"
                fi
            else
                warn "OpenWrt 服务未安装"
            fi
            ;;
        systemd)
            if [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                active="$(systemctl is-active mgate.service 2>/dev/null || true)"
                enabled="$(systemctl is-enabled mgate.service 2>/dev/null || true)"
                main_pid="$(systemctl show -p MainPID --value mgate.service 2>/dev/null || true)"
                sub_state="$(systemctl show -p SubState --value mgate.service 2>/dev/null || true)"
                exec_status="$(systemctl show -p ExecMainStatus --value mgate.service 2>/dev/null || true)"

                [ -n "$active" ] || active="unknown"
                [ -n "$enabled" ] || enabled="unknown"
                [ -n "$main_pid" ] || main_pid="0"
                [ -n "$sub_state" ] || sub_state="unknown"
                [ -n "$exec_status" ] || exec_status="unknown"

                if [ "$active" = "active" ]; then
                    ok "服务状态：active ($sub_state)"
                else
                    warn "服务状态：$active ($sub_state)"
                fi
                info "开机自启：$enabled"
                info "主进程 PID：$main_pid"
                info "退出状态：$exec_status"
            else
                warn "systemd 服务未安装"
            fi
            ;;
        plain)
            if fallback_status_quiet; then
                ok "运行中，PID：$(cat "$PID_FILE")"
            else
                warn "服务未运行"
            fi
            ;;
    esac
}

remove_service_files() {
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] && "$OPENWRT_SERVICE_LINK" disable >/dev/null 2>&1 || true
            rm -f "$OPENWRT_SERVICE_LINK"
            ;;
        systemd)
            if [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                systemctl disable mgate.service >/dev/null 2>&1 || true
                rm -f "$SYSTEMD_SERVICE_LINK"
                systemctl daemon-reload >/dev/null 2>&1 || true
            fi
            ;;
        plain) : ;;
    esac
}

cmd_install() {
    need_root
    step "开始安装 mgate $MGATE_VERSION"
    info "工作目录：$WORKDIR"
    ensure_dirs
    install_self
    install_core
    generate_config
    generate_readme
    create_service_files
    service_enable
    service_start
    ok "mgate 安装完成"
    say ""
    hint "下一步：mgate edit && mgate test && mgate restart"
}

cmd_uninstall_core() {
    need_root
    service_stop || true
    if [ -f "$CORE_BIN" ]; then
        rm -f "$CORE_BIN" || die "failed to remove $CORE_BIN"
        ok "Mihomo 内核已删除：$CORE_BIN"
        info "配置文件已保留：$CONFIG_FILE"
    else
        info "Mihomo 内核未安装"
    fi
}

confirm_uninstall() {
    if [ "${MGATE_ASSUME_YES:-0}" = "1" ] || [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
        return 0
    fi
    warn "这将完整删除 mgate，包括内核、配置、日志和备份。"
    warn "工作目录：$WORKDIR"
    printf '请输入 UNINSTALL 确认：'
    read -r ans
    [ "$ans" = "UNINSTALL" ] || die "uninstall cancelled"
}

cmd_uninstall() {
    need_root
    confirm_uninstall "${1:-}"
    step "正在完整卸载 mgate"
    service_stop || true
    service_disable || true
    remove_service_files
    rm -f "$GLOBAL_BIN"
    cd /tmp 2>/dev/null || cd /
    rm -rf "$WORKDIR"
    if [ -d "$WORKDIR" ]; then
        warn "工作目录仍存在，请手动检查：$WORKDIR"
        warn "可手动删除：rm -rf $WORKDIR"
    else
        ok "工作目录已删除：$WORKDIR"
    fi
    ok "mgate 已完整卸载"
}

cmd_config() {
    [ -f "$CONFIG_FILE" ] || die "配置文件不存在：$CONFIG_FILE"
    cat "$CONFIG_FILE"
}

cmd_edit() {
    need_root
    [ -f "$CONFIG_FILE" ] || generate_config

    editor="$(find_editor || true)"
    if [ -z "$editor" ]; then
        err "未找到可用编辑器"
        say "请先安装 vi / vim / nano / micro，或手动编辑：$CONFIG_FILE"
        say "也可以临时指定编辑器，例如：EDITOR=/path/to/editor mgate edit"
        return 1
    fi

    info "正在编辑配置：$CONFIG_FILE"
    info "使用编辑器：$editor"
    run_editor "$editor" "$CONFIG_FILE"
}

cmd_test() {
    [ -x "$CORE_BIN" ] || die "Mihomo 内核不存在：$CORE_BIN，请先执行：mgate install-core"
    [ -f "$CONFIG_FILE" ] || die "配置文件不存在：$CONFIG_FILE，请先执行：mgate install"
    step "正在测试配置"
    "$CORE_BIN" -t -f "$CONFIG_FILE"
    ok "配置测试通过"
}

cmd_logs() {
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if have logread; then
                logread | grep -i 'mgate\|mihomo' | tail -n 100
            else
                [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || warn "暂无日志"
            fi
            ;;
        systemd)
            if have journalctl && [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                journalctl -u mgate.service -n 100 --no-pager -o cat
            else
                [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || warn "暂无日志"
            fi
            ;;
        plain)
            [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || warn "暂无日志"
            ;;
    esac
}

cmd_version() {
    say "$APP_NAME $MGATE_VERSION"
    say "workspace: $WORKDIR"
    if [ -x "$CORE_BIN" ]; then
        "$CORE_BIN" -v 2>/dev/null || true
    else
        say "mihomo: not installed"
    fi
}

usage() {
    cat <<EOF_USAGE
$APP_NAME - $APP_DESC

Usage:
  mgate                     Enter TUI menu
  mgate install             Install/update mgate, core, config and service
  mgate install-core        Install/update Mihomo core only
  mgate uninstall-core      Remove Mihomo core only, keep config and manager
  mgate uninstall [--yes]   Remove mgate completely

  mgate start               Start service
  mgate stop                Stop service
  mgate restart             Restart service
  mgate status              Show service status
  mgate enable              Enable boot start
  mgate disable             Disable boot start

  mgate config              Show config
  mgate edit                Edit config
  mgate test                Test config
  mgate logs                Show recent logs
  mgate version             Show versions
  mgate help                Show this help

Environment:
  FORCE=1                         overwrite generated config after backup
  MGATE_ASSUME_YES=1              skip uninstall confirmation
  MGATE_MIHOMO_VERSION=v1.19.25   install a specific Mihomo version
  MGATE_MIHOMO_ASSET=linux-arm64  force Mihomo release asset
  MGATE_GITHUB_PROXY=https://.../ set GitHub proxy prefix; default is $DEFAULT_GITHUB_PROXY
  MGATE_GITHUB_PROXY=direct       disable GitHub proxy and use direct download
EOF_USAGE
}

menu() {
    while :; do
        say ""
        say "mgate - Mobile Gateway Manager"
        say "Workspace: $WORKDIR"
        say ""
        say "1)  安装/更新 mgate"
        say "2)  安装/更新 Mihomo 内核"
        say "3)  卸载 Mihomo 内核"
        say "4)  完整卸载 mgate"
        say ""
        say "5)  启动服务"
        say "6)  停止服务"
        say "7)  重启服务"
        say "8)  查看服务状态"
        say ""
        say "9)  设置开机启动"
        say "10) 关闭开机启动"
        say ""
        say "11) 查看配置"
        say "12) 编辑配置"
        say "13) 测试配置"
        say "14) 查看日志"
        say "15) 查看版本"
        say ""
        say "0)  退出"
        printf '请选择: '
        read -r choice
        case "$choice" in
            1) cmd_install; pause_enter ;;
            2) install_core; pause_enter ;;
            3) cmd_uninstall_core; pause_enter ;;
            4) cmd_uninstall; exit 0 ;;
            5) service_start; pause_enter ;;
            6) service_stop; pause_enter ;;
            7) service_restart; pause_enter ;;
            8) service_status; pause_enter ;;
            9) service_enable; pause_enter ;;
            10) service_disable; pause_enter ;;
            11) cmd_config; pause_enter ;;
            12) cmd_edit; pause_enter ;;
            13) cmd_test; pause_enter ;;
            14) cmd_logs; pause_enter ;;
            15) cmd_version; pause_enter ;;
            0) exit 0 ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

main() {
    if [ "$#" -eq 0 ]; then
        menu
        exit 0
    fi

    cmd="$1"
    shift
    case "$cmd" in
        menu) menu ;;
        install) cmd_install "$@" ;;
        install-core) install_core "$@" ;;
        uninstall-core) cmd_uninstall_core "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        start) service_start "$@" ;;
        stop) service_stop "$@" ;;
        restart) service_restart "$@" ;;
        status) service_status "$@" ;;
        enable) service_enable "$@" ;;
        disable) service_disable "$@" ;;
        config) cmd_config "$@" ;;
        edit) cmd_edit "$@" ;;
        test) cmd_test "$@" ;;
        logs) cmd_logs "$@" ;;
        version) cmd_version "$@" ;;
        help|-h|--help) usage ;;
        exit) exit 0 ;;
        *)
            err "unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

init_output
main "$@"
