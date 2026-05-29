#!/bin/sh
# mgate - Mobile Gateway Manager for Mihomo
# POSIX/BusyBox friendly management script.

set -u
umask 022

APP_NAME="mgate"
APP_DESC="Mobile Gateway Manager"
MGATE_VERSION="0.2.6"

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

WEB_PORT="${MGATE_WEB_PORT:-31888}"
WEB_LISTEN="${MGATE_WEB_LISTEN:-0.0.0.0}"
WEB_DIR="$WORKDIR/web"
WEB_CGI_DIR="$WEB_DIR/cgi-bin"
WEB_STATIC_DIR="$WEB_DIR/static"
WEB_INDEX_FILE="$WEB_DIR/index.html"
WEB_CGI_FILE="$WEB_CGI_DIR/mgate.cgi"
WEB_CSS_FILE="$WEB_STATIC_DIR/style.css"
WEB_FAVICON_FILE="$WEB_DIR/favicon.ico"
WEB_FAVICON_SVG_FILE="$WEB_DIR/favicon.svg"
WEB_TOKEN_FILE="$DATA_DIR/web.token"
WEB_PID_FILE="$RUN_DIR/mgate-web.pid"
WEB_LOG_FILE="$LOG_DIR/mgate-web.log"
WEB_OPENWRT_SERVICE_FILE="$SERVICE_DIR/mgate-web.init"
WEB_SYSTEMD_SERVICE_FILE="$SERVICE_DIR/mgate-web.service"
WEB_OPENWRT_SERVICE_LINK="/etc/init.d/mgate-web"
WEB_SYSTEMD_SERVICE_LINK="/etc/systemd/system/mgate-web.service"

DEFAULT_SOCKS_PORT="${SOCKS_PORT:-31800}"
DEFAULT_HTTP_PORT="${HTTP_PORT:-31801}"

REPO="MetaCubeX/mihomo"
GITHUB_RELEASE_BASE="https://github.com/$REPO/releases"
GITHUB_API_LATEST="https://api.github.com/repos/$REPO/releases/latest"
DEFAULT_MIHOMO_VERSION="${MGATE_DEFAULT_MIHOMO_VERSION:-v1.19.25}"
DEFAULT_GITHUB_PROXY="https://gh-proxy.fastly.eu.org/"
DEFAULT_SELF_URL="${MGATE_DEFAULT_SELF_URL:-https://raw.githubusercontent.com/akiiya/mgate/main/mgate.sh}"
SELF_URL_FILE="$DATA_DIR/self.url"

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

ensure_web_dirs() {
    ensure_dirs
    mkdir -p "$WEB_DIR" "$WEB_CGI_DIR" "$WEB_STATIC_DIR" || die "failed to create $WEB_DIR"
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

is_placeholder_url() {
    url="$1"
    case "$url" in
        ""|*"<your-github-username>"*|*"example.com"*|*"YOUR_"*|*"your_"*) return 0 ;;
        *) return 1 ;;
    esac
}

append_cache_bust() {
    url="$1"
    ts="$(date +%s 2>/dev/null || echo now)"
    case "$url" in
        *\?*) printf '%s&ts=%s' "$url" "$ts" ;;
        *) printf '%s?ts=%s' "$url" "$ts" ;;
    esac
}

with_self_proxy() {
    url="$1"
    proxy="${MGATE_SELF_PROXY:-${MGATE_GITHUB_PROXY:-$DEFAULT_GITHUB_PROXY}}"

    case "$proxy" in
        ""|direct|DIRECT|none|NONE|0)
            printf '%s' "$url"
            return 0
            ;;
    esac

    case "$url" in
        "$proxy"*)
            printf '%s' "$url"
            return 0
            ;;
    esac

    case "$proxy" in
        */) printf '%s%s' "$proxy" "$url" ;;
        *) printf '%s/%s' "$proxy" "$url" ;;
    esac
}

get_self_url() {
    if [ -n "${MGATE_SELF_URL:-}" ]; then
        if is_placeholder_url "$MGATE_SELF_URL"; then
            die "MGATE_SELF_URL 不是有效地址：$MGATE_SELF_URL"
        fi
        printf '%s
' "$MGATE_SELF_URL"
        return 0
    fi

    if [ -f "$SELF_URL_FILE" ]; then
        saved_url="$(sed -n '1p' "$SELF_URL_FILE" 2>/dev/null || true)"
        if [ -n "$saved_url" ] && ! is_placeholder_url "$saved_url"; then
            printf '%s
' "$saved_url"
            return 0
        fi
    fi

    if ! is_placeholder_url "$DEFAULT_SELF_URL"; then
        printf '%s
' "$DEFAULT_SELF_URL"
        return 0
    fi

    return 1
}

save_self_url_if_available() {
    ensure_dirs
    url=""
    if [ -n "${MGATE_SELF_URL:-}" ] && ! is_placeholder_url "$MGATE_SELF_URL"; then
        url="$MGATE_SELF_URL"
    elif ! is_placeholder_url "$DEFAULT_SELF_URL"; then
        url="$DEFAULT_SELF_URL"
    fi

    if [ -n "$url" ]; then
        printf '%s
' "$url" > "$SELF_URL_FILE" 2>/dev/null || true
    fi
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
        curl -fL --connect-timeout 30 -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$out" "$url"
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
    save_self_url_if_available
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
  mgate install         Initialize/repair mgate workspace
  mgate self-update    Update mgate manager script from GitHub
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
  MGATE_SELF_URL=https://.../       set mgate self-update URL
  MGATE_SELF_PROXY=https://.../     set self-update proxy; default follows MGATE_GITHUB_PROXY
  MGATE_GITHUB_PROXY=https://.../   set GitHub proxy prefix; default is $DEFAULT_GITHUB_PROXY
  MGATE_GITHUB_PROXY=direct         disable GitHub proxy and use direct download
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

extract_mgate_version() {
    file="$1"
    sed -n 's/^MGATE_VERSION="\([^"]*\)".*/\1/p' "$file" | head -n 1
}

validate_mgate_script() {
    file="$1"
    [ -s "$file" ] || die "下载内容为空"
    sh -n "$file" >/dev/null 2>&1 || die "下载内容不是有效 shell 脚本"
    grep -q 'APP_NAME="mgate"' "$file" || die "下载内容不是有效 mgate 脚本：缺少 APP_NAME"
    grep -q '^MGATE_VERSION=' "$file" || die "下载内容不是有效 mgate 脚本：缺少 MGATE_VERSION"
    grep -q 'main "\$@"' "$file" || die "下载内容不是有效 mgate 脚本：缺少入口调用"
}

cmd_self_update() {
    need_root
    ensure_dirs

    self_url="$(get_self_url || true)"
    if [ -z "$self_url" ]; then
        err "未配置 mgate 自更新地址"
        hint "请使用：MGATE_SELF_URL=https://raw.githubusercontent.com/<user>/mgate/main/mgate.sh mgate self-update"
        hint "或在脚本内设置 DEFAULT_SELF_URL 后重新安装"
        return 1
    fi

    url_with_ts="$(append_cache_bust "$self_url")"
    download_url="$(with_self_proxy "$url_with_ts")"
    tmp_file="$TMP_DIR/mgate.self-update.$$"

    step "正在更新 mgate 管理脚本"
    info "当前版本：$MGATE_VERSION"
    info "更新地址：$self_url"
    info "下载地址：$download_url"

    rm -f "$tmp_file"
    download_file "$download_url" "$tmp_file" || die "下载新版 mgate.sh 失败"
    validate_mgate_script "$tmp_file"

    new_version="$(extract_mgate_version "$tmp_file")"
    [ -n "$new_version" ] || die "无法读取新版版本号"
    info "新版本：$new_version"

    if [ -f "$SCRIPT_PATH" ]; then
        backup_file "$SCRIPT_PATH"
    fi

    cp "$tmp_file" "$SCRIPT_PATH" || die "安装新版管理脚本失败"
    chmod 755 "$SCRIPT_PATH" || die "设置脚本权限失败"
    mkdir -p "$(dirname "$GLOBAL_BIN")"
    ln -sf "$SCRIPT_PATH" "$GLOBAL_BIN" || die "创建全局命令失败"
    printf '%s
' "$self_url" > "$SELF_URL_FILE" 2>/dev/null || true
    rm -f "$tmp_file"

    ok "mgate 管理脚本已更新：$SCRIPT_PATH"
    info "当前版本：$new_version"
    hint "执行 mgate version 查看版本信息"
    hint "如需刷新 Web 管理文件，请执行：mgate web-refresh"
}

cmd_install() {
    need_root
    step "开始初始化/修复 mgate 工作区 $MGATE_VERSION"
    info "工作目录：$WORKDIR"
    ensure_dirs
    install_self
    install_core
    generate_config
    generate_readme
    create_service_files
    service_enable
    service_start
    ok "mgate 工作区初始化/修复完成"
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
    web_stop || true
    remove_web_service_files
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

find_httpd_cmd() {
    if have busybox; then
        if busybox httpd -h 2>&1 | grep -qi 'httpd'; then
            printf '%s\n' "$(command -v busybox) httpd"
            return 0
        fi
        if busybox --list 2>/dev/null | grep -qx httpd; then
            printf '%s\n' "$(command -v busybox) httpd"
            return 0
        fi
    fi

    if have httpd; then
        printf '%s\n' "$(command -v httpd)"
        return 0
    fi

    return 1
}

generate_web_token_value() {
    token=""
    if [ -r /dev/urandom ]; then
        token="$(dd if=/dev/urandom bs=48 count=1 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 24)"
    fi
    if [ -z "$token" ]; then
        token="mgate$(date +%s 2>/dev/null || echo now)$$"
    fi
    printf '%s\n' "$token"
}

ensure_web_token() {
    ensure_dirs
    if [ ! -s "$WEB_TOKEN_FILE" ]; then
        generate_web_token_value > "$WEB_TOKEN_FILE" || die "failed to write $WEB_TOKEN_FILE"
        chmod 600 "$WEB_TOKEN_FILE" 2>/dev/null || true
        ok "Web 管理 Token 已生成：$WEB_TOKEN_FILE"
    fi
}

generate_web_index() {
    cat > "$WEB_INDEX_FILE" <<'EOF_WEB_INDEX'
<!doctype html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/cgi-bin/mgate.cgi"><link rel="icon" type="image/svg+xml" href="/favicon.svg?v=0.2.6"><title>mgate</title></head><body><a href="/cgi-bin/mgate.cgi">mgate Web</a></body></html>
EOF_WEB_INDEX
}

generate_web_style() {
    cat > "$WEB_CSS_FILE" <<'EOF_WEB_CSS'
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;margin:0;background:#f6f7f9;color:#222}.wrap{max-width:1080px;margin:0 auto;padding:20px}.card{background:#fff;border:1px solid #ddd;border-radius:10px;padding:16px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.04)}h1{font-size:24px;margin:0 0 8px}h2{font-size:18px;margin:0 0 12px}h3{font-size:15px;margin:0 0 6px}.muted{color:#666;font-size:13px}.nav{display:flex;flex-wrap:wrap;gap:8px}.btn,button{display:inline-block;border:1px solid #bbb;border-radius:8px;background:#fff;color:#222;padding:8px 12px;text-decoration:none;font-size:14px;cursor:pointer}.btn:hover,button:hover{background:#f0f0f0}.danger{border-color:#c33;color:#a00}.primary{border-color:#2673d9;color:#0756b1}.good{border-color:#16a34a}.warn{border-color:#d97706}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}.mini{background:#fff;border:1px solid #ddd;border-radius:10px;padding:14px}.mini strong{display:block;font-size:16px;margin-top:4px;word-break:break-word}.mini span{color:#666;font-size:12px}.table{width:100%;border-collapse:collapse}.table th,.table td{border-bottom:1px solid #eee;padding:8px;text-align:left;vertical-align:top;font-size:13px}.code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;background:#f2f2f2;border-radius:6px;padding:2px 5px;word-break:break-all}pre{background:#111;color:#eee;padding:12px;border-radius:8px;overflow:auto;white-space:pre-wrap;word-break:break-word}.row{margin:8px 0}input[type=password],input[type=text]{padding:8px;border:1px solid #bbb;border-radius:6px;min-width:260px}.footer{margin-top:20px;color:#777;font-size:12px}.split{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.pill{display:inline-block;border:1px solid #ddd;border-radius:999px;padding:3px 8px;font-size:12px;color:#555;background:#fafafa}
EOF_WEB_CSS
}
generate_mgate_cgi() {
    cat > "$WEB_CGI_FILE" <<'EOF_WEB_CGI'
#!/bin/sh

MGATE="__MGATE_PATH__"
TOKEN_FILE="__WEB_TOKEN_FILE__"
CONFIG_FILE="__CONFIG_FILE__"
WEB_PORT="__WEB_PORT__"
DEFAULT_HTTP_PORT="__DEFAULT_HTTP_PORT__"
DEFAULT_SOCKS_PORT="__DEFAULT_SOCKS_PORT__"
FAVICON_VER="0.2.6"

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

param_get() {
    data="$1"
    key="$2"
    printf '%s' "&$data&" | sed -n "s/.*[&]$key=\([^&]*\).*/\1/p" | head -n 1
}

read_post_body() {
    len="${CONTENT_LENGTH:-0}"
    case "$len" in ''|*[!0-9]*) len=0 ;; esac
    if [ "$len" -gt 0 ]; then
        dd bs=1 count="$len" 2>/dev/null
    fi
}

expected_token() {
    sed -n '1p' "$TOKEN_FILE" 2>/dev/null
}

cookie_token() {
    printf '%s' "${HTTP_COOKIE:-}" | tr ';' '\n' | sed -n 's/^ *mgate_token=//p' | head -n 1
}

is_logged_in() {
    exp="$(expected_token)"
    got="$(cookie_token)"
    [ -n "$exp" ] && [ "$got" = "$exp" ]
}

header() {
    printf 'Content-Type: text/html; charset=utf-8\r\n'
    printf 'Cache-Control: no-store\r\n'
    printf 'Connection: close\r\n'
    if [ -n "${1:-}" ]; then
        printf '%s\r\n' "$1"
    fi
    printf '\r\n'
}

page_start() {
    title="$1"
    cat <<EOF
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$title</title>
<link rel="icon" type="image/svg+xml" href="/favicon.svg?v=$FAVICON_VER">
<link rel="stylesheet" href="/static/style.css?v=$FAVICON_VER">
</head>
<body><div class="wrap">
<h1>mgate Web</h1>
<div class="muted">轻量级 Mihomo 网关管理</div>
EOF
}

nav() {
    cat <<'EOF'
<div class="card"><div class="nav">
<a class="btn" href="/cgi-bin/mgate.cgi?action=status">首页</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=version">版本</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=doctor">诊断</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=proxy-info">连接信息</a>
<a class="btn primary" href="/cgi-bin/mgate.cgi?action=start">启动服务</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=stop">停止服务</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=restart">重启服务</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=test">测试配置</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logs&lines=100">查看日志</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=config">查看配置</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=token">Token</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=self-update">自更新</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=web-disable">关闭 Web 管理</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logout">退出登录</a>
</div></div>
EOF
}

page_end() {
    cat <<EOF
<div class="footer">mgate Web 仅建议在局域网内使用，请不要暴露到公网。</div>
</div></body></html>
EOF
}

login_page() {
    msg="$1"
    header
    page_start "mgate Login"
    cat <<EOF
<div class="card">
<h2>登录</h2>
<p class="muted">请输入 Web 管理 Token。</p>
EOF
    if [ -n "$msg" ]; then
        printf '<p class="danger">%s</p>\n' "$(printf '%s' "$msg" | html_escape)"
    fi
    cat <<'EOF'
<form method="POST" action="/cgi-bin/mgate.cgi">
<input type="hidden" name="action" value="login">
<div class="row"><input type="password" name="token" autocomplete="current-password"></div>
<div class="row"><button class="primary" type="submit">登录</button></div>
</form>
</div>
EOF
    page_end
}

run_output_page() {
    title="$1"
    shift
    output="$($MGATE "$@" 2>&1)"
    rc=$?
    header
    page_start "$title"
    nav
    printf '<div class="card"><h2>%s</h2><pre>' "$(printf '%s' "$title" | html_escape)"
    printf '%s\n' "$output" | html_escape
    printf '\nexit code: %s' "$rc" | html_escape
    printf '</pre></div>\n'
    page_end
}

summary_card() {
    label="$1"
    value="$2"
    klass="$3"
    printf '<div class="mini %s"><span>%s</span><strong>%s</strong></div>\n' \
        "$(printf '%s' "$klass" | html_escape)" \
        "$(printf '%s' "$label" | html_escape)" \
        "$(printf '%s' "$value" | html_escape)"
}

status_page() {
    status_out="$($MGATE status 2>&1)"
    version_out="$($MGATE version 2>&1)"

    svc_line="$(printf '%s\n' "$status_out" | grep '服务状态' | head -n 1)"
    [ -n "$svc_line" ] || svc_line="$(printf '%s\n' "$status_out" | grep '运行中\|服务未运行' | head -n 1)"
    [ -n "$svc_line" ] || svc_line="未知"
    case "$svc_line" in *'active'*|*'running'*|*'运行中'*) svc_class="good" ;; *) svc_class="warn" ;; esac

    core_line="$(printf '%s\n' "$status_out" | grep '内核版本\|Mihomo 内核未安装' | head -n 1)"
    [ -n "$core_line" ] || core_line="未知"
    case "$core_line" in *未安装*) core_class="warn" ;; *) core_class="good" ;; esac

    boot_line="$(printf '%s\n' "$status_out" | grep '开机自启' | head -n 1)"
    [ -n "$boot_line" ] || boot_line="未知"
    case "$boot_line" in *enabled*|*启用*) boot_class="good" ;; *) boot_class="warn" ;; esac

    if [ -f "$CONFIG_FILE" ]; then
        cfg_line="已存在"
        cfg_class="good"
    else
        cfg_line="不存在"
        cfg_class="warn"
    fi

    header
    page_start "状态"
    nav
    cat <<'EOF'
<div class="card"><h2>状态概览</h2><div class="grid">
EOF
    summary_card "mgate 服务" "$svc_line" "$svc_class"
    summary_card "Mihomo 内核" "$core_line" "$core_class"
    summary_card "开机自启" "$boot_line" "$boot_class"
    summary_card "配置文件" "$cfg_line" "$cfg_class"
    summary_card "HTTP 代理" "$DEFAULT_HTTP_PORT" ""
    summary_card "SOCKS5 代理" "$DEFAULT_SOCKS_PORT" ""
    cat <<'EOF'
</div></div>
EOF
    printf '<div class="card"><h2>详细状态</h2><pre>'
    printf '%s\n' "$status_out" | html_escape
    printf '</pre></div>\n'
    printf '<div class="card"><h2>版本信息</h2><pre>'
    printf '%s\n' "$version_out" | html_escape
    printf '</pre></div>\n'
    page_end
}

confirm_page() {
    target="$1"
    label="$target"
    case "$target" in
        stop) label="停止 mgate 服务" ;;
        restart) label="重启 mgate 服务" ;;
        self-update) label="从 GitHub 更新 mgate 管理脚本" ;;
        web-disable) label="关闭 Web 管理" ;;
        token-reset) label="重置 Web 管理 Token" ;;
    esac
    header
    page_start "Confirm"
    nav
    cat <<EOF
<div class="card">
<h2>确认操作</h2>
<p>即将执行：<strong>$(printf '%s' "$label" | html_escape)</strong></p>
<form method="POST" action="/cgi-bin/mgate.cgi">
<input type="hidden" name="action" value="do">
<input type="hidden" name="target" value="$(printf '%s' "$target" | html_escape)">
<button class="danger" type="submit">确认执行</button>
<a class="btn" href="/cgi-bin/mgate.cgi?action=status">取消</a>
</form>
</div>
EOF
    page_end
}

token_page() {
    tok="$(expected_token)"
    header
    page_start "Token"
    nav
    cat <<EOF
<div class="card">
<h2>Web Token</h2>
<p class="muted">Token 保存在：<span class="code">$TOKEN_FILE</span></p>
<p><span class="code">$(printf '%s' "$tok" | html_escape)</span></p>
<p><a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=token-reset">重置 Token</a></p>
</div>
EOF
    page_end
}

listener_port() {
    name="$1"
    def="$2"
    if [ -f "$CONFIG_FILE" ]; then
        p="$(awk -v n="$name" '
            $0 ~ "name:[[:space:]]*" n {found=1}
            found && $1=="port:" {print $2; exit}
            found && /^  - name:/ && $0 !~ n {found=0}
        ' "$CONFIG_FILE" 2>/dev/null | head -n 1)"
        [ -n "$p" ] && { printf '%s\n' "$p"; return 0; }
    fi
    printf '%s\n' "$def"
}

proxy_info_page() {
    host="${HTTP_HOST:-设备IP}"
    host="${host%%:*}"
    http_port="$(listener_port http-users "$DEFAULT_HTTP_PORT")"
    socks_port="$(listener_port socks-users "$DEFAULT_SOCKS_PORT")"

    header
    page_start "连接信息"
    nav
    cat <<EOF
<div class="card">
<h2>代理连接信息</h2>
<p class="muted">如果密码包含特殊字符，请在客户端代理 URL 中进行 URL 编码。</p>
<table class="table"><thead><tr><th>用户</th><th>HTTP 代理</th><th>SOCKS5 代理</th></tr></thead><tbody>
EOF
    if [ -f "$CONFIG_FILE" ]; then
        awk '
            /^authentication:/ {on=1; next}
            /^[A-Za-z0-9_-]+:/ {if(on) exit}
            on && /^[[:space:]]*-[[:space:]]*"/ {
                line=$0
                sub(/^[^"]*"/, "", line)
                sub(/"[[:space:]]*$/, "", line)
                print line
            }
        ' "$CONFIG_FILE" | while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            user="${entry%%:*}"
            pass="${entry#*:}"
            http_url="http://$user:$pass@$host:$http_port"
            socks_url="socks5://$user:$pass@$host:$socks_port"
            printf '<tr><td><span class="code">%s</span></td><td><span class="code">%s</span></td><td><span class="code">%s</span></td></tr>\n' \
                "$(printf '%s' "$user" | html_escape)" \
                "$(printf '%s' "$http_url" | html_escape)" \
                "$(printf '%s' "$socks_url" | html_escape)"
        done
    fi
    cat <<'EOF'
</tbody></table>
</div>
EOF
    page_end
}

logs_page() {
    lines="$1"
    case "$lines" in 50|100|200) : ;; *) lines="100" ;; esac
    output="$($MGATE logs "$lines" 2>&1)"
    rc=$?
    header
    page_start "日志"
    nav
    cat <<EOF
<div class="card"><h2>最近日志</h2><div class="split">
<a class="btn" href="/cgi-bin/mgate.cgi?action=logs&lines=50">50 行</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logs&lines=100">100 行</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logs&lines=200">200 行</a>
<span class="pill">当前：$lines 行</span>
</div><pre>
EOF
    printf '%s\n' "$output" | html_escape
    printf '\nexit code: %s' "$rc" | html_escape
    cat <<'EOF'
</pre></div>
EOF
    page_end
}

post_body=""
if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
    post_body="$(read_post_body)"
fi

action="$(param_get "$post_body" action)"
[ -n "$action" ] || action="$(param_get "${QUERY_STRING:-}" action)"
[ -n "$action" ] || action="status"

target="$(param_get "$post_body" target)"
[ -n "$target" ] || target="$(param_get "${QUERY_STRING:-}" target)"
lines="$(param_get "${QUERY_STRING:-}" lines)"

if [ "$action" = "login" ]; then
    token="$(param_get "$post_body" token)"
    exp="$(expected_token)"
    if [ -n "$exp" ] && [ "$token" = "$exp" ]; then
        header "Set-Cookie: mgate_token=$exp; Path=/; HttpOnly; SameSite=Lax"
        page_start "登录成功"
        nav
        cat <<'EOF'
<div class="card"><h2>登录成功</h2><p><a class="btn primary" href="/cgi-bin/mgate.cgi?action=status">进入首页</a></p></div>
EOF
        page_end
        exit 0
    fi
    login_page "Token 错误"
    exit 0
fi

if [ "$action" = "logout" ]; then
    header "Set-Cookie: mgate_token=deleted; Path=/; Max-Age=0"
    page_start "Logout"
    cat <<'EOF'
<div class="card"><h2>已退出</h2><p><a class="btn" href="/cgi-bin/mgate.cgi">重新登录</a></p></div>
EOF
    page_end
    exit 0
fi

if ! is_logged_in; then
    login_page ""
    exit 0
fi

case "$action" in
    status) status_page ;;
    version) run_output_page "版本" version ;;
    doctor) run_output_page "系统诊断" doctor ;;
    proxy-info) proxy_info_page ;;
    start) run_output_page "启动服务" start ;;
    test) run_output_page "测试配置" test ;;
    logs) logs_page "$lines" ;;
    config) run_output_page "当前配置" config ;;
    token) token_page ;;
    confirm)
        case "$target" in
            stop|restart|self-update|web-disable|token-reset) confirm_page "$target" ;;
            *) status_page ;;
        esac
        ;;
    do)
        case "$target" in
            stop) run_output_page "停止服务" stop ;;
            restart) run_output_page "重启服务" restart ;;
            self-update) run_output_page "自更新 mgate" self-update ;;
            token-reset)
                header "Set-Cookie: mgate_token=deleted; Path=/; Max-Age=0"
                page_start "Token 已重置"
                out="$($MGATE web-token reset 2>&1)"
                printf '<div class="card"><h2>Token 已重置</h2><pre>'
                printf '%s\n' "$out" | html_escape
                printf '</pre><p><a class="btn" href="/cgi-bin/mgate.cgi">重新登录</a></p></div>\n'
                page_end
                ;;
            web-disable)
                header
                page_start "关闭 Web 管理"
                cat <<'EOF'
<div class="card"><h2>Web 管理即将关闭</h2><p>请稍等几秒后关闭此页面。</p></div>
EOF
                page_end
                (sleep 1; "$MGATE" web-disable >/dev/null 2>&1) &
                ;;
            *) status_page ;;
        esac
        ;;
    *) status_page ;;
esac
exit 0
EOF_WEB_CGI

    sed -i \
        -e "s#__MGATE_PATH__#$SCRIPT_PATH#g" \
        -e "s#__WEB_TOKEN_FILE__#$WEB_TOKEN_FILE#g" \
        -e "s#__CONFIG_FILE__#$CONFIG_FILE#g" \
        -e "s#__WEB_PORT__#$WEB_PORT#g" \
        -e "s#__DEFAULT_HTTP_PORT__#$DEFAULT_HTTP_PORT#g" \
        -e "s#__DEFAULT_SOCKS_PORT__#$DEFAULT_SOCKS_PORT#g" \
        "$WEB_CGI_FILE"

    chmod 755 "$WEB_CGI_FILE" || die "failed to chmod $WEB_CGI_FILE"
    sh -n "$WEB_CGI_FILE" || die "generated CGI syntax check failed"
}
generate_web_favicon() {
    : > "$WEB_FAVICON_FILE" || die "failed to write $WEB_FAVICON_FILE"

    cat > "$WEB_FAVICON_SVG_FILE" <<'EOF_WEB_FAVICON'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#2563eb"/>
  <text x="32" y="42" font-size="34" text-anchor="middle" fill="#ffffff" font-family="Arial, sans-serif">M</text>
</svg>
EOF_WEB_FAVICON
}

generate_web_files() {
    need_root
    ensure_web_dirs
    generate_web_index
    generate_web_style
    generate_web_favicon
    generate_mgate_cgi
    ok "Web 管理文件已生成：$WEB_DIR"
}

create_web_openwrt_service() {
    httpd_cmd="$1"
    cat > "$WEB_OPENWRT_SERVICE_FILE" <<EOF_WEB_INIT
#!/bin/sh /etc/rc.common

START=98
STOP=11
USE_PROCD=1

HTTPD_CMD="$httpd_cmd"
WEB_LISTEN="$WEB_LISTEN"
WEB_PORT="$WEB_PORT"
WEB_DIR="$WEB_DIR"

start_service() {
    set -- \$HTTPD_CMD
    procd_open_instance
    procd_set_param command "\$@" -f -p "\$WEB_LISTEN:\$WEB_PORT" -h "\$WEB_DIR"
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF_WEB_INIT
    chmod 755 "$WEB_OPENWRT_SERVICE_FILE" || die "failed to chmod $WEB_OPENWRT_SERVICE_FILE"
    ln -sf "$WEB_OPENWRT_SERVICE_FILE" "$WEB_OPENWRT_SERVICE_LINK" || die "failed to link $WEB_OPENWRT_SERVICE_LINK"
    ok "OpenWrt Web 服务已创建：$WEB_OPENWRT_SERVICE_LINK"
}

create_web_systemd_service() {
    httpd_cmd="$1"
    cat > "$WEB_SYSTEMD_SERVICE_FILE" <<EOF_WEB_SYSTEMD
[Unit]
Description=mgate Web Manager
After=network.target
Wants=network.target

[Service]
Type=simple
WorkingDirectory=$WORKDIR
ExecStart=$httpd_cmd -f -p $WEB_LISTEN:$WEB_PORT -h $WEB_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_WEB_SYSTEMD
    chmod 644 "$WEB_SYSTEMD_SERVICE_FILE" || die "failed to chmod $WEB_SYSTEMD_SERVICE_FILE"
    mkdir -p "$(dirname "$WEB_SYSTEMD_SERVICE_LINK")"
    ln -sf "$WEB_SYSTEMD_SERVICE_FILE" "$WEB_SYSTEMD_SERVICE_LINK" || die "failed to link $WEB_SYSTEMD_SERVICE_LINK"
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "systemd Web 服务已创建：$WEB_SYSTEMD_SERVICE_LINK"
}

create_web_service_files() {
    need_root
    ensure_web_dirs
    httpd_cmd="$(find_httpd_cmd || true)"
    [ -n "$httpd_cmd" ] || die "未找到可用 httpd，请安装 busybox httpd"
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt) create_web_openwrt_service "$httpd_cmd" ;;
        systemd) create_web_systemd_service "$httpd_cmd" ;;
        plain) warn "Web 管理将使用普通后台模式" ;;
    esac
}

web_fallback_status_quiet() {
    [ -f "$WEB_PID_FILE" ] || return 1
    pid="$(cat "$WEB_PID_FILE" 2>/dev/null || true)"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

web_fallback_start() {
    httpd_cmd="$(find_httpd_cmd || true)"
    [ -n "$httpd_cmd" ] || die "未找到可用 httpd，请安装 busybox httpd"
    ensure_web_token
    generate_web_files
    if web_fallback_status_quiet; then
        info "Web 管理已经在运行"
        return 0
    fi
    set -- $httpd_cmd
    nohup "$@" -f -p "$WEB_LISTEN:$WEB_PORT" -h "$WEB_DIR" >> "$WEB_LOG_FILE" 2>&1 &
    echo $! > "$WEB_PID_FILE"
    ok "Web 管理已启动，PID：$(cat "$WEB_PID_FILE")"
}

web_fallback_stop() {
    if ! web_fallback_status_quiet; then
        info "Web 管理当前未运行"
        rm -f "$WEB_PID_FILE"
        return 0
    fi
    pid="$(cat "$WEB_PID_FILE")"
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    kill -0 "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
    rm -f "$WEB_PID_FILE"
    ok "Web 管理已停止"
}

web_start() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] || create_web_service_files
            "$WEB_OPENWRT_SERVICE_LINK" start || die "Web 管理启动失败"
            ok "Web 管理已启动"
            ;;
        systemd)
            [ -e "$WEB_SYSTEMD_SERVICE_LINK" ] || create_web_service_files
            systemctl start mgate-web.service || die "Web 管理启动失败"
            ok "Web 管理已启动"
            ;;
        plain) web_fallback_start ;;
    esac
}

web_stop() {
    need_root
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] && "$WEB_OPENWRT_SERVICE_LINK" stop || true
            ok "Web 管理已停止"
            ;;
        systemd)
            [ -e "$WEB_SYSTEMD_SERVICE_LINK" ] && systemctl stop mgate-web.service || true
            ok "Web 管理已停止"
            ;;
        plain) web_fallback_stop ;;
    esac
}

web_restart() {
    need_root
    web_stop || true
    web_start
}

web_enable() {
    need_root
    ensure_web_token
    generate_web_files
    create_web_service_files
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] && "$WEB_OPENWRT_SERVICE_LINK" enable || true
            ;;
        systemd)
            [ -e "$WEB_SYSTEMD_SERVICE_LINK" ] && systemctl enable mgate-web.service >/dev/null 2>&1 || true
            ;;
        plain) warn "当前模式不支持 Web 开机自启" ;;
    esac
    web_start
    ok "Web 管理已开启"
    info "访问地址：http://<device-ip>:$WEB_PORT"
    info "Web Token：$(sed -n '1p' "$WEB_TOKEN_FILE" 2>/dev/null)"
    warn "请不要把 Web 管理端口暴露到公网"
}

web_disable() {
    need_root
    web_stop || true
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] && "$WEB_OPENWRT_SERVICE_LINK" disable || true
            ;;
        systemd)
            [ -e "$WEB_SYSTEMD_SERVICE_LINK" ] && systemctl disable mgate-web.service >/dev/null 2>&1 || true
            ;;
        plain) : ;;
    esac
    ok "Web 管理已关闭"
}

web_status() {
    mode="$(detect_service_mode)"
    info "Web 目录：$WEB_DIR"
    info "监听地址：$WEB_LISTEN:$WEB_PORT"
    if [ -s "$WEB_TOKEN_FILE" ]; then
        info "Token 文件：$WEB_TOKEN_FILE"
    else
        warn "Web Token 未生成"
    fi
    case "$mode" in
        openwrt)
            if [ -x "$WEB_OPENWRT_SERVICE_LINK" ]; then
                if "$WEB_OPENWRT_SERVICE_LINK" status >/dev/null 2>&1; then
                    ok "Web 状态：running"
                else
                    warn "Web 状态：stopped"
                fi
            else
                warn "OpenWrt Web 服务未安装"
            fi
            ;;
        systemd)
            if [ -e "$WEB_SYSTEMD_SERVICE_LINK" ]; then
                active="$(systemctl is-active mgate-web.service 2>/dev/null || true)"
                enabled="$(systemctl is-enabled mgate-web.service 2>/dev/null || true)"
                [ -n "$active" ] || active="unknown"
                [ -n "$enabled" ] || enabled="unknown"
                if [ "$active" = "active" ]; then
                    ok "Web 状态：active"
                else
                    warn "Web 状态：$active"
                fi
                info "Web 开机自启：$enabled"
            else
                warn "systemd Web 服务未安装"
            fi
            ;;
        plain)
            if web_fallback_status_quiet; then
                ok "Web 状态：running，PID：$(cat "$WEB_PID_FILE")"
            else
                warn "Web 状态：stopped"
            fi
            ;;
    esac
}

web_token() {
    need_root
    case "${1:-show}" in
        reset)
            ensure_dirs
            generate_web_token_value > "$WEB_TOKEN_FILE" || die "重置 Web Token 失败"
            chmod 600 "$WEB_TOKEN_FILE" 2>/dev/null || true
            ok "Web Token 已重置"
            info "Web Token：$(sed -n '1p' "$WEB_TOKEN_FILE")"
            ;;
        show|*)
            ensure_web_token
            info "Web Token：$(sed -n '1p' "$WEB_TOKEN_FILE")"
            ;;
    esac
}

web_refresh() {
    need_root
    ensure_web_token
    generate_web_files
    create_web_service_files
    ok "Web 管理文件已刷新"
    hint "如 Web 管理正在运行，可执行：mgate web-restart"
}

remove_web_service_files() {
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] && "$WEB_OPENWRT_SERVICE_LINK" disable >/dev/null 2>&1 || true
            rm -f "$WEB_OPENWRT_SERVICE_LINK"
            ;;
        systemd)
            if [ -e "$WEB_SYSTEMD_SERVICE_LINK" ]; then
                systemctl disable mgate-web.service >/dev/null 2>&1 || true
                rm -f "$WEB_SYSTEMD_SERVICE_LINK"
                systemctl daemon-reload >/dev/null 2>&1 || true
            fi
            ;;
        plain) : ;;
    esac
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
    lines="${1:-100}"
    case "$lines" in
        50|100|200) : ;;
        *) lines="100" ;;
    esac

    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if have logread; then
                logread | grep -i 'mgate\|mihomo' | tail -n "$lines"
            else
                [ -f "$LOG_FILE" ] && tail -n "$lines" "$LOG_FILE" || warn "暂无日志"
            fi
            ;;
        systemd)
            if have journalctl && [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                journalctl -u mgate.service -n "$lines" --no-pager -o cat
            else
                [ -f "$LOG_FILE" ] && tail -n "$lines" "$LOG_FILE" || warn "暂无日志"
            fi
            ;;
        plain)
            [ -f "$LOG_FILE" ] && tail -n "$lines" "$LOG_FILE" || warn "暂无日志"
            ;;
    esac
}

config_listener_port() {
    name="$1"
    def="$2"
    if [ -f "$CONFIG_FILE" ]; then
        p="$(awk -v n="$name" '
            $0 ~ "name:[[:space:]]*" n {found=1}
            found && $1=="port:" {print $2; exit}
            found && /^  - name:/ && $0 !~ n {found=0}
        ' "$CONFIG_FILE" 2>/dev/null | head -n 1)"
        if [ -n "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    fi
    printf '%s\n' "$def"
}

is_tcp_port_listening() {
    port="$1"
    case "$port" in ''|*[!0-9]*) return 2 ;; esac

    if have ss; then
        ss -lnt 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1} END{exit !found}' && return 0
    fi

    if have netstat; then
        netstat -lnt 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {found=1} END{exit !found}' && return 0
    fi

    hex="$(printf '%04X' "$port" 2>/dev/null | tr 'A-F' 'a-f')"
    [ -n "$hex" ] || return 2
    for f in /proc/net/tcp /proc/net/tcp6; do
        [ -r "$f" ] || continue
        awk -v p="$hex" 'BEGIN{found=0} NR>1 {local=tolower($2); state=$4; if (local ~ ":" p "$" && state=="0A") found=1} END{exit !found}' "$f" 2>/dev/null && return 0
    done
    return 1
}

doctor_ok() {
    ok "$1"
    DOCTOR_OK=$((DOCTOR_OK + 1))
}

doctor_warn() {
    warn "$1"
    DOCTOR_WARN=$((DOCTOR_WARN + 1))
}

doctor_fail() {
    err "$1"
    DOCTOR_FAIL=$((DOCTOR_FAIL + 1))
}

check_required_cmd() {
    label="$1"
    shift
    for c in "$@"; do
        if have "$c"; then
            doctor_ok "$label：$c"
            return 0
        fi
    done
    doctor_fail "$label：未找到 $*"
    return 1
}

check_optional_cmd() {
    label="$1"
    shift
    for c in "$@"; do
        if have "$c"; then
            doctor_ok "$label：$c"
            return 0
        fi
    done
    doctor_warn "$label：未找到 $*"
    return 1
}

check_port() {
    label="$1"
    port="$2"
    case "$port" in ''|*[!0-9]*) doctor_warn "$label 端口无效：$port"; return 1 ;; esac
    if is_tcp_port_listening "$port"; then
        doctor_ok "$label 端口监听中：$port"
    else
        doctor_warn "$label 端口未监听：$port"
    fi
}

cmd_doctor() {
    DOCTOR_OK=0
    DOCTOR_WARN=0
    DOCTOR_FAIL=0

    info "mgate 版本：$MGATE_VERSION"
    info "工作目录：$WORKDIR"
    info "服务模式：$(detect_service_mode)"

    say ""
    step "检查基础命令"
    check_required_cmd "下载工具" curl wget
    check_required_cmd "解压工具" gzip gunzip
    check_optional_cmd "日志工具" logread journalctl
    check_optional_cmd "端口检查工具" ss netstat
    check_optional_cmd "Web 服务" busybox httpd

    say ""
    step "检查工作目录"
    for d in "$WORKDIR" "$BIN_DIR" "$CONFIG_DIR" "$SERVICE_DIR" "$LOG_DIR" "$RUN_DIR" "$BACKUP_DIR" "$TMP_DIR" "$DATA_DIR"; do
        if [ -d "$d" ]; then
            doctor_ok "目录存在：$d"
        else
            doctor_warn "目录不存在：$d"
        fi
    done

    say ""
    step "检查 Mihomo 内核"
    if [ -x "$CORE_BIN" ]; then
        core_ver="$($CORE_BIN -v 2>/dev/null || true)"
        [ -n "$core_ver" ] || core_ver="$CORE_BIN"
        doctor_ok "Mihomo 内核可执行：$core_ver"
    elif [ -f "$CORE_BIN" ]; then
        doctor_fail "Mihomo 内核存在但不可执行：$CORE_BIN"
    else
        doctor_fail "Mihomo 内核不存在：$CORE_BIN"
    fi

    say ""
    step "检查配置"
    if [ -f "$CONFIG_FILE" ]; then
        doctor_ok "配置文件存在：$CONFIG_FILE"
        if [ -x "$CORE_BIN" ]; then
            if "$CORE_BIN" -t -f "$CONFIG_FILE" >/tmp/mgate-doctor-config.out 2>&1; then
                doctor_ok "配置语法测试通过"
            else
                doctor_fail "配置语法测试失败"
                sed 's/^/[DETAIL] /' /tmp/mgate-doctor-config.out 2>/dev/null | tail -n 20
            fi
            rm -f /tmp/mgate-doctor-config.out
        else
            doctor_warn "跳过配置测试：Mihomo 内核不可用"
        fi
    else
        doctor_fail "配置文件不存在：$CONFIG_FILE"
    fi

    say ""
    step "检查 mgate 服务"
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            [ -x "$OPENWRT_SERVICE_LINK" ] && doctor_ok "OpenWrt 服务入口存在：$OPENWRT_SERVICE_LINK" || doctor_warn "OpenWrt 服务入口不存在：$OPENWRT_SERVICE_LINK"
            if [ -x "$OPENWRT_SERVICE_LINK" ] && "$OPENWRT_SERVICE_LINK" status >/dev/null 2>&1; then
                doctor_ok "mgate 服务运行中"
            else
                doctor_warn "mgate 服务未运行"
            fi
            ;;
        systemd)
            [ -e "$SYSTEMD_SERVICE_LINK" ] && doctor_ok "systemd 服务入口存在：$SYSTEMD_SERVICE_LINK" || doctor_warn "systemd 服务入口不存在：$SYSTEMD_SERVICE_LINK"
            active="$(systemctl is-active mgate.service 2>/dev/null || true)"
            enabled="$(systemctl is-enabled mgate.service 2>/dev/null || true)"
            [ "$active" = "active" ] && doctor_ok "mgate 服务运行中：$active" || doctor_warn "mgate 服务状态：${active:-unknown}"
            [ "$enabled" = "enabled" ] && doctor_ok "mgate 开机自启：$enabled" || doctor_warn "mgate 开机自启：${enabled:-unknown}"
            ;;
        plain)
            if fallback_status_quiet; then
                doctor_ok "mgate plain 模式运行中，PID：$(cat "$PID_FILE" 2>/dev/null)"
            else
                doctor_warn "mgate plain 模式未运行"
            fi
            ;;
    esac

    say ""
    step "检查代理端口"
    http_port="$(config_listener_port http-users "$DEFAULT_HTTP_PORT")"
    socks_port="$(config_listener_port socks-users "$DEFAULT_SOCKS_PORT")"
    check_port "HTTP 代理" "$http_port"
    check_port "SOCKS5 代理" "$socks_port"

    say ""
    step "检查 Web 管理"
    if [ -d "$WEB_DIR" ]; then
        doctor_ok "Web 目录存在：$WEB_DIR"
    else
        doctor_warn "Web 目录不存在：$WEB_DIR"
    fi
    [ -x "$WEB_CGI_FILE" ] && doctor_ok "Web CGI 可执行：$WEB_CGI_FILE" || doctor_warn "Web CGI 不可执行或不存在：$WEB_CGI_FILE"
    [ -s "$WEB_TOKEN_FILE" ] && doctor_ok "Web Token 已生成：$WEB_TOKEN_FILE" || doctor_warn "Web Token 未生成"
    case "$mode" in
        openwrt)
            [ -x "$WEB_OPENWRT_SERVICE_LINK" ] && doctor_ok "OpenWrt Web 服务入口存在：$WEB_OPENWRT_SERVICE_LINK" || doctor_warn "OpenWrt Web 服务入口不存在：$WEB_OPENWRT_SERVICE_LINK"
            ;;
        systemd)
            [ -e "$WEB_SYSTEMD_SERVICE_LINK" ] && doctor_ok "systemd Web 服务入口存在：$WEB_SYSTEMD_SERVICE_LINK" || doctor_warn "systemd Web 服务入口不存在：$WEB_SYSTEMD_SERVICE_LINK"
            ;;
        plain)
            :
            ;;
    esac
    check_port "Web 管理" "$WEB_PORT"

    say ""
    step "检查资源"
    if have df; then
        avail="$(df -k "$WORKDIR" 2>/dev/null | awk 'NR==2 {print $4}')"
        if [ -n "$avail" ]; then
            if [ "$avail" -lt 10240 ] 2>/dev/null; then
                doctor_warn "磁盘可用空间偏低：${avail}KB"
            else
                doctor_ok "磁盘可用空间：${avail}KB"
            fi
        else
            doctor_warn "无法读取磁盘空间"
        fi
    else
        doctor_warn "无法检查磁盘空间：df 不存在"
    fi

    if have free; then
        mem_avail="$(free -k 2>/dev/null | awk '/Mem:/ {print $7}')"
        [ -n "$mem_avail" ] || mem_avail="$(free -k 2>/dev/null | awk '/Mem:/ {print $4}')"
        if [ -n "$mem_avail" ]; then
            if [ "$mem_avail" -lt 32768 ] 2>/dev/null; then
                doctor_warn "可用内存偏低：${mem_avail}KB"
            else
                doctor_ok "可用内存：${mem_avail}KB"
            fi
        else
            doctor_warn "无法读取内存信息"
        fi
    else
        doctor_warn "无法检查内存：free 不存在"
    fi

    say ""
    info "诊断汇总：OK=$DOCTOR_OK WARN=$DOCTOR_WARN ERROR=$DOCTOR_FAIL"
    if [ "$DOCTOR_FAIL" -gt 0 ]; then
        err "诊断发现严重问题，请优先处理 ERROR 项"
        return 1
    fi
    if [ "$DOCTOR_WARN" -gt 0 ]; then
        warn "诊断完成，有 WARN 项需要关注"
        return 0
    fi
    ok "诊断完成，未发现明显问题"
}

cmd_version() {
    info "mgate 版本：$MGATE_VERSION"
    info "工作目录：$WORKDIR"
    if self_url="$(get_self_url 2>/dev/null || true)" && [ -n "$self_url" ]; then
        info "更新地址：$self_url"
    else
        warn "更新地址未配置"
    fi
    if [ -x "$CORE_BIN" ]; then
        core_ver="$($CORE_BIN -v 2>/dev/null || true)"
        [ -n "$core_ver" ] || core_ver="$CORE_BIN"
        info "Mihomo 版本：$core_ver"
    else
        warn "Mihomo 未安装"
    fi
}

usage() {
    cat <<EOF_USAGE
$APP_NAME - $APP_DESC

Usage:
  mgate                     Enter TUI menu
  mgate install             Initialize/repair mgate workspace, core, config and service
  mgate self-update         Update mgate manager script from GitHub
  mgate update              Alias of self-update
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
  mgate logs [50|100|200]   Show recent logs
  mgate doctor              Run system diagnostics
  mgate version             Show versions

  mgate web-enable          Enable and start Web manager
  mgate web-disable         Disable and stop Web manager
  mgate web-start           Start Web manager
  mgate web-stop            Stop Web manager
  mgate web-restart         Restart Web manager
  mgate web-status          Show Web manager status
  mgate web-token [reset]   Show or reset Web token
  mgate web-refresh         Regenerate Web files

  mgate help                Show this help

Environment:
  FORCE=1                         overwrite generated config after backup
  MGATE_ASSUME_YES=1              skip uninstall confirmation
  MGATE_MIHOMO_VERSION=v1.19.25   install a specific Mihomo version
  MGATE_MIHOMO_ASSET=linux-arm64  force Mihomo release asset
  MGATE_SELF_URL=https://.../       set mgate self-update URL
  MGATE_SELF_PROXY=https://.../     set self-update proxy; default follows MGATE_GITHUB_PROXY
  MGATE_GITHUB_PROXY=https://.../   set GitHub proxy prefix; default is $DEFAULT_GITHUB_PROXY
  MGATE_GITHUB_PROXY=direct         disable GitHub proxy and use direct download
EOF_USAGE
}

menu() {
    while :; do
        say ""
        say "mgate - Mobile Gateway Manager"
        say "Workspace: $WORKDIR"
        say ""
        say "1)  初始化/修复 mgate 工作区"
        say "2)  更新 mgate 管理脚本（从 GitHub）"
        say "3)  安装/更新 Mihomo 内核"
        say "4)  卸载 Mihomo 内核"
        say "5)  完整卸载 mgate"
        say ""
        say "6)  启动服务"
        say "7)  停止服务"
        say "8)  重启服务"
        say "9)  查看服务状态"
        say ""
        say "10) 设置开机启动"
        say "11) 关闭开机启动"
        say ""
        say "12) 查看配置"
        say "13) 编辑配置"
        say "14) 测试配置"
        say "15) 查看日志"
        say "16) 系统诊断"
        say "17) 查看版本"
        say ""
        say "Web 管理"
        say "18) 开启 Web 管理"
        say "19) 关闭 Web 管理"
        say "20) 启动 Web 管理"
        say "21) 停止 Web 管理"
        say "22) 查看 Web 管理状态"
        say "23) 重置 Web 管理 Token"
        say "24) 刷新 Web 管理文件"
        say ""
        say "0)  退出"
        printf '请选择: '
        read -r choice
        case "$choice" in
            1) cmd_install; pause_enter ;;
            2) cmd_self_update; pause_enter ;;
            3) install_core; pause_enter ;;
            4) cmd_uninstall_core; pause_enter ;;
            5) cmd_uninstall; exit 0 ;;
            6) service_start; pause_enter ;;
            7) service_stop; pause_enter ;;
            8) service_restart; pause_enter ;;
            9) service_status; pause_enter ;;
            10) service_enable; pause_enter ;;
            11) service_disable; pause_enter ;;
            12) cmd_config; pause_enter ;;
            13) cmd_edit; pause_enter ;;
            14) cmd_test; pause_enter ;;
            15) cmd_logs; pause_enter ;;
            16) cmd_doctor; pause_enter ;;
            17) cmd_version; pause_enter ;;
            18) web_enable; pause_enter ;;
            19) web_disable; pause_enter ;;
            20) web_start; pause_enter ;;
            21) web_stop; pause_enter ;;
            22) web_status; pause_enter ;;
            23) web_token reset; pause_enter ;;
            24) web_refresh; pause_enter ;;
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
        self-update|update) cmd_self_update "$@" ;;
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
        doctor) cmd_doctor "$@" ;;
        version) cmd_version "$@" ;;
        web-enable) web_enable "$@" ;;
        web-disable) web_disable "$@" ;;
        web-start) web_start "$@" ;;
        web-stop) web_stop "$@" ;;
        web-restart) web_restart "$@" ;;
        web-status) web_status "$@" ;;
        web-token) web_token "$@" ;;
        web-refresh) web_refresh "$@" ;;
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
