#!/bin/sh
# mgate - Mobile Gateway Manager for Mihomo
# POSIX/BusyBox friendly management script.

set -u
umask 022

APP_NAME="mgate"
APP_DESC="Mobile Gateway Manager"
MGATE_VERSION="0.1.0"

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
DEFAULT_USERS="DE JP US UK"

REPO="MetaCubeX/mihomo"
GITHUB_RELEASE_BASE="https://github.com/$REPO/releases"
GITHUB_API_LATEST="https://api.github.com/repos/$REPO/releases/latest"

say() {
    printf '%s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

err() {
    printf 'ERROR: %s\n' "$*" >&2
}

die() {
    err "$*"
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

need_root() {
    uid="$(id -u 2>/dev/null || echo 1)"
    [ "$uid" = "0" ] || die "please run as root"
}

pause_enter() {
    printf '\nPress Enter to continue... '
    # shellcheck disable=SC2034
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
    proxy="${MGATE_GITHUB_PROXY:-}"
    if [ -z "$proxy" ]; then
        printf '%s' "$url"
        return 0
    fi
    case "$proxy" in
        */) printf '%s%s' "$proxy" "$url" ;;
        *) printf '%s/%s' "$proxy" "$url" ;;
    esac
}

fetch_to_stdout() {
    url="$1"
    if have curl; then
        curl -fsSL "$url"
        return $?
    fi
    if have wget; then
        wget -qO- "$url"
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
    say "Backed up: $file -> $BACKUP_DIR/$base.$ts"
}

detect_service_mode() {
    if [ -f /etc/openwrt_release ] || [ -x /sbin/procd ]; then
        printf '%s\n' "openwrt"
        return 0
    fi
    if have systemctl && [ -d /run/systemd/system ]; then
        printf '%s\n' "systemd"
        return 0
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
        x86_64|amd64)
            printf '%s\n' "linux-amd64-compatible"
            ;;
        i386|i486|i586|i686)
            printf '%s\n' "linux-386"
            ;;
        aarch64|arm64)
            printf '%s\n' "linux-arm64"
            ;;
        armv7*|armv7l)
            printf '%s\n' "linux-armv7"
            ;;
        armv6*|armv6l)
            printf '%s\n' "linux-armv6"
            ;;
        mipsel|mipsle)
            printf '%s\n' "linux-mipsle-softfloat"
            ;;
        mips)
            printf '%s\n' "linux-mips-softfloat"
            ;;
        *)
            die "unsupported architecture: $machine. You can set MGATE_MIHOMO_ASSET manually."
            ;;
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

    api_url="$(with_github_proxy "$GITHUB_API_LATEST")"
    json="$(fetch_to_stdout "$api_url" 2>/dev/null || true)"
    tag="$(printf '%s\n' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [ -n "$tag" ] || die "failed to get latest Mihomo version. Try MGATE_MIHOMO_VERSION=v1.19.25"
    printf '%s\n' "$tag"
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
        die "cannot locate script source. Download the script first, then run: sh ./mgate install"
    fi

    chmod 755 "$SCRIPT_PATH" || die "failed to chmod $SCRIPT_PATH"
    mkdir -p "$(dirname "$GLOBAL_BIN")"
    ln -sf "$SCRIPT_PATH" "$GLOBAL_BIN" || die "failed to create $GLOBAL_BIN"
    say "Installed manager: $SCRIPT_PATH"
    say "Global command: $GLOBAL_BIN"
}

install_core() {
    need_root
    ensure_dirs

    asset="$(detect_arch_asset)"
    version="$(get_latest_mihomo_version)"
    asset_name="mihomo-$asset-$version.gz"
    url="$(with_github_proxy "$GITHUB_RELEASE_BASE/download/$version/$asset_name")"
    tmp_gz="$TMP_DIR/$asset_name"
    tmp_bin="$TMP_DIR/mihomo"

    say "Mihomo version: $version"
    say "Mihomo asset: $asset_name"
    say "Downloading: $url"

    rm -f "$tmp_gz" "$tmp_bin"
    download_file "$url" "$tmp_gz" || die "download failed: $url"

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
    say "Installed core: $CORE_BIN"
    "$CORE_BIN" -v 2>/dev/null || true
}

generate_config_content() {
    cat <<EOF
mode: rule
log-level: warning
ipv6: false

# HTTP and SOCKS5 listeners share this authentication list.
# Client examples:
#   HTTP   http://DE:change_me_de@192.168.8.1:$DEFAULT_HTTP_PORT
#   SOCKS5 socks5://DE:change_me_de@192.168.8.1:$DEFAULT_SOCKS_PORT
authentication:
  - "DE:change_me_de"
  - "JP:change_me_jp"
  - "US:change_me_us"
  - "UK:change_me_uk"

listeners:
  - name: socks-users
    type: socks
    listen: 0.0.0.0
    port: $DEFAULT_SOCKS_PORT
    udp: true

  - name: http-users
    type: http
    listen: 0.0.0.0
    port: $DEFAULT_HTTP_PORT

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
EOF
}

generate_config() {
    need_root
    ensure_dirs

    generate_config_content > "$CONFIG_EXAMPLE" || die "failed to write $CONFIG_EXAMPLE"

    if [ -f "$CONFIG_FILE" ] && [ "${FORCE:-0}" != "1" ]; then
        say "Config exists, skipped: $CONFIG_FILE"
        say "Use FORCE=1 mgate install to backup and regenerate it."
        return 0
    fi

    if [ -f "$CONFIG_FILE" ] && [ "${FORCE:-0}" = "1" ]; then
        backup_file "$CONFIG_FILE"
    fi

    generate_config_content > "$CONFIG_FILE" || die "failed to write $CONFIG_FILE"
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
    say "Generated config: $CONFIG_FILE"
}

generate_readme() {
    ensure_dirs
    cat > "$README_FILE" <<EOF
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
  MGATE_GITHUB_PROXY=https://.../  prefix GitHub download URLs
  SOCKS_PORT=31800                override default SOCKS5 port during config generation
  HTTP_PORT=31801                 override default HTTP port during config generation
EOF
}

create_openwrt_service() {
    cat > "$OPENWRT_SERVICE_FILE" <<EOF
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
EOF
    chmod 755 "$OPENWRT_SERVICE_FILE" || die "failed to chmod OpenWrt service"
    ln -sf "$OPENWRT_SERVICE_FILE" "$OPENWRT_SERVICE_LINK" || die "failed to link $OPENWRT_SERVICE_LINK"
    say "Generated OpenWrt service: $OPENWRT_SERVICE_LINK -> $OPENWRT_SERVICE_FILE"
}

create_systemd_service() {
    cat > "$SYSTEMD_SERVICE_FILE" <<EOF
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
EOF
    chmod 644 "$SYSTEMD_SERVICE_FILE" || die "failed to chmod systemd service"
    mkdir -p "$(dirname "$SYSTEMD_SERVICE_LINK")"
    ln -sf "$SYSTEMD_SERVICE_FILE" "$SYSTEMD_SERVICE_LINK" || die "failed to link $SYSTEMD_SERVICE_LINK"
    systemctl daemon-reload >/dev/null 2>&1 || true
    say "Generated systemd service: $SYSTEMD_SERVICE_LINK -> $SYSTEMD_SERVICE_FILE"
}

create_service_files() {
    need_root
    ensure_dirs
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            create_openwrt_service
            ;;
        systemd)
            create_systemd_service
            ;;
        plain)
            warn "no OpenWrt procd or systemd detected; mgate will use plain background mode"
            ;;
    esac
}

fallback_status_quiet() {
    [ -f "$PID_FILE" ] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

fallback_start() {
    [ -x "$CORE_BIN" ] || die "Mihomo core not installed: $CORE_BIN"
    [ -f "$CONFIG_FILE" ] || die "config not found: $CONFIG_FILE"
    ensure_dirs
    if fallback_status_quiet; then
        say "mgate is already running."
        return 0
    fi
    nohup "$CORE_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    say "Started mgate in plain background mode. PID: $(cat "$PID_FILE")"
}

fallback_stop() {
    if ! fallback_status_quiet; then
        say "mgate is not running."
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
    say "Stopped mgate."
}

service_start() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" start
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl start mgate.service
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
            else
                fallback_stop
            fi
            ;;
        systemd)
            if [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                systemctl stop mgate.service || true
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
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" restart
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl restart mgate.service
            ;;
        plain)
            fallback_stop
            fallback_start
            ;;
    esac
}

service_enable() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] || create_service_files
            "$OPENWRT_SERVICE_LINK" enable
            say "Enabled mgate on boot."
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] || create_service_files
            systemctl daemon-reload >/dev/null 2>&1 || true
            systemctl enable mgate.service
            ;;
        plain)
            warn "enable is not supported without OpenWrt procd or systemd"
            ;;
    esac
}

service_disable() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] && "$OPENWRT_SERVICE_LINK" disable || true
            say "Disabled mgate on boot."
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] && systemctl disable mgate.service || true
            ;;
        plain)
            warn "disable is not supported without OpenWrt procd or systemd"
            ;;
    esac
}

service_status() {
    mode="$(detect_service_mode)"
    say "mgate workspace: $WORKDIR"
    say "service mode: $mode"
    if [ -x "$CORE_BIN" ]; then
        printf 'core: '
        "$CORE_BIN" -v 2>/dev/null || echo "$CORE_BIN"
    else
        say "core: not installed"
    fi
    say "config: $CONFIG_FILE"

    case "$mode" in
        openwrt)
            if [ -x "$OPENWRT_SERVICE_LINK" ]; then
                "$OPENWRT_SERVICE_LINK" status || true
            else
                say "OpenWrt service not installed."
            fi
            ;;
        systemd)
            if [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                systemctl status mgate.service --no-pager || true
            else
                say "systemd service not installed."
            fi
            ;;
        plain)
            if fallback_status_quiet; then
                say "plain status: running, pid $(cat "$PID_FILE")"
            else
                say "plain status: stopped"
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
        plain)
            :
            ;;
    esac
}

cmd_install() {
    need_root
    say "Installing $APP_NAME $MGATE_VERSION ..."
    ensure_dirs
    install_self
    install_core
    generate_config
    generate_readme
    create_service_files
    service_enable
    service_start
    say ""
    say "mgate installed successfully."
    say "Edit config: mgate edit"
    say "Test config: mgate test"
    say "Status:      mgate status"
}

cmd_uninstall_core() {
    need_root
    service_stop || true
    if [ -f "$CORE_BIN" ]; then
        rm -f "$CORE_BIN" || die "failed to remove $CORE_BIN"
        say "Removed Mihomo core: $CORE_BIN"
    else
        say "Mihomo core is not installed."
    fi
}

confirm_uninstall() {
    if [ "${MGATE_ASSUME_YES:-0}" = "1" ] || [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
        return 0
    fi
    say "This will remove mgate completely, including core, config, logs and backups."
    say "Workspace to remove: $WORKDIR"
    printf 'Type UNINSTALL to continue: '
    read -r ans
    [ "$ans" = "UNINSTALL" ] || die "uninstall cancelled"
}

cmd_uninstall() {
    need_root
    confirm_uninstall "${1:-}"
    say "Uninstalling mgate ..."
    service_stop || true
    service_disable || true
    remove_service_files
    rm -f "$GLOBAL_BIN"
    cd /tmp 2>/dev/null || cd /
    rm -rf "$WORKDIR"
    if [ -d "$WORKDIR" ]; then
        warn "failed to remove $WORKDIR completely"
        warn "you may remove it manually: rm -rf $WORKDIR"
    else
        say "Removed workspace: $WORKDIR"
    fi
    say "mgate uninstalled."
}

cmd_config() {
    [ -f "$CONFIG_FILE" ] || die "config not found: $CONFIG_FILE"
    cat "$CONFIG_FILE"
}

cmd_edit() {
    need_root
    [ -f "$CONFIG_FILE" ] || generate_config
    editor="${EDITOR:-vi}"
    command -v "$editor" >/dev/null 2>&1 || editor="vi"
    "$editor" "$CONFIG_FILE"
}

cmd_test() {
    [ -x "$CORE_BIN" ] || die "Mihomo core not installed: $CORE_BIN"
    [ -f "$CONFIG_FILE" ] || die "config not found: $CONFIG_FILE"
    "$CORE_BIN" -t -f "$CONFIG_FILE"
}

cmd_logs() {
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if have logread; then
                logread | grep -i 'mgate\|mihomo' | tail -n 100
            else
                [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || say "no log available"
            fi
            ;;
        systemd)
            if have journalctl && [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                journalctl -u mgate.service -n 100 --no-pager
            else
                [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || say "no log available"
            fi
            ;;
        plain)
            [ -f "$LOG_FILE" ] && tail -n 100 "$LOG_FILE" || say "no log available"
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
    cat <<EOF
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
  MGATE_GITHUB_PROXY=https://.../ prefix GitHub URLs
EOF
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
            *) warn "invalid choice"; pause_enter ;;
        esac
    done
}

main() {
    cmd="${1:-menu}"
    shift 2>/dev/null || true
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

main "$@"
