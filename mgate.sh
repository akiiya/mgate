#!/bin/sh
# mgate - Mobile Gateway Manager for Mihomo
# POSIX/BusyBox friendly management script.

set -u
umask 022

APP_NAME="mgate"
APP_DESC="Mobile Gateway Manager"
MGATE_VERSION="0.3.12"

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
WEB_JOB_DIR="$RUN_DIR/web-jobs"
WEB_OPENWRT_SERVICE_FILE="$SERVICE_DIR/mgate-web.init"
WEB_SYSTEMD_SERVICE_FILE="$SERVICE_DIR/mgate-web.service"
WEB_OPENWRT_SERVICE_LINK="/etc/init.d/mgate-web"
WEB_SYSTEMD_SERVICE_LINK="/etc/systemd/system/mgate-web.service"

DEFAULT_MIXED_PORT="${MIXED_PORT:-31800}"
# Backward-compatible internal aliases. The default proxy entry is now a single mixed listener.
DEFAULT_SOCKS_PORT="$DEFAULT_MIXED_PORT"
DEFAULT_HTTP_PORT="$DEFAULT_MIXED_PORT"

REPO="MetaCubeX/mihomo"
GITHUB_RELEASE_BASE="https://github.com/$REPO/releases"
GITHUB_API_LATEST="https://api.github.com/repos/$REPO/releases/latest"
DEFAULT_MIHOMO_VERSION="${MGATE_DEFAULT_MIHOMO_VERSION:-v1.19.25}"
DEFAULT_GITHUB_PROXY="https://gh-proxy.fastly.eu.org/"
DEFAULT_SELF_URL="${MGATE_DEFAULT_SELF_URL:-https://raw.githubusercontent.com/akiiya/mgate/main/mgate.sh}"
MGATE_CONNECT_TIMEOUT="${MGATE_CONNECT_TIMEOUT:-20}"
MGATE_DOWNLOAD_TIMEOUT="${MGATE_DOWNLOAD_TIMEOUT:-180}"
SELF_URL_FILE="$DATA_DIR/self.url"

SUB_URL_FILE="$DATA_DIR/sub.url"
SUB_STATUS_FILE="$DATA_DIR/sub.status"
SUB_COUNTRIES_FILE="$DATA_DIR/sub.countries"
SUB_ACCOUNTS_FILE="$DATA_DIR/accounts.txt"
ACCOUNT_DEFAULT_PASSWORD_FILE="$DATA_DIR/account.default_password"
DEFAULT_ACCOUNT_PASSWORD="12345678"
SUB_LAST_UPDATE_FILE="$DATA_DIR/sub.last_update"
SUB_PROVIDER_DIR="$CONFIG_DIR/providers"
SUB_PROVIDER_FILE="$SUB_PROVIDER_DIR/sub.yaml"
SUB_USER_AGENT="${MGATE_SUB_USER_AGENT:-Clash.Meta}"
SUB_LAST_LOG_FILE="$LOG_DIR/sub-update.last.log"
SUB_LAST_TMP_FILE="$DATA_DIR/sub.last_tmp"

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
    mkdir -p "$WEB_DIR" "$WEB_CGI_DIR" "$WEB_STATIC_DIR" "$WEB_JOB_DIR" || die "failed to create $WEB_DIR"
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
        curl -fsSL --connect-timeout "$MGATE_CONNECT_TIMEOUT" --max-time "$MGATE_DOWNLOAD_TIMEOUT" "$url"
        return $?
    fi
    if have wget; then
        wget -T "$MGATE_DOWNLOAD_TIMEOUT" -qO- "$url"
        return $?
    fi
    return 127
}

download_file() {
    url="$1"
    out="$2"
    if have curl; then
        curl -fL \
            --connect-timeout "$MGATE_CONNECT_TIMEOUT" \
            --max-time "$MGATE_DOWNLOAD_TIMEOUT" \
            -H "Cache-Control: no-cache" \
            -H "Pragma: no-cache" \
            -o "$out" "$url"
        return $?
    fi
    if have wget; then
        wget -T "$MGATE_DOWNLOAD_TIMEOUT" -O "$out" "$url"
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

# Mixed listener supports both HTTP and SOCKS5 proxy protocols on one port.
# Client examples:
#   HTTP   http://DE:change_me_de@192.168.8.1:__MIXED_PORT__
#   SOCKS5 socks5://DE:change_me_de@192.168.8.1:__MIXED_PORT__
authentication:
  - "DE:change_me_de"
  - "JP:change_me_jp"
  - "US:change_me_us"
  - "UK:change_me_uk"

listeners:
  - name: mixed-users
    type: mixed
    listen: 0.0.0.0
    port: __MIXED_PORT__
    udp: true

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
        -e "s/__MIXED_PORT__/$DEFAULT_MIXED_PORT/g" \
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

Default listener:
  Mixed:  0.0.0.0:$DEFAULT_MIXED_PORT

Default users:
  DE / JP / US / UK

Client examples:
  http://DE:change_me_de@192.168.8.1:$DEFAULT_MIXED_PORT
  socks5://DE:change_me_de@192.168.8.1:$DEFAULT_MIXED_PORT

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
  MIXED_PORT=31800                override default mixed proxy port during config generation
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
ExecStartPre=/bin/sleep 10
ExecStart=$CORE_BIN -d $CONFIG_DIR
Restart=always
RestartSec=10
StartLimitIntervalSec=0
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
    hint "如需更新 mgate 管理脚本：mgate self-update"
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

detect_package_manager() {
    if have apt-get; then printf 'apt-get\n'; return 0; fi
    if have apk;     then printf 'apk\n';     return 0; fi
    if have opkg;    then printf 'opkg\n';    return 0; fi
    if have yum;     then printf 'yum\n';     return 0; fi
    if have dnf;     then printf 'dnf\n';     return 0; fi
    return 1
}

ensure_httpd_available() {
    find_httpd_cmd >/dev/null 2>&1 && return 0

    warn "未找到可用的 httpd（需要 busybox httpd applet）"
    pm="$(detect_package_manager 2>/dev/null || true)"
    case "$pm" in
        apt-get) hint "安装命令：apt-get install -y busybox" ;;
        apk)     hint "安装命令：apk add busybox" ;;
        opkg)    hint "安装命令：opkg update && opkg install busybox" ;;
        yum|dnf) hint "安装命令：$pm install -y busybox" ;;
        *)       hint "请手动安装包含 httpd applet 的 busybox 后重试" ; return 1 ;;
    esac

    if [ "${MGATE_ASSUME_YES:-0}" != "1" ] && [ ! -t 0 ]; then
        err "非交互模式，请手动安装 busybox 后重试"
        return 1
    fi

    if [ "${MGATE_ASSUME_YES:-0}" != "1" ]; then
        printf '是否现在自动安装 busybox？[y/N] '
        read -r _httpd_ans
        case "$_httpd_ans" in
            y|Y|yes|YES) : ;;
            *) info "已取消，Web 管理不会启动"; return 1 ;;
        esac
    fi

    step "正在安装 busybox..."
    case "$pm" in
        apt-get) apt-get install -y busybox ;;
        apk)     apk add busybox ;;
        opkg)    opkg update && opkg install busybox ;;
        yum|dnf) "$pm" install -y busybox ;;
    esac || die "busybox 安装失败，请手动安装后重试"

    if find_httpd_cmd >/dev/null 2>&1; then
        ok "busybox 安装成功，httpd 可用"
        return 0
    fi
    die "安装后仍未找到 httpd applet，busybox 可能未包含 httpd，请检查"
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
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/cgi-bin/mgate.cgi"><link rel="icon" type="image/svg+xml" href="/favicon.svg?v=0.2.9"><title>mgate</title></head><body><a href="/cgi-bin/mgate.cgi">mgate Web</a></body></html>
EOF_WEB_INDEX
}

generate_web_style() {
    cat > "$WEB_CSS_FILE" <<'EOF_WEB_CSS'
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;margin:0;background:#f6f7f9;color:#222}.wrap{max-width:1080px;margin:0 auto;padding:20px}.card{background:#fff;border:1px solid #ddd;border-radius:10px;padding:16px;margin:14px 0;box-shadow:0 1px 2px rgba(0,0,0,.04)}h1{font-size:24px;margin:0 0 8px}h2{font-size:18px;margin:0 0 12px}h3{font-size:15px;margin:0 0 6px}.muted{color:#666;font-size:13px}.nav{display:flex;flex-wrap:wrap;gap:8px}.btn,button{display:inline-block;border:1px solid #bbb;border-radius:8px;background:#fff;color:#222;padding:8px 12px;text-decoration:none;font-size:14px;cursor:pointer}.btn:hover,button:hover{background:#f0f0f0}.danger{border-color:#c33;color:#a00}.primary{border-color:#2673d9;color:#0756b1}.good{border-color:#16a34a}.warn{border-color:#d97706}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:12px}.mini{background:#fff;border:1px solid #ddd;border-radius:10px;padding:14px}.mini strong{display:block;font-size:16px;margin-top:4px;word-break:break-word}.mini span{color:#666;font-size:12px}.table{width:100%;border-collapse:collapse}.table th,.table td{border-bottom:1px solid #eee;padding:8px;text-align:left;vertical-align:top;font-size:13px}.code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;background:#f2f2f2;border-radius:6px;padding:2px 5px;word-break:break-all}pre{background:#111;color:#eee;padding:12px;border-radius:8px;overflow:auto;white-space:pre-wrap;word-break:break-word}.row{margin:8px 0}input[type=password],input[type=text]{padding:8px;border:1px solid #bbb;border-radius:6px;min-width:260px}.footer{margin-top:20px;color:#777;font-size:12px}.split{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.pill{display:inline-block;border:1px solid #ddd;border-radius:999px;padding:3px 8px;font-size:12px;color:#555;background:#fafafa}details{margin:8px 0}summary{cursor:pointer;color:#0756b1}
EOF_WEB_CSS
}
generate_mgate_cgi() {
    cat > "$WEB_CGI_FILE" <<'EOF_WEB_CGI'
#!/bin/sh

MGATE="__MGATE_PATH__"
TOKEN_FILE="__WEB_TOKEN_FILE__"
CONFIG_FILE="__CONFIG_FILE__"
WEB_PORT="__WEB_PORT__"
WEB_JOB_DIR="__WEB_JOB_DIR__"
DEFAULT_MIXED_PORT="__DEFAULT_MIXED_PORT__"
DEFAULT_HTTP_PORT="$DEFAULT_MIXED_PORT"
DEFAULT_SOCKS_PORT="$DEFAULT_MIXED_PORT"
FAVICON_VER="0.3.7"

html_escape() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

param_get() {
    data="$1"
    key="$2"
    printf '%s' "&$data&" | sed -n "s/.*[&]$key=\([^&]*\).*/\1/p" | head -n 1
}

url_decode() {
    # Decode application/x-www-form-urlencoded values. BusyBox printf supports \xHH on common builds.
    v="$(printf '%s' "$1" | sed 's/+/ /g; s/%/\\x/g')"
    printf '%b' "$v"
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

_CGI_EXTRA_HEADER=""
header() {
    if [ -n "${1:-}" ]; then
        _CGI_EXTRA_HEADER="$1"
    fi
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
<a class="btn" href="/cgi-bin/mgate.cgi?action=account-password">账号密码</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=sub-status">订阅状态</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=sub-set">设置订阅</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=confirm&target=sub-update">更新订阅</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=sub-clear">清除订阅</a>
<a class="btn primary" href="/cgi-bin/mgate.cgi?action=start">启动服务</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=stop">停止服务</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=restart">重启服务</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=test">测试配置</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logs&lines=100">查看日志</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=config">查看配置</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=backups">备份</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=backup">创建备份</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=token">Token</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=self-update">自更新</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=web-disable">关闭 Web 管理</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=logout">退出登录</a>
</div></div>
EOF
}

page_end() {
    host_display="${HTTP_HOST:-0.0.0.0:$WEB_PORT}"
    cat <<EOF
<div class="footer">
  <div>访问地址：<span class="code">http://$(printf '%s' "$host_display" | html_escape)</span></div>
  <div>mgate Web 仅建议在局域网内使用，请不要暴露到公网。</div>
</div>
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
    header
    page_start "$title"
    nav
    printf '<div class="card"><h2>%s</h2><pre>' "$(printf '%s' "$title" | html_escape)"
    output="$($MGATE "$@" 2>&1)"
    rc=$?
    printf '%s\n' "$output" | html_escape
    printf '\nexit code: %s' "$rc" | html_escape
    printf '</pre></div>\n'
    page_end
}

job_cleanup() {
    mkdir -p "$WEB_JOB_DIR" 2>/dev/null || return 0
    # Keep the newest 20 jobs. Each job has .log/.status/.meta files.
    ls -1t "$WEB_JOB_DIR"/*.status 2>/dev/null | sed -n '21,$p' | while IFS= read -r st; do
        base="${st%.status}"
        rm -f "$base.status" "$base.log" "$base.meta" 2>/dev/null || true
    done
}

job_id_new() {
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    printf '%s-%s\n' "$ts" "$$"
}

job_page() {
    id="$1"
    case "$id" in ''|*/*|*..*|*\\*) id="" ;; esac
    header
    page_start "任务状态"
    nav
    if [ -z "$id" ]; then
        cat <<'EOF'
<div class="card"><h2>任务不存在</h2><p>无效的任务 ID。</p></div>
EOF
        page_end
        return 0
    fi
    base="$WEB_JOB_DIR/$id"
    status="$(sed -n '1p' "$base.status" 2>/dev/null)"
    [ -n "$status" ] || status="unknown"
    title="$(sed -n '1p' "$base.meta" 2>/dev/null)"
    [ -n "$title" ] || title="$id"
    if [ "$status" = "running" ]; then
        cat <<'EOF'
<script>
setTimeout(function(){ window.location.reload(); }, 2000);
</script>
EOF
    fi
    printf '<div class="card"><h2>%s</h2>' "$(printf '%s' "$title" | html_escape)"
    printf '<p>任务 ID：<span class="code">%s</span></p>' "$(printf '%s' "$id" | html_escape)"
    printf '<p>状态：<span class="pill">%s</span></p>' "$(printf '%s' "$status" | html_escape)"
    if [ "$status" = "running" ]; then
        printf '<p class="muted">任务正在后台执行，页面会自动刷新。</p>'
    fi
    printf '<pre>'
    if [ -f "$base.log" ]; then
        tail -n 200 "$base.log" 2>/dev/null | html_escape
    else
        printf '暂无日志' | html_escape
    fi
    printf '</pre>'
    printf '<p><a class="btn" href="/cgi-bin/mgate.cgi?action=job&id=%s">刷新</a> <a class="btn" href="/cgi-bin/mgate.cgi?action=status">返回首页</a></p>' "$(printf '%s' "$id" | html_escape)"
    printf '</div>\n'
    page_end
}

run_job_page() {
    title="$1"
    shift
    mkdir -p "$WEB_JOB_DIR" 2>/dev/null || { run_output_page "$title" "$@"; return 0; }
    job_cleanup
    id="$(job_id_new)"
    base="$WEB_JOB_DIR/$id"
    printf 'running\n' > "$base.status"
    printf '%s\n' "$title" > "$base.meta"
    (
        printf '[STEP] 开始执行：%s\n' "$title"
        printf '[INFO] 命令：mgate'
        for a in "$@"; do printf ' %s' "$a"; done
        printf '\n'
        "$MGATE" "$@"
        rc=$?
        printf '[INFO] exit code: %s\n' "$rc"
        if [ "$rc" -eq 0 ]; then
            printf 'success\n' > "$base.status"
        else
            printf 'failed\n' > "$base.status"
        fi
    ) </dev/null > "$base.log" 2>&1 3>&- &
    _CGI_LOCATION="/cgi-bin/mgate.cgi?action=job&id=$id"
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
    header
    page_start "状态"
    nav
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

    cat <<'EOF'
<div class="card"><h2>状态概览</h2><div class="grid">
EOF
    summary_card "mgate 服务" "$svc_line" "$svc_class"
    summary_card "Mihomo 内核" "$core_line" "$core_class"
    summary_card "开机自启" "$boot_line" "$boot_class"
    summary_card "配置文件" "$cfg_line" "$cfg_class"
    summary_card "Mixed 代理" "$DEFAULT_MIXED_PORT" ""
    summary_card "支持协议" "HTTP / SOCKS5" ""
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
        sub-update) label="更新订阅并重建配置" ;;
        sub-clear) label="清除订阅设置和缓存" ;;
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
<details><summary>显示当前 Token</summary><p><span class="code">$(printf '%s' "$tok" | html_escape)</span></p></details>
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
    mixed_port="$(listener_port mixed-users "$DEFAULT_MIXED_PORT")"

    header
    page_start "连接信息"
    nav
    cat <<EOF
<div class="card">
<h2>代理连接信息</h2>
<p class="muted">Mixed 端口同时支持 HTTP 和 SOCKS5 协议。客户端里仍需选择对应代理协议，但端口统一使用 $mixed_port。</p>
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
            http_url="http://$user:$pass@$host:$mixed_port"
            socks_url="socks5://$user:$pass@$host:$mixed_port"
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

account_password_page() {
    header
    page_start "账号密码"
    nav
    out="$($MGATE account-password 2>&1)"
    cat <<'EOF'
<div class="card">
<h2>代理账号默认密码</h2>
<p class="muted">订阅模式下自动生成的国家/地区账号会统一使用此默认密码。</p>
<pre>
EOF
    printf '%s\n' "$out" | html_escape
    cat <<'EOF'
</pre>
<form method="POST" action="/cgi-bin/mgate.cgi">
<input type="hidden" name="action" value="account-password-set">
<div class="row"><input type="text" name="password" placeholder="新的默认密码，例如 12345678" autocomplete="off"></div>
<div class="row"><button class="primary" type="submit">修改默认密码</button></div>
</form>
<p class="muted">密码建议只使用字母和数字，不要包含空格、冒号或引号。修改后会重新更新订阅配置。</p>
</div>
EOF
    page_end
}


sub_status_page() {
    header
    page_start "订阅状态"
    nav
    out="$($MGATE sub-status 2>&1)"
    cat <<'EOF'
<div class="card">
<h2>订阅状态</h2>
<pre>
EOF
    printf '%s\n' "$out" | html_escape
    cat <<'EOF'
</pre>
<p><a class="btn primary" href="/cgi-bin/mgate.cgi?action=sub-set">设置/替换订阅</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=confirm&target=sub-update">更新订阅</a>
<a class="btn danger" href="/cgi-bin/mgate.cgi?action=confirm&target=sub-clear">清除订阅</a></p>
</div>
EOF
    page_end
}

sub_set_page() {
    header
    page_start "设置订阅"
    nav
    out="$($MGATE sub-status 2>&1)"
    cat <<'EOF'
<div class="card">
<h2>设置/替换订阅链接</h2>
<p class="muted">仅支持 Clash / Mihomo YAML 订阅。提交后会立即拉取订阅、识别国家/地区、生成账号和配置。</p>
<form method="POST" action="/cgi-bin/mgate.cgi">
<input type="hidden" name="action" value="sub-set-do">
<div class="row"><input type="text" name="sub_url" placeholder="https://example.com/clash.yaml" autocomplete="off"></div>
<div class="row"><button class="primary" type="submit">保存并立即更新</button></div>
</form>
</div>
<div class="card"><h2>当前订阅状态</h2><pre>
EOF
    printf '%s\n' "$out" | html_escape
    cat <<'EOF'
</pre></div>
EOF
    page_end
}

logs_page() {
    lines="$1"
    case "$lines" in 50|100|200) : ;; *) lines="100" ;; esac
    header
    page_start "日志"
    nav
    output="$($MGATE logs "$lines" 2>&1)"
    rc=$?
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

# Buffer all HTML output to a temp file so we can send Content-Length.
# Without Content-Length, HTTP/1.1 keep-alive causes Chrome to spin forever
# waiting for the connection to close.
_CGI_LOCATION=""
_CGI_BODY="/tmp/.mgate-cgi-$$"
exec 3>&1
exec 1>"$_CGI_BODY"

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
    else
        login_page "Token 错误"
    fi
elif [ "$action" = "logout" ]; then
    header "Set-Cookie: mgate_token=deleted; Path=/; Max-Age=0"
    page_start "Logout"
    cat <<'EOF'
<div class="card"><h2>已退出</h2><p><a class="btn" href="/cgi-bin/mgate.cgi">重新登录</a></p></div>
EOF
    page_end
elif ! is_logged_in; then
    login_page ""
else
    case "$action" in
        status) status_page ;;
        job) job_page "$(param_get "${QUERY_STRING:-}" id)" ;;
        version) run_output_page "版本" version ;;
        doctor) run_output_page "系统诊断" doctor ;;
        proxy-info) proxy_info_page ;;
        account-password) account_password_page ;;
        sub-status) sub_status_page ;;
        sub-set) sub_set_page ;;
        sub-set-do)
            sub_url="$(url_decode "$(param_get "$post_body" sub_url)")"
            run_job_page "设置/替换订阅" sub-set "$sub_url"
            ;;
        account-password-set)
            pw="$(param_get "$post_body" password)"
            run_job_page "修改代理账号默认密码" account-password set "$pw"
            ;;
        start) run_job_page "启动服务" start ;;
        test) run_output_page "测试配置" test ;;
        logs) logs_page "$lines" ;;
        config) run_output_page "当前配置" config ;;
        backups) run_output_page "备份列表" backups ;;
        backup) run_job_page "创建备份" backup web ;;
        token) token_page ;;
        confirm)
            case "$target" in
                stop|restart|self-update|web-disable|token-reset|sub-update|sub-clear) confirm_page "$target" ;;
                *) status_page ;;
            esac
            ;;
        do)
            case "$target" in
                stop) run_job_page "停止服务" stop ;;
                restart) run_job_page "重启服务" restart ;;
                self-update) run_job_page "自更新 mgate" self-update ;;
                sub-update) run_job_page "更新订阅" sub-update ;;
                sub-clear) run_job_page "清除订阅" sub-clear ;;
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
                    page_start "关闭 Web 管理"
                    cat <<'EOF'
<div class="card"><h2>Web 管理即将关闭</h2><p>请稍等几秒后关闭此页面。</p></div>
EOF
                    page_end
                    (
                        sleep 1
                        "$MGATE" web-disable >/dev/null 2>&1
                    ) </dev/null >/dev/null 2>&1 &
                    ;;
                *) status_page ;;
            esac
            ;;
        *) status_page ;;
    esac
fi

exec 1>&3
exec 3>&-
if [ -n "$_CGI_LOCATION" ]; then
    printf 'Status: 302 Found\r\n'
    printf 'Location: %s\r\n' "$_CGI_LOCATION"
    printf 'Content-Length: 0\r\n'
    printf 'Connection: close\r\n'
    [ -n "$_CGI_EXTRA_HEADER" ] && printf '%s\r\n' "$_CGI_EXTRA_HEADER"
    printf '\r\n'
    rm -f "$_CGI_BODY"
else
    _CGI_BODY_LEN="$(wc -c < "$_CGI_BODY" 2>/dev/null || echo 0)"
    printf 'Content-Type: text/html; charset=utf-8\r\n'
    printf 'Content-Length: %s\r\n' "$_CGI_BODY_LEN"
    printf 'Cache-Control: no-store\r\n'
    printf 'Connection: close\r\n'
    [ -n "$_CGI_EXTRA_HEADER" ] && printf '%s\r\n' "$_CGI_EXTRA_HEADER"
    printf '\r\n'
    cat "$_CGI_BODY"
    rm -f "$_CGI_BODY"
fi
exit 0
EOF_WEB_CGI

    sed -i \
        -e "s#__MGATE_PATH__#$SCRIPT_PATH#g" \
        -e "s#__WEB_TOKEN_FILE__#$WEB_TOKEN_FILE#g" \
        -e "s#__CONFIG_FILE__#$CONFIG_FILE#g" \
        -e "s#__WEB_PORT__#$WEB_PORT#g" \
        -e "s#__WEB_JOB_DIR__#$WEB_JOB_DIR#g" \
        -e "s#__DEFAULT_MIXED_PORT__#$DEFAULT_MIXED_PORT#g" \
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
ExecStartPre=/bin/sleep 10
ExecStart=$httpd_cmd -f -p $WEB_LISTEN:$WEB_PORT -h $WEB_DIR
Restart=always
RestartSec=10
StartLimitIntervalSec=0

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
    ensure_httpd_available || return 1
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
    ensure_httpd_available || return 1
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


backup_copy_dir() {
    src="$1"
    dst="$2"
    if [ -d "$src" ]; then
        mkdir -p "$(dirname "$dst")" || return 1
        cp -pR "$src" "$dst" || return 1
    fi
}

create_backup() {
    label="${1:-manual}"
    ensure_dirs
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    safe_label="$(printf '%s' "$label" | sed 's/[^A-Za-z0-9_.-]/_/g')"
    [ -n "$safe_label" ] || safe_label="manual"
    backup_id="$ts-$safe_label"
    backup_dir="$BACKUP_DIR/$backup_id"

    mkdir -p "$backup_dir" || die "创建备份目录失败：$backup_dir"

    if [ -d "$CONFIG_DIR" ]; then
        cp -pR "$CONFIG_DIR" "$backup_dir/config" || die "备份配置目录失败"
    fi
    if [ -d "$DATA_DIR" ]; then
        cp -pR "$DATA_DIR" "$backup_dir/data" || die "备份数据目录失败"
    fi
    if [ -d "$SERVICE_DIR" ]; then
        cp -pR "$SERVICE_DIR" "$backup_dir/service" 2>/dev/null || true
    fi

    {
        printf 'id=%s\n' "$backup_id"
        printf 'time=%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
        printf 'label=%s\n' "$safe_label"
        printf 'mgate_version=%s\n' "$MGATE_VERSION"
        printf 'workdir=%s\n' "$WORKDIR"
    } > "$backup_dir/manifest.txt"

    printf '%s\n' "$backup_id"
}

latest_backup_id() {
    ensure_dirs
    for d in $(ls -1dt "$BACKUP_DIR"/* 2>/dev/null); do
        [ -d "$d" ] || continue
        [ -f "$d/manifest.txt" ] || continue
        basename "$d"
        return 0
    done
    return 1
}

backup_exists() {
    id="$1"
    [ -n "$id" ] && [ -d "$BACKUP_DIR/$id" ] && [ -f "$BACKUP_DIR/$id/manifest.txt" ]
}

cmd_backup() {
    need_root
    label="${1:-manual}"
    step "正在创建备份"
    id="$(create_backup "$label")" || die "创建备份失败"
    ok "备份已创建：$id"
    info "备份目录：$BACKUP_DIR/$id"
}

cmd_backups() {
    ensure_dirs
    step "备份列表"
    found=0
    for d in $(ls -1dt "$BACKUP_DIR"/* 2>/dev/null); do
        [ -d "$d" ] || continue
        [ -f "$d/manifest.txt" ] || continue
        id="$(basename "$d")"
        time="$(sed -n 's/^time=//p' "$d/manifest.txt" 2>/dev/null | head -n 1)"
        label="$(sed -n 's/^label=//p' "$d/manifest.txt" 2>/dev/null | head -n 1)"
        [ -n "$time" ] || time="unknown"
        [ -n "$label" ] || label="manual"
        info "$id  time=$time  label=$label"
        found=1
    done
    if [ "$found" = "0" ]; then
        warn "暂无备份"
    fi
}

choose_backup_interactive() {
    cmd_backups
    printf '请输入要恢复的备份 ID，或输入 latest 使用最新备份: '
    read -r chosen
    [ -n "$chosen" ] || return 1
    printf '%s\n' "$chosen"
}

confirm_restore() {
    id="$1"
    if [ "${MGATE_ASSUME_YES:-0}" = "1" ] || [ "${2:-}" = "--yes" ] || [ "${2:-}" = "-y" ]; then
        return 0
    fi
    warn "即将恢复备份：$id"
    warn "当前配置和数据会先自动备份，然后被该备份覆盖。"
    printf 'Type RESTORE to continue: '
    read -r ans
    [ "$ans" = "RESTORE" ] || die "restore cancelled"
}

cmd_restore() {
    need_root
    req="${1:-}"
    yes_arg="${2:-}"

    if [ -z "$req" ]; then
        if [ -t 0 ]; then
            req="$(choose_backup_interactive || true)"
        fi
        [ -n "$req" ] || die "请指定备份 ID，例如：mgate restore latest"
    fi

    if [ "$req" = "latest" ]; then
        id="$(latest_backup_id || true)"
        [ -n "$id" ] || die "没有可恢复的备份"
    else
        id="$req"
    fi

    backup_exists "$id" || die "备份不存在：$id"
    src="$BACKUP_DIR/$id"

    if [ -x "$CORE_BIN" ] && [ -f "$src/config/config.yaml" ]; then
        step "正在测试备份配置"
        if "$CORE_BIN" -t -f "$src/config/config.yaml" >/tmp/mgate-restore-test.out 2>&1; then
            ok "备份配置测试通过"
        else
            err "备份配置测试失败，已取消恢复"
            sed 's/^/[DETAIL] /' /tmp/mgate-restore-test.out 2>/dev/null | tail -n 30
            rm -f /tmp/mgate-restore-test.out
            return 1
        fi
        rm -f /tmp/mgate-restore-test.out
    else
        warn "跳过配置测试：Mihomo 内核或备份配置不存在"
    fi

    confirm_restore "$id" "$yes_arg"

    pre_id="$(create_backup pre-restore)" || die "恢复前备份失败"
    info "恢复前备份：$pre_id"

    step "正在恢复备份：$id"
    if [ -d "$src/config" ]; then
        rm -rf "$CONFIG_DIR"
        cp -pR "$src/config" "$CONFIG_DIR" || die "恢复配置失败"
    fi
    if [ -d "$src/data" ]; then
        rm -rf "$DATA_DIR"
        cp -pR "$src/data" "$DATA_DIR" || die "恢复数据失败"
    fi
    if [ -d "$src/service" ]; then
        rm -rf "$SERVICE_DIR"
        cp -pR "$src/service" "$SERVICE_DIR" 2>/dev/null || true
    fi

    ok "备份已恢复：$id"
    hint "建议执行：mgate test && mgate restart"
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
    mixed_port="$(config_listener_port mixed-users "$DEFAULT_MIXED_PORT")"
    check_port "Mixed 代理" "$mixed_port"

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


# -----------------------------
# Subscription management
# -----------------------------
ensure_sub_dirs() {
    ensure_dirs
    mkdir -p "$SUB_PROVIDER_DIR" || die "创建订阅目录失败：$SUB_PROVIDER_DIR"
}

sub_fetch_to_file() {
    url="$1"
    out="$2"
    ua="$SUB_USER_AGENT"
    if have curl; then
        curl -fsSL --connect-timeout 20 --max-time 120 \
            -A "$ua" \
            -H "Accept: application/yaml,text/yaml,text/plain,*/*" \
            -o "$out" "$url"
        return $?
    fi
    if have wget; then
        wget -T 120 \
            --user-agent="$ua" \
            --header="Accept: application/yaml,text/yaml,text/plain,*/*" \
            -O "$out" "$url"
        return $?
    fi
    die "需要 curl 或 wget 才能拉取订阅"
}

validate_sub_file() {
    file="$1"
    [ -s "$file" ] || die "订阅内容为空"
    if grep -Eiq '<html|<!doctype html|<body|</html>' "$file" 2>/dev/null; then
        die "订阅内容像 HTML 页面，不是 Clash/Mihomo YAML，请确认订阅链接格式"
    fi
    grep -Eq '^[[:space:]]*proxies[[:space:]]*:' "$file" 2>/dev/null || die "订阅内容未找到 proxies:，请使用 Clash/Mihomo YAML 订阅"
    grep -Eq '^[[:space:]]*-[[:space:]]*name[[:space:]]*:|^[[:space:]]*-[[:space:]]*\{[[:space:]]*name[[:space:]]*:' "$file" 2>/dev/null || die "订阅内容未找到节点 name 字段"
}

extract_sub_names() {
    file="$1"
    out="$2"
    : > "$out"
    # block style: - name: "JP Tokyo 01"
    sed -n "s/^[[:space:]]*-[[:space:]]*name[[:space:]]*:[[:space:]]*[\"']\{0,1\}\([^\"'#]*\).*/\1/p" "$file" >> "$out" 2>/dev/null || true
    # inline style: - { name: "JP Tokyo 01", type: vmess, ... }
    sed -n "s/.*name[[:space:]]*:[[:space:]]*[\"']\([^\"'}]*\)[\"'].*/\1/p" "$file" >> "$out" 2>/dev/null || true
    # remove empty and duplicates
    awk 'NF {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if (!seen[$0]++) print}' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
}

country_map() {
    # CODE|Label|grep -E regex for node names
    # Expanded in v0.3.6: flags, English names, ISO alpha-2/alpha-3 codes, and common aliases/cities.
    cat <<'EOF_COUNTRY_MAP'
HK|香港|🇭🇰|香港|hong[ -_]*kong|hongkong|(^|[^a-z0-9])hkg([^a-z0-9]|$)|(^|[^a-z0-9])hk([^a-z0-9]|$)|港区|港節點|港节点|港專|港专|hong[ -_]*kong[ -_]*special[ -_]*administrative[ -_]*region[ -_]*of[ -_]*china
TW|台湾|🇹🇼|台湾|台灣|taiwan|taipei|kaohsiung|(^|[^a-z0-9])tw([^a-z0-9]|$)|(^|[^a-z0-9])twn([^a-z0-9]|$)|台北|高雄|taiwan,[ -_]*province[ -_]*of[ -_]*china
MO|澳门|🇲🇴|澳门|澳門|macau|macao|(^|[^a-z0-9])mo([^a-z0-9]|$)|(^|[^a-z0-9])mac([^a-z0-9]|$)|macao[ -_]*special[ -_]*administrative[ -_]*region[ -_]*of[ -_]*china
JP|日本|🇯🇵|日本|japan|tokyo|osaka|(^|[^a-z0-9])jp([^a-z0-9]|$)|(^|[^a-z0-9])jpn([^a-z0-9]|$)|东京|東京|大阪|名古屋|nagoya|樱花|櫻花
KR|韩国|🇰🇷|韩国|韓國|korea|south[ -_]*korea|seoul|(^|[^a-z0-9])kr([^a-z0-9]|$)|(^|[^a-z0-9])kor([^a-z0-9]|$)|首尔|首爾|仁川|incheon|korea,[ -_]*republic[ -_]*of
SG|新加坡|🇸🇬|新加坡|singapore|(^|[^a-z0-9])sg([^a-z0-9]|$)|(^|[^a-z0-9])sgp([^a-z0-9]|$)|狮城|獅城|republic[ -_]*of[ -_]*singapore
US|美国|🇺🇸|美国|美國|united[ -_]*states|(^|[^a-z0-9])usa([^a-z0-9]|$)|america|los[ -_]*angeles|san[ -_]*jose|new[ -_]*york|chicago|dallas|seattle|(^|[^a-z0-9])us([^a-z0-9]|$)|美西|美东|美東|洛杉矶|洛杉磯|圣何塞|聖荷西|纽约|紐約|united[ -_]*states[ -_]*of[ -_]*america
UK|英国|🇬🇧|英国|英國|united[ -_]*kingdom|great[ -_]*britain|britain|england|london|(^|[^a-z0-9])uk([^a-z0-9]|$)|(^|[^a-z0-9])gb([^a-z0-9]|$)|(^|[^a-z0-9])gbr([^a-z0-9]|$)|伦敦|倫敦|united[ -_]*kingdom[ -_]*of[ -_]*great[ -_]*britain[ -_]*and[ -_]*northern[ -_]*ireland
DE|德国|🇩🇪|德国|德國|germany|(^|[^a-z0-9])deu([^a-z0-9]|$)|frankfurt|berlin|(^|[^a-z0-9])de([^a-z0-9]|$)|法兰克福|法蘭克福|柏林|federal[ -_]*republic[ -_]*of[ -_]*germany
FR|法国|🇫🇷|法国|法國|france|paris|(^|[^a-z0-9])fr([^a-z0-9]|$)|(^|[^a-z0-9])fra([^a-z0-9]|$)|巴黎|french[ -_]*republic
NL|荷兰|🇳🇱|荷兰|荷蘭|netherlands|holland|amsterdam|(^|[^a-z0-9])nl([^a-z0-9]|$)|(^|[^a-z0-9])nld([^a-z0-9]|$)|阿姆斯特丹|kingdom[ -_]*of[ -_]*the[ -_]*netherlands
CA|加拿大|🇨🇦|加拿大|canada|toronto|vancouver|montreal|(^|[^a-z0-9])ca([^a-z0-9]|$)|(^|[^a-z0-9])can([^a-z0-9]|$)|多伦多|多倫多|温哥华|溫哥華
AU|澳大利亚|🇦🇺|澳大利亚|澳大利亞|澳洲|australia|sydney|melbourne|(^|[^a-z0-9])au([^a-z0-9]|$)|(^|[^a-z0-9])aus([^a-z0-9]|$)|悉尼|墨尔本|墨爾本
NZ|新西兰|🇳🇿|新西兰|新西蘭|new[ -_]*zealand|auckland|(^|[^a-z0-9])nz([^a-z0-9]|$)|(^|[^a-z0-9])nzl([^a-z0-9]|$)|奥克兰|奧克蘭
IT|意大利|🇮🇹|意大利|italy|milan|rome|(^|[^a-z0-9])ita([^a-z0-9]|$)|米兰|米蘭|罗马|羅馬|italian[ -_]*republic
ES|西班牙|🇪🇸|西班牙|spain|madrid|barcelona|(^|[^a-z0-9])es([^a-z0-9]|$)|(^|[^a-z0-9])esp([^a-z0-9]|$)|马德里|馬德里|巴塞罗那|kingdom[ -_]*of[ -_]*spain
PT|葡萄牙|🇵🇹|葡萄牙|portugal|lisbon|(^|[^a-z0-9])pt([^a-z0-9]|$)|(^|[^a-z0-9])prt([^a-z0-9]|$)|里斯本|portuguese[ -_]*republic
SE|瑞典|🇸🇪|瑞典|sweden|stockholm|(^|[^a-z0-9])se([^a-z0-9]|$)|(^|[^a-z0-9])swe([^a-z0-9]|$)|斯德哥尔摩|斯德哥爾摩|kingdom[ -_]*of[ -_]*sweden
CH|瑞士|🇨🇭|瑞士|switzerland|zurich|zürich|geneva|(^|[^a-z0-9])ch([^a-z0-9]|$)|(^|[^a-z0-9])che([^a-z0-9]|$)|苏黎世|蘇黎世|日内瓦|日內瓦|swiss[ -_]*confederation
NO|挪威|🇳🇴|挪威|norway|oslo|(^|[^a-z0-9])nor([^a-z0-9]|$)|奥斯陆|奧斯陸|kingdom[ -_]*of[ -_]*norway
FI|芬兰|🇫🇮|芬兰|芬蘭|finland|helsinki|(^|[^a-z0-9])fi([^a-z0-9]|$)|(^|[^a-z0-9])fin([^a-z0-9]|$)|赫尔辛基|赫爾辛基|republic[ -_]*of[ -_]*finland
DK|丹麦|🇩🇰|丹麦|丹麥|denmark|copenhagen|(^|[^a-z0-9])dk([^a-z0-9]|$)|(^|[^a-z0-9])dnk([^a-z0-9]|$)|哥本哈根|kingdom[ -_]*of[ -_]*denmark
IE|爱尔兰|🇮🇪|爱尔兰|愛爾蘭|ireland|dublin|(^|[^a-z0-9])ie([^a-z0-9]|$)|(^|[^a-z0-9])irl([^a-z0-9]|$)|都柏林
PL|波兰|🇵🇱|波兰|波蘭|poland|warsaw|(^|[^a-z0-9])pl([^a-z0-9]|$)|(^|[^a-z0-9])pol([^a-z0-9]|$)|华沙|華沙|republic[ -_]*of[ -_]*poland
CZ|捷克|🇨🇿|捷克|czech|czechia|prague|(^|[^a-z0-9])cz([^a-z0-9]|$)|(^|[^a-z0-9])cze([^a-z0-9]|$)|布拉格|czech[ -_]*republic
AT|奥地利|🇦🇹|奥地利|奧地利|austria|vienna|(^|[^a-z0-9])aut([^a-z0-9]|$)|维也纳|維也納|republic[ -_]*of[ -_]*austria
BE|比利时|🇧🇪|比利时|比利時|belgium|brussels|(^|[^a-z0-9])bel([^a-z0-9]|$)|布鲁塞尔|布魯塞爾|kingdom[ -_]*of[ -_]*belgium
LU|卢森堡|🇱🇺|卢森堡|盧森堡|luxembourg|(^|[^a-z0-9])lu([^a-z0-9]|$)|(^|[^a-z0-9])lux([^a-z0-9]|$)|grand[ -_]*duchy[ -_]*of[ -_]*luxembourg
RO|罗马尼亚|🇷🇴|罗马尼亚|羅馬尼亞|romania|bucharest|(^|[^a-z0-9])ro([^a-z0-9]|$)|(^|[^a-z0-9])rou([^a-z0-9]|$)|布加勒斯特
TR|土耳其|🇹🇷|土耳其|turkey|turkiye|türkiye|istanbul|(^|[^a-z0-9])tr([^a-z0-9]|$)|(^|[^a-z0-9])tur([^a-z0-9]|$)|伊斯坦布尔|伊斯坦堡|republic[ -_]*of[ -_]*türkiye
RU|俄罗斯|🇷🇺|俄罗斯|俄羅斯|russia|moscow|saint[ -_]*petersburg|(^|[^a-z0-9])ru([^a-z0-9]|$)|(^|[^a-z0-9])rus([^a-z0-9]|$)|莫斯科|russian[ -_]*federation
UA|乌克兰|🇺🇦|乌克兰|烏克蘭|ukraine|kyiv|kiev|(^|[^a-z0-9])ua([^a-z0-9]|$)|(^|[^a-z0-9])ukr([^a-z0-9]|$)|基辅|基輔
IN|印度|🇮🇳|印度|india|mumbai|delhi|bangalore|chennai|(^|[^a-z0-9])ind([^a-z0-9]|$)|孟买|孟買|德里|班加罗尔|republic[ -_]*of[ -_]*india
ID|印度尼西亚|🇮🇩|印度尼西亚|印度尼西亞|印尼|indonesia|jakarta|(^|[^a-z0-9])id([^a-z0-9]|$)|(^|[^a-z0-9])idn([^a-z0-9]|$)|雅加达|雅加達|republic[ -_]*of[ -_]*indonesia
MY|马来西亚|🇲🇾|马来西亚|馬來西亞|malaysia|kuala[ -_]*lumpur|(^|[^a-z0-9])mys([^a-z0-9]|$)|吉隆坡
TH|泰国|🇹🇭|泰国|泰國|thailand|bangkok|(^|[^a-z0-9])th([^a-z0-9]|$)|(^|[^a-z0-9])tha([^a-z0-9]|$)|曼谷|kingdom[ -_]*of[ -_]*thailand
VN|越南|🇻🇳|越南|vietnam|hanoi|saigon|ho[ -_]*chi[ -_]*minh|(^|[^a-z0-9])vn([^a-z0-9]|$)|(^|[^a-z0-9])vnm([^a-z0-9]|$)|河内|河內|胡志明|viet[ -_]*nam|socialist[ -_]*republic[ -_]*of[ -_]*viet[ -_]*nam
PH|菲律宾|🇵🇭|菲律宾|菲律賓|philippines|manila|(^|[^a-z0-9])ph([^a-z0-9]|$)|(^|[^a-z0-9])phl([^a-z0-9]|$)|马尼拉|馬尼拉|republic[ -_]*of[ -_]*the[ -_]*philippines
AE|阿联酋|🇦🇪|阿联酋|阿聯酋|(^|[^a-z0-9])uae([^a-z0-9]|$)|united[ -_]*arab[ -_]*emirates|dubai|abu[ -_]*dhabi|(^|[^a-z0-9])ae([^a-z0-9]|$)|(^|[^a-z0-9])are([^a-z0-9]|$)|迪拜|阿布扎比
IL|以色列|🇮🇱|以色列|israel|tel[ -_]*aviv|jerusalem|(^|[^a-z0-9])il([^a-z0-9]|$)|(^|[^a-z0-9])isr([^a-z0-9]|$)|特拉维夫|耶路撒冷|state[ -_]*of[ -_]*israel
SA|沙特|🇸🇦|沙特|沙特阿拉伯|saudi|saudi[ -_]*arabia|riyadh|(^|[^a-z0-9])sa([^a-z0-9]|$)|(^|[^a-z0-9])sau([^a-z0-9]|$)|利雅得|kingdom[ -_]*of[ -_]*saudi[ -_]*arabia
ZA|南非|🇿🇦|南非|south[ -_]*africa|johannesburg|cape[ -_]*town|(^|[^a-z0-9])za([^a-z0-9]|$)|(^|[^a-z0-9])zaf([^a-z0-9]|$)|约翰内斯堡|開普敦|开普敦|republic[ -_]*of[ -_]*south[ -_]*africa
BR|巴西|🇧🇷|巴西|brazil|sao[ -_]*paulo|são[ -_]*paulo|(^|[^a-z0-9])rio([^a-z0-9]|$)|(^|[^a-z0-9])br([^a-z0-9]|$)|(^|[^a-z0-9])bra([^a-z0-9]|$)|圣保罗|聖保羅|里约|里約|federative[ -_]*republic[ -_]*of[ -_]*brazil
MX|墨西哥|🇲🇽|墨西哥|mexico|mexico[ -_]*city|(^|[^a-z0-9])mx([^a-z0-9]|$)|(^|[^a-z0-9])mex([^a-z0-9]|$)|united[ -_]*mexican[ -_]*states
AR|阿根廷|🇦🇷|阿根廷|argentina|buenos[ -_]*aires|(^|[^a-z0-9])ar([^a-z0-9]|$)|(^|[^a-z0-9])arg([^a-z0-9]|$)|布宜诺斯艾利斯|argentine[ -_]*republic
CL|智利|🇨🇱|智利|chile|santiago|(^|[^a-z0-9])cl([^a-z0-9]|$)|(^|[^a-z0-9])chl([^a-z0-9]|$)|圣地亚哥|聖地亞哥|republic[ -_]*of[ -_]*chile
CO|哥伦比亚|🇨🇴|哥伦比亚|哥倫比亞|colombia|bogota|bogotá|(^|[^a-z0-9])co([^a-z0-9]|$)|(^|[^a-z0-9])col([^a-z0-9]|$)|波哥大|republic[ -_]*of[ -_]*colombia
PE|秘鲁|🇵🇪|秘鲁|秘魯|peru|lima|(^|[^a-z0-9])pe([^a-z0-9]|$)|(^|[^a-z0-9])per([^a-z0-9]|$)|利马|利馬|republic[ -_]*of[ -_]*peru
GR|希腊|🇬🇷|希腊|希臘|greece|athens|(^|[^a-z0-9])gr([^a-z0-9]|$)|(^|[^a-z0-9])grc([^a-z0-9]|$)|雅典|hellenic[ -_]*republic
HU|匈牙利|🇭🇺|匈牙利|hungary|budapest|(^|[^a-z0-9])hu([^a-z0-9]|$)|(^|[^a-z0-9])hun([^a-z0-9]|$)|布达佩斯
SK|斯洛伐克|🇸🇰|斯洛伐克|slovakia|bratislava|(^|[^a-z0-9])sk([^a-z0-9]|$)|(^|[^a-z0-9])svk([^a-z0-9]|$)|布拉迪斯拉发|slovak[ -_]*republic
BG|保加利亚|🇧🇬|保加利亚|保加利亞|bulgaria|sofia|(^|[^a-z0-9])bg([^a-z0-9]|$)|(^|[^a-z0-9])bgr([^a-z0-9]|$)|索菲亚|republic[ -_]*of[ -_]*bulgaria
HR|克罗地亚|🇭🇷|克罗地亚|克羅地亞|croatia|zagreb|(^|[^a-z0-9])hr([^a-z0-9]|$)|(^|[^a-z0-9])hrv([^a-z0-9]|$)|萨格勒布|republic[ -_]*of[ -_]*croatia
RS|塞尔维亚|🇷🇸|塞尔维亚|塞爾維亞|serbia|belgrade|(^|[^a-z0-9])rs([^a-z0-9]|$)|(^|[^a-z0-9])srb([^a-z0-9]|$)|贝尔格莱德|republic[ -_]*of[ -_]*serbia
IS|冰岛|🇮🇸|冰岛|冰島|iceland|reykjavik|(^|[^a-z0-9])isl([^a-z0-9]|$)|雷克雅未克|republic[ -_]*of[ -_]*iceland
EE|爱沙尼亚|🇪🇪|爱沙尼亚|愛沙尼亞|estonia|tallinn|(^|[^a-z0-9])ee([^a-z0-9]|$)|(^|[^a-z0-9])est([^a-z0-9]|$)|塔林|republic[ -_]*of[ -_]*estonia
LV|拉脱维亚|🇱🇻|拉脱维亚|拉脫維亞|latvia|riga|(^|[^a-z0-9])lv([^a-z0-9]|$)|(^|[^a-z0-9])lva([^a-z0-9]|$)|里加|republic[ -_]*of[ -_]*latvia
LT|立陶宛|🇱🇹|立陶宛|lithuania|vilnius|(^|[^a-z0-9])lt([^a-z0-9]|$)|(^|[^a-z0-9])ltu([^a-z0-9]|$)|维尔纽斯|republic[ -_]*of[ -_]*lithuania
SI|斯洛文尼亚|🇸🇮|斯洛文尼亚|斯洛文尼亞|slovenia|ljubljana|(^|[^a-z0-9])si([^a-z0-9]|$)|(^|[^a-z0-9])svn([^a-z0-9]|$)|卢布尔雅那|republic[ -_]*of[ -_]*slovenia
CY|塞浦路斯|🇨🇾|塞浦路斯|cyprus|nicosia|(^|[^a-z0-9])cy([^a-z0-9]|$)|(^|[^a-z0-9])cyp([^a-z0-9]|$)|尼科西亚|republic[ -_]*of[ -_]*cyprus
EG|埃及|🇪🇬|埃及|egypt|cairo|(^|[^a-z0-9])eg([^a-z0-9]|$)|(^|[^a-z0-9])egy([^a-z0-9]|$)|开罗|開羅|arab[ -_]*republic[ -_]*of[ -_]*egypt
NG|尼日利亚|🇳🇬|尼日利亚|尼日利亞|nigeria|lagos|abuja|(^|[^a-z0-9])ng([^a-z0-9]|$)|(^|[^a-z0-9])nga([^a-z0-9]|$)|拉各斯|federal[ -_]*republic[ -_]*of[ -_]*nigeria
PK|巴基斯坦|🇵🇰|巴基斯坦|pakistan|karachi|islamabad|(^|[^a-z0-9])pk([^a-z0-9]|$)|(^|[^a-z0-9])pak([^a-z0-9]|$)|卡拉奇|islamic[ -_]*republic[ -_]*of[ -_]*pakistan
BD|孟加拉|🇧🇩|孟加拉|bangladesh|dhaka|(^|[^a-z0-9])bd([^a-z0-9]|$)|(^|[^a-z0-9])bgd([^a-z0-9]|$)|达卡|達卡|people's[ -_]*republic[ -_]*of[ -_]*bangladesh
AD|Andorra|🇦🇩|andorra|principality[ -_]*of[ -_]*andorra|(^|[^a-z0-9])and([^a-z0-9]|$)|(^|[^a-z0-9])ad([^a-z0-9]|$)
AF|Afghanistan|🇦🇫|afghanistan|islamic[ -_]*republic[ -_]*of[ -_]*afghanistan|(^|[^a-z0-9])afg([^a-z0-9]|$)|(^|[^a-z0-9])af([^a-z0-9]|$)
AG|Antigua and Barbuda|🇦🇬|antigua[ -_]*and[ -_]*barbuda|(^|[^a-z0-9])atg([^a-z0-9]|$)|(^|[^a-z0-9])ag([^a-z0-9]|$)
AI|Anguilla|🇦🇮|anguilla|(^|[^a-z0-9])aia([^a-z0-9]|$)|(^|[^a-z0-9])ai([^a-z0-9]|$)
AL|Albania|🇦🇱|albania|republic[ -_]*of[ -_]*albania|(^|[^a-z0-9])alb([^a-z0-9]|$)|(^|[^a-z0-9])al([^a-z0-9]|$)
AM|Armenia|🇦🇲|armenia|republic[ -_]*of[ -_]*armenia|(^|[^a-z0-9])arm([^a-z0-9]|$)
AO|Angola|🇦🇴|angola|republic[ -_]*of[ -_]*angola|(^|[^a-z0-9])ago([^a-z0-9]|$)|(^|[^a-z0-9])ao([^a-z0-9]|$)
AQ|Antarctica|🇦🇶|antarctica|(^|[^a-z0-9])ata([^a-z0-9]|$)|(^|[^a-z0-9])aq([^a-z0-9]|$)
AS|American Samoa|🇦🇸|american[ -_]*samoa|(^|[^a-z0-9])asm([^a-z0-9]|$)
AW|Aruba|🇦🇼|aruba|(^|[^a-z0-9])abw([^a-z0-9]|$)|(^|[^a-z0-9])aw([^a-z0-9]|$)
AX|Åland Islands|🇦🇽|åland[ -_]*islands|(^|[^a-z0-9])ala([^a-z0-9]|$)|(^|[^a-z0-9])ax([^a-z0-9]|$)
AZ|Azerbaijan|🇦🇿|azerbaijan|republic[ -_]*of[ -_]*azerbaijan|(^|[^a-z0-9])aze([^a-z0-9]|$)|(^|[^a-z0-9])az([^a-z0-9]|$)
BA|Bosnia and Herzegovina|🇧🇦|bosnia[ -_]*and[ -_]*herzegovina|republic[ -_]*of[ -_]*bosnia[ -_]*and[ -_]*herzegovina|(^|[^a-z0-9])bih([^a-z0-9]|$)|(^|[^a-z0-9])ba([^a-z0-9]|$)
BB|Barbados|🇧🇧|barbados|(^|[^a-z0-9])brb([^a-z0-9]|$)|(^|[^a-z0-9])bb([^a-z0-9]|$)
BF|Burkina Faso|🇧🇫|burkina[ -_]*faso|(^|[^a-z0-9])bfa([^a-z0-9]|$)|(^|[^a-z0-9])bf([^a-z0-9]|$)
BH|巴林|🇧🇭|巴林|bahrain|manama|(^|[^a-z0-9])bh([^a-z0-9]|$)|(^|[^a-z0-9])bhr([^a-z0-9]|$)|麦纳麦|kingdom[ -_]*of[ -_]*bahrain
BI|Burundi|🇧🇮|burundi|republic[ -_]*of[ -_]*burundi|(^|[^a-z0-9])bdi([^a-z0-9]|$)|(^|[^a-z0-9])bi([^a-z0-9]|$)
BJ|Benin|🇧🇯|benin|republic[ -_]*of[ -_]*benin|(^|[^a-z0-9])ben([^a-z0-9]|$)|(^|[^a-z0-9])bj([^a-z0-9]|$)
BL|Saint Barthélemy|🇧🇱|saint[ -_]*barthélemy|(^|[^a-z0-9])blm([^a-z0-9]|$)|(^|[^a-z0-9])bl([^a-z0-9]|$)
BM|Bermuda|🇧🇲|bermuda|(^|[^a-z0-9])bmu([^a-z0-9]|$)|(^|[^a-z0-9])bm([^a-z0-9]|$)
BN|Brunei Darussalam|🇧🇳|brunei[ -_]*darussalam|(^|[^a-z0-9])brn([^a-z0-9]|$)|(^|[^a-z0-9])bn([^a-z0-9]|$)
BO|玻利维亚|🇧🇴|玻利维亚|玻利維亞|bolivia|la[ -_]*paz|(^|[^a-z0-9])bo([^a-z0-9]|$)|(^|[^a-z0-9])bol([^a-z0-9]|$)|拉巴斯|bolivia,[ -_]*plurinational[ -_]*state[ -_]*of|plurinational[ -_]*state[ -_]*of[ -_]*bolivia
BQ|Bonaire, Sint Eustatius and Saba|🇧🇶|bonaire,[ -_]*sint[ -_]*eustatius[ -_]*and[ -_]*saba|(^|[^a-z0-9])bes([^a-z0-9]|$)|(^|[^a-z0-9])bq([^a-z0-9]|$)
BS|Bahamas|🇧🇸|bahamas|commonwealth[ -_]*of[ -_]*the[ -_]*bahamas|(^|[^a-z0-9])bhs([^a-z0-9]|$)|(^|[^a-z0-9])bs([^a-z0-9]|$)
BT|Bhutan|🇧🇹|bhutan|kingdom[ -_]*of[ -_]*bhutan|(^|[^a-z0-9])btn([^a-z0-9]|$)|(^|[^a-z0-9])bt([^a-z0-9]|$)
BV|Bouvet Island|🇧🇻|bouvet[ -_]*island|(^|[^a-z0-9])bvt([^a-z0-9]|$)|(^|[^a-z0-9])bv([^a-z0-9]|$)
BW|Botswana|🇧🇼|botswana|republic[ -_]*of[ -_]*botswana|(^|[^a-z0-9])bwa([^a-z0-9]|$)|(^|[^a-z0-9])bw([^a-z0-9]|$)
BY|Belarus|🇧🇾|belarus|republic[ -_]*of[ -_]*belarus|(^|[^a-z0-9])blr([^a-z0-9]|$)
BZ|Belize|🇧🇿|belize|(^|[^a-z0-9])blz([^a-z0-9]|$)|(^|[^a-z0-9])bz([^a-z0-9]|$)
CC|Cocos (Keeling) Islands|🇨🇨|cocos[ -_]*\(keeling\)[ -_]*islands|(^|[^a-z0-9])cck([^a-z0-9]|$)|(^|[^a-z0-9])cc([^a-z0-9]|$)
CD|Congo, The Democratic Republic of the|🇨🇩|congo,[ -_]*the[ -_]*democratic[ -_]*republic[ -_]*of[ -_]*the|(^|[^a-z0-9])cod([^a-z0-9]|$)|(^|[^a-z0-9])cd([^a-z0-9]|$)
CF|Central African Republic|🇨🇫|central[ -_]*african[ -_]*republic|(^|[^a-z0-9])caf([^a-z0-9]|$)|(^|[^a-z0-9])cf([^a-z0-9]|$)
CG|Congo|🇨🇬|congo|republic[ -_]*of[ -_]*the[ -_]*congo|(^|[^a-z0-9])cog([^a-z0-9]|$)|(^|[^a-z0-9])cg([^a-z0-9]|$)
CI|Côte d'Ivoire|🇨🇮|côte[ -_]*d'ivoire|republic[ -_]*of[ -_]*côte[ -_]*d'ivoire|(^|[^a-z0-9])civ([^a-z0-9]|$)|(^|[^a-z0-9])ci([^a-z0-9]|$)
CK|Cook Islands|🇨🇰|cook[ -_]*islands|(^|[^a-z0-9])cok([^a-z0-9]|$)|(^|[^a-z0-9])ck([^a-z0-9]|$)
CM|Cameroon|🇨🇲|cameroon|republic[ -_]*of[ -_]*cameroon|(^|[^a-z0-9])cmr([^a-z0-9]|$)|(^|[^a-z0-9])cm([^a-z0-9]|$)
CN|China|🇨🇳|china|people's[ -_]*republic[ -_]*of[ -_]*china|(^|[^a-z0-9])chn([^a-z0-9]|$)|(^|[^a-z0-9])cn([^a-z0-9]|$)
CR|哥斯达黎加|🇨🇷|哥斯达黎加|哥斯大黎加|costa[ -_]*rica|san[ -_]*jose|(^|[^a-z0-9])cr([^a-z0-9]|$)|(^|[^a-z0-9])cri([^a-z0-9]|$)|republic[ -_]*of[ -_]*costa[ -_]*rica
CU|古巴|🇨🇺|古巴|cuba|havana|(^|[^a-z0-9])cu([^a-z0-9]|$)|(^|[^a-z0-9])cub([^a-z0-9]|$)|哈瓦那|republic[ -_]*of[ -_]*cuba
CV|Cabo Verde|🇨🇻|cabo[ -_]*verde|republic[ -_]*of[ -_]*cabo[ -_]*verde|(^|[^a-z0-9])cpv([^a-z0-9]|$)|(^|[^a-z0-9])cv([^a-z0-9]|$)
CW|Curaçao|🇨🇼|curaçao|(^|[^a-z0-9])cuw([^a-z0-9]|$)|(^|[^a-z0-9])cw([^a-z0-9]|$)
CX|Christmas Island|🇨🇽|christmas[ -_]*island|(^|[^a-z0-9])cxr([^a-z0-9]|$)|(^|[^a-z0-9])cx([^a-z0-9]|$)
DJ|Djibouti|🇩🇯|djibouti|republic[ -_]*of[ -_]*djibouti|(^|[^a-z0-9])dji([^a-z0-9]|$)|(^|[^a-z0-9])dj([^a-z0-9]|$)
DM|Dominica|🇩🇲|dominica|commonwealth[ -_]*of[ -_]*dominica|(^|[^a-z0-9])dma([^a-z0-9]|$)|(^|[^a-z0-9])dm([^a-z0-9]|$)
DO|多米尼加|🇩🇴|多米尼加|dominican[ -_]*republic|santo[ -_]*domingo|(^|[^a-z0-9])dom([^a-z0-9]|$)
DZ|阿尔及利亚|🇩🇿|阿尔及利亚|阿爾及利亞|algeria|algiers|(^|[^a-z0-9])dz([^a-z0-9]|$)|(^|[^a-z0-9])dza([^a-z0-9]|$)|阿尔及尔|people's[ -_]*democratic[ -_]*republic[ -_]*of[ -_]*algeria
EC|厄瓜多尔|🇪🇨|厄瓜多尔|厄瓜多爾|ecuador|quito|(^|[^a-z0-9])ec([^a-z0-9]|$)|(^|[^a-z0-9])ecu([^a-z0-9]|$)|基多|republic[ -_]*of[ -_]*ecuador
EH|Western Sahara|🇪🇭|western[ -_]*sahara|(^|[^a-z0-9])esh([^a-z0-9]|$)|(^|[^a-z0-9])eh([^a-z0-9]|$)
ER|Eritrea|🇪🇷|eritrea|the[ -_]*state[ -_]*of[ -_]*eritrea|(^|[^a-z0-9])eri([^a-z0-9]|$)|(^|[^a-z0-9])er([^a-z0-9]|$)
ET|埃塞俄比亚|🇪🇹|埃塞俄比亚|衣索比亚|ethiopia|addis[ -_]*ababa|(^|[^a-z0-9])et([^a-z0-9]|$)|(^|[^a-z0-9])eth([^a-z0-9]|$)|亚的斯亚贝巴|federal[ -_]*democratic[ -_]*republic[ -_]*of[ -_]*ethiopia
FJ|Fiji|🇫🇯|fiji|republic[ -_]*of[ -_]*fiji|(^|[^a-z0-9])fji([^a-z0-9]|$)|(^|[^a-z0-9])fj([^a-z0-9]|$)
FK|Falkland Islands (Malvinas)|🇫🇰|falkland[ -_]*islands[ -_]*\(malvinas\)|(^|[^a-z0-9])flk([^a-z0-9]|$)|(^|[^a-z0-9])fk([^a-z0-9]|$)
FM|Micronesia, Federated States of|🇫🇲|micronesia,[ -_]*federated[ -_]*states[ -_]*of|federated[ -_]*states[ -_]*of[ -_]*micronesia|(^|[^a-z0-9])fsm([^a-z0-9]|$)|(^|[^a-z0-9])fm([^a-z0-9]|$)
FO|Faroe Islands|🇫🇴|faroe[ -_]*islands|(^|[^a-z0-9])fro([^a-z0-9]|$)|(^|[^a-z0-9])fo([^a-z0-9]|$)
GA|Gabon|🇬🇦|gabon|gabonese[ -_]*republic|(^|[^a-z0-9])gab([^a-z0-9]|$)|(^|[^a-z0-9])ga([^a-z0-9]|$)
GD|Grenada|🇬🇩|grenada|(^|[^a-z0-9])grd([^a-z0-9]|$)|(^|[^a-z0-9])gd([^a-z0-9]|$)
GE|Georgia|🇬🇪|georgia|(^|[^a-z0-9])geo([^a-z0-9]|$)|(^|[^a-z0-9])ge([^a-z0-9]|$)
GF|French Guiana|🇬🇫|french[ -_]*guiana|(^|[^a-z0-9])guf([^a-z0-9]|$)|(^|[^a-z0-9])gf([^a-z0-9]|$)
GG|Guernsey|🇬🇬|guernsey|(^|[^a-z0-9])ggy([^a-z0-9]|$)|(^|[^a-z0-9])gg([^a-z0-9]|$)
GH|加纳|🇬🇭|加纳|迦納|ghana|accra|(^|[^a-z0-9])gh([^a-z0-9]|$)|(^|[^a-z0-9])gha([^a-z0-9]|$)|阿克拉|republic[ -_]*of[ -_]*ghana
GI|Gibraltar|🇬🇮|gibraltar|(^|[^a-z0-9])gib([^a-z0-9]|$)|(^|[^a-z0-9])gi([^a-z0-9]|$)
GL|Greenland|🇬🇱|greenland|(^|[^a-z0-9])grl([^a-z0-9]|$)|(^|[^a-z0-9])gl([^a-z0-9]|$)
GM|Gambia|🇬🇲|gambia|republic[ -_]*of[ -_]*the[ -_]*gambia|(^|[^a-z0-9])gmb([^a-z0-9]|$)|(^|[^a-z0-9])gm([^a-z0-9]|$)
GN|Guinea|🇬🇳|guinea|republic[ -_]*of[ -_]*guinea|(^|[^a-z0-9])gin([^a-z0-9]|$)|(^|[^a-z0-9])gn([^a-z0-9]|$)
GP|Guadeloupe|🇬🇵|guadeloupe|(^|[^a-z0-9])glp([^a-z0-9]|$)|(^|[^a-z0-9])gp([^a-z0-9]|$)
GQ|Equatorial Guinea|🇬🇶|equatorial[ -_]*guinea|republic[ -_]*of[ -_]*equatorial[ -_]*guinea|(^|[^a-z0-9])gnq([^a-z0-9]|$)|(^|[^a-z0-9])gq([^a-z0-9]|$)
GS|South Georgia and the South Sandwich Islands|🇬🇸|south[ -_]*georgia[ -_]*and[ -_]*the[ -_]*south[ -_]*sandwich[ -_]*islands|(^|[^a-z0-9])sgs([^a-z0-9]|$)|(^|[^a-z0-9])gs([^a-z0-9]|$)
GT|Guatemala|🇬🇹|guatemala|republic[ -_]*of[ -_]*guatemala|(^|[^a-z0-9])gtm([^a-z0-9]|$)|(^|[^a-z0-9])gt([^a-z0-9]|$)
GU|Guam|🇬🇺|guam|(^|[^a-z0-9])gum([^a-z0-9]|$)|(^|[^a-z0-9])gu([^a-z0-9]|$)
GW|Guinea-Bissau|🇬🇼|guinea[ -_]*bissau|republic[ -_]*of[ -_]*guinea[ -_]*bissau|(^|[^a-z0-9])gnb([^a-z0-9]|$)|(^|[^a-z0-9])gw([^a-z0-9]|$)
GY|Guyana|🇬🇾|guyana|republic[ -_]*of[ -_]*guyana|(^|[^a-z0-9])guy([^a-z0-9]|$)|(^|[^a-z0-9])gy([^a-z0-9]|$)
HM|Heard Island and McDonald Islands|🇭🇲|heard[ -_]*island[ -_]*and[ -_]*mcdonald[ -_]*islands|(^|[^a-z0-9])hmd([^a-z0-9]|$)|(^|[^a-z0-9])hm([^a-z0-9]|$)
HN|Honduras|🇭🇳|honduras|republic[ -_]*of[ -_]*honduras|(^|[^a-z0-9])hnd([^a-z0-9]|$)|(^|[^a-z0-9])hn([^a-z0-9]|$)
HT|Haiti|🇭🇹|haiti|republic[ -_]*of[ -_]*haiti|(^|[^a-z0-9])hti([^a-z0-9]|$)|(^|[^a-z0-9])ht([^a-z0-9]|$)
IM|Isle of Man|🇮🇲|isle[ -_]*of[ -_]*man|(^|[^a-z0-9])imn([^a-z0-9]|$)|(^|[^a-z0-9])im([^a-z0-9]|$)
IO|British Indian Ocean Territory|🇮🇴|british[ -_]*indian[ -_]*ocean[ -_]*territory|(^|[^a-z0-9])iot([^a-z0-9]|$)|(^|[^a-z0-9])io([^a-z0-9]|$)
IQ|伊拉克|🇮🇶|伊拉克|iraq|baghdad|(^|[^a-z0-9])iq([^a-z0-9]|$)|(^|[^a-z0-9])irq([^a-z0-9]|$)|巴格达|republic[ -_]*of[ -_]*iraq
IR|伊朗|🇮🇷|伊朗|iran|tehran|(^|[^a-z0-9])ir([^a-z0-9]|$)|(^|[^a-z0-9])irn([^a-z0-9]|$)|德黑兰|iran,[ -_]*islamic[ -_]*republic[ -_]*of|islamic[ -_]*republic[ -_]*of[ -_]*iran
JE|Jersey|🇯🇪|jersey|(^|[^a-z0-9])jey([^a-z0-9]|$)|(^|[^a-z0-9])je([^a-z0-9]|$)
JM|Jamaica|🇯🇲|jamaica|(^|[^a-z0-9])jam([^a-z0-9]|$)|(^|[^a-z0-9])jm([^a-z0-9]|$)
JO|约旦|🇯🇴|约旦|約旦|jordan|amman|(^|[^a-z0-9])jo([^a-z0-9]|$)|(^|[^a-z0-9])jor([^a-z0-9]|$)|安曼|hashemite[ -_]*kingdom[ -_]*of[ -_]*jordan
KE|肯尼亚|🇰🇪|肯尼亚|肯尼亞|kenya|nairobi|(^|[^a-z0-9])ke([^a-z0-9]|$)|(^|[^a-z0-9])ken([^a-z0-9]|$)|内罗毕|republic[ -_]*of[ -_]*kenya
KG|Kyrgyzstan|🇰🇬|kyrgyzstan|kyrgyz[ -_]*republic|(^|[^a-z0-9])kgz([^a-z0-9]|$)|(^|[^a-z0-9])kg([^a-z0-9]|$)
KH|Cambodia|🇰🇭|cambodia|kingdom[ -_]*of[ -_]*cambodia|(^|[^a-z0-9])khm([^a-z0-9]|$)|(^|[^a-z0-9])kh([^a-z0-9]|$)
KI|Kiribati|🇰🇮|kiribati|republic[ -_]*of[ -_]*kiribati|(^|[^a-z0-9])kir([^a-z0-9]|$)|(^|[^a-z0-9])ki([^a-z0-9]|$)
KM|Comoros|🇰🇲|comoros|union[ -_]*of[ -_]*the[ -_]*comoros|(^|[^a-z0-9])com([^a-z0-9]|$)|(^|[^a-z0-9])km([^a-z0-9]|$)
KN|Saint Kitts and Nevis|🇰🇳|saint[ -_]*kitts[ -_]*and[ -_]*nevis|(^|[^a-z0-9])kna([^a-z0-9]|$)|(^|[^a-z0-9])kn([^a-z0-9]|$)
KP|Korea, Democratic People's Republic of|🇰🇵|korea,[ -_]*democratic[ -_]*people's[ -_]*republic[ -_]*of|democratic[ -_]*people's[ -_]*republic[ -_]*of[ -_]*korea|(^|[^a-z0-9])prk([^a-z0-9]|$)|(^|[^a-z0-9])kp([^a-z0-9]|$)
KW|科威特|🇰🇼|科威特|kuwait|(^|[^a-z0-9])kw([^a-z0-9]|$)|(^|[^a-z0-9])kwt([^a-z0-9]|$)|state[ -_]*of[ -_]*kuwait
KY|Cayman Islands|🇰🇾|cayman[ -_]*islands|(^|[^a-z0-9])cym([^a-z0-9]|$)|(^|[^a-z0-9])ky([^a-z0-9]|$)
KZ|Kazakhstan|🇰🇿|kazakhstan|republic[ -_]*of[ -_]*kazakhstan|(^|[^a-z0-9])kaz([^a-z0-9]|$)|(^|[^a-z0-9])kz([^a-z0-9]|$)
LA|Lao People's Democratic Republic|🇱🇦|lao[ -_]*people's[ -_]*democratic[ -_]*republic|(^|[^a-z0-9])lao([^a-z0-9]|$)
LB|黎巴嫩|🇱🇧|黎巴嫩|lebanon|beirut|(^|[^a-z0-9])lb([^a-z0-9]|$)|(^|[^a-z0-9])lbn([^a-z0-9]|$)|贝鲁特|lebanese[ -_]*republic
LC|Saint Lucia|🇱🇨|saint[ -_]*lucia|(^|[^a-z0-9])lca([^a-z0-9]|$)|(^|[^a-z0-9])lc([^a-z0-9]|$)
LI|Liechtenstein|🇱🇮|liechtenstein|principality[ -_]*of[ -_]*liechtenstein|(^|[^a-z0-9])lie([^a-z0-9]|$)
LK|Sri Lanka|🇱🇰|sri[ -_]*lanka|democratic[ -_]*socialist[ -_]*republic[ -_]*of[ -_]*sri[ -_]*lanka|(^|[^a-z0-9])lka([^a-z0-9]|$)|(^|[^a-z0-9])lk([^a-z0-9]|$)
LR|Liberia|🇱🇷|liberia|republic[ -_]*of[ -_]*liberia|(^|[^a-z0-9])lbr([^a-z0-9]|$)|(^|[^a-z0-9])lr([^a-z0-9]|$)
LS|Lesotho|🇱🇸|lesotho|kingdom[ -_]*of[ -_]*lesotho|(^|[^a-z0-9])lso([^a-z0-9]|$)|(^|[^a-z0-9])ls([^a-z0-9]|$)
LY|Libya|🇱🇾|libya|(^|[^a-z0-9])lby([^a-z0-9]|$)|(^|[^a-z0-9])ly([^a-z0-9]|$)
MA|摩洛哥|🇲🇦|摩洛哥|morocco|casablanca|rabat|(^|[^a-z0-9])ma([^a-z0-9]|$)|(^|[^a-z0-9])mar([^a-z0-9]|$)|卡萨布兰卡|kingdom[ -_]*of[ -_]*morocco
MC|Monaco|🇲🇨|monaco|principality[ -_]*of[ -_]*monaco|(^|[^a-z0-9])mco([^a-z0-9]|$)|(^|[^a-z0-9])mc([^a-z0-9]|$)
MD|Moldova, Republic of|🇲🇩|moldova,[ -_]*republic[ -_]*of|republic[ -_]*of[ -_]*moldova|(^|[^a-z0-9])mda([^a-z0-9]|$)|(^|[^a-z0-9])md([^a-z0-9]|$)
ME|Montenegro|🇲🇪|montenegro|(^|[^a-z0-9])mne([^a-z0-9]|$)
MF|Saint Martin (French part)|🇲🇫|saint[ -_]*martin[ -_]*\(french[ -_]*part\)|(^|[^a-z0-9])maf([^a-z0-9]|$)|(^|[^a-z0-9])mf([^a-z0-9]|$)
MG|Madagascar|🇲🇬|madagascar|republic[ -_]*of[ -_]*madagascar|(^|[^a-z0-9])mdg([^a-z0-9]|$)|(^|[^a-z0-9])mg([^a-z0-9]|$)
MH|Marshall Islands|🇲🇭|marshall[ -_]*islands|republic[ -_]*of[ -_]*the[ -_]*marshall[ -_]*islands|(^|[^a-z0-9])mhl([^a-z0-9]|$)|(^|[^a-z0-9])mh([^a-z0-9]|$)
MK|North Macedonia|🇲🇰|north[ -_]*macedonia|republic[ -_]*of[ -_]*north[ -_]*macedonia|(^|[^a-z0-9])mkd([^a-z0-9]|$)|(^|[^a-z0-9])mk([^a-z0-9]|$)
ML|Mali|🇲🇱|mali|republic[ -_]*of[ -_]*mali|(^|[^a-z0-9])mli([^a-z0-9]|$)|(^|[^a-z0-9])ml([^a-z0-9]|$)
MM|Myanmar|🇲🇲|myanmar|republic[ -_]*of[ -_]*myanmar|(^|[^a-z0-9])mmr([^a-z0-9]|$)|(^|[^a-z0-9])mm([^a-z0-9]|$)
MN|Mongolia|🇲🇳|mongolia|(^|[^a-z0-9])mng([^a-z0-9]|$)|(^|[^a-z0-9])mn([^a-z0-9]|$)
MP|Northern Mariana Islands|🇲🇵|northern[ -_]*mariana[ -_]*islands|commonwealth[ -_]*of[ -_]*the[ -_]*northern[ -_]*mariana[ -_]*islands|(^|[^a-z0-9])mnp([^a-z0-9]|$)|(^|[^a-z0-9])mp([^a-z0-9]|$)
MQ|Martinique|🇲🇶|martinique|(^|[^a-z0-9])mtq([^a-z0-9]|$)|(^|[^a-z0-9])mq([^a-z0-9]|$)
MR|Mauritania|🇲🇷|mauritania|islamic[ -_]*republic[ -_]*of[ -_]*mauritania|(^|[^a-z0-9])mrt([^a-z0-9]|$)|(^|[^a-z0-9])mr([^a-z0-9]|$)
MS|Montserrat|🇲🇸|montserrat|(^|[^a-z0-9])msr([^a-z0-9]|$)|(^|[^a-z0-9])ms([^a-z0-9]|$)
MT|Malta|🇲🇹|malta|republic[ -_]*of[ -_]*malta|(^|[^a-z0-9])mlt([^a-z0-9]|$)|(^|[^a-z0-9])mt([^a-z0-9]|$)
MU|Mauritius|🇲🇺|mauritius|republic[ -_]*of[ -_]*mauritius|(^|[^a-z0-9])mus([^a-z0-9]|$)|(^|[^a-z0-9])mu([^a-z0-9]|$)
MV|Maldives|🇲🇻|maldives|republic[ -_]*of[ -_]*maldives|(^|[^a-z0-9])mdv([^a-z0-9]|$)|(^|[^a-z0-9])mv([^a-z0-9]|$)
MW|Malawi|🇲🇼|malawi|republic[ -_]*of[ -_]*malawi|(^|[^a-z0-9])mwi([^a-z0-9]|$)|(^|[^a-z0-9])mw([^a-z0-9]|$)
MZ|Mozambique|🇲🇿|mozambique|republic[ -_]*of[ -_]*mozambique|(^|[^a-z0-9])moz([^a-z0-9]|$)|(^|[^a-z0-9])mz([^a-z0-9]|$)
NA|Namibia|🇳🇦|namibia|republic[ -_]*of[ -_]*namibia|(^|[^a-z0-9])nam([^a-z0-9]|$)|(^|[^a-z0-9])na([^a-z0-9]|$)
NC|New Caledonia|🇳🇨|new[ -_]*caledonia|(^|[^a-z0-9])ncl([^a-z0-9]|$)|(^|[^a-z0-9])nc([^a-z0-9]|$)
NE|Niger|🇳🇪|niger|republic[ -_]*of[ -_]*the[ -_]*niger|(^|[^a-z0-9])ner([^a-z0-9]|$)|(^|[^a-z0-9])ne([^a-z0-9]|$)
NF|Norfolk Island|🇳🇫|norfolk[ -_]*island|(^|[^a-z0-9])nfk([^a-z0-9]|$)|(^|[^a-z0-9])nf([^a-z0-9]|$)
NI|Nicaragua|🇳🇮|nicaragua|republic[ -_]*of[ -_]*nicaragua|(^|[^a-z0-9])nic([^a-z0-9]|$)|(^|[^a-z0-9])ni([^a-z0-9]|$)
NP|Nepal|🇳🇵|nepal|federal[ -_]*democratic[ -_]*republic[ -_]*of[ -_]*nepal|(^|[^a-z0-9])npl([^a-z0-9]|$)|(^|[^a-z0-9])np([^a-z0-9]|$)
NR|Nauru|🇳🇷|nauru|republic[ -_]*of[ -_]*nauru|(^|[^a-z0-9])nru([^a-z0-9]|$)|(^|[^a-z0-9])nr([^a-z0-9]|$)
NU|Niue|🇳🇺|niue|(^|[^a-z0-9])niu([^a-z0-9]|$)|(^|[^a-z0-9])nu([^a-z0-9]|$)
OM|阿曼|🇴🇲|阿曼|oman|muscat|(^|[^a-z0-9])om([^a-z0-9]|$)|(^|[^a-z0-9])omn([^a-z0-9]|$)|马斯喀特|sultanate[ -_]*of[ -_]*oman
PA|巴拿马|🇵🇦|巴拿马|巴拿馬|panama|(^|[^a-z0-9])pa([^a-z0-9]|$)|(^|[^a-z0-9])pan([^a-z0-9]|$)|republic[ -_]*of[ -_]*panama
PF|French Polynesia|🇵🇫|french[ -_]*polynesia|(^|[^a-z0-9])pyf([^a-z0-9]|$)|(^|[^a-z0-9])pf([^a-z0-9]|$)
PG|Papua New Guinea|🇵🇬|papua[ -_]*new[ -_]*guinea|independent[ -_]*state[ -_]*of[ -_]*papua[ -_]*new[ -_]*guinea|(^|[^a-z0-9])png([^a-z0-9]|$)|(^|[^a-z0-9])pg([^a-z0-9]|$)
PM|Saint Pierre and Miquelon|🇵🇲|saint[ -_]*pierre[ -_]*and[ -_]*miquelon|(^|[^a-z0-9])spm([^a-z0-9]|$)|(^|[^a-z0-9])pm([^a-z0-9]|$)
PN|Pitcairn|🇵🇳|pitcairn|(^|[^a-z0-9])pcn([^a-z0-9]|$)|(^|[^a-z0-9])pn([^a-z0-9]|$)
PR|波多黎各|🇵🇷|波多黎各|puerto[ -_]*rico|san[ -_]*juan|(^|[^a-z0-9])pr([^a-z0-9]|$)|(^|[^a-z0-9])pri([^a-z0-9]|$)
PS|Palestine, State of|🇵🇸|palestine,[ -_]*state[ -_]*of|the[ -_]*state[ -_]*of[ -_]*palestine|(^|[^a-z0-9])pse([^a-z0-9]|$)|(^|[^a-z0-9])ps([^a-z0-9]|$)
PW|Palau|🇵🇼|palau|republic[ -_]*of[ -_]*palau|(^|[^a-z0-9])plw([^a-z0-9]|$)|(^|[^a-z0-9])pw([^a-z0-9]|$)
PY|巴拉圭|🇵🇾|巴拉圭|paraguay|asuncion|asunción|(^|[^a-z0-9])py([^a-z0-9]|$)|(^|[^a-z0-9])pry([^a-z0-9]|$)|亚松森|republic[ -_]*of[ -_]*paraguay
QA|卡塔尔|🇶🇦|卡塔尔|卡塔爾|qatar|doha|(^|[^a-z0-9])qa([^a-z0-9]|$)|(^|[^a-z0-9])qat([^a-z0-9]|$)|多哈|state[ -_]*of[ -_]*qatar
RE|Réunion|🇷🇪|réunion|(^|[^a-z0-9])reu([^a-z0-9]|$)|(^|[^a-z0-9])re([^a-z0-9]|$)
RW|Rwanda|🇷🇼|rwanda|rwandese[ -_]*republic|(^|[^a-z0-9])rwa([^a-z0-9]|$)|(^|[^a-z0-9])rw([^a-z0-9]|$)
SB|Solomon Islands|🇸🇧|solomon[ -_]*islands|(^|[^a-z0-9])slb([^a-z0-9]|$)|(^|[^a-z0-9])sb([^a-z0-9]|$)
SC|Seychelles|🇸🇨|seychelles|republic[ -_]*of[ -_]*seychelles|(^|[^a-z0-9])syc([^a-z0-9]|$)|(^|[^a-z0-9])sc([^a-z0-9]|$)
SD|Sudan|🇸🇩|sudan|republic[ -_]*of[ -_]*the[ -_]*sudan|(^|[^a-z0-9])sdn([^a-z0-9]|$)|(^|[^a-z0-9])sd([^a-z0-9]|$)
SH|Saint Helena, Ascension and Tristan da Cunha|🇸🇭|saint[ -_]*helena,[ -_]*ascension[ -_]*and[ -_]*tristan[ -_]*da[ -_]*cunha|(^|[^a-z0-9])shn([^a-z0-9]|$)|(^|[^a-z0-9])sh([^a-z0-9]|$)
SJ|Svalbard and Jan Mayen|🇸🇯|svalbard[ -_]*and[ -_]*jan[ -_]*mayen|(^|[^a-z0-9])sjm([^a-z0-9]|$)|(^|[^a-z0-9])sj([^a-z0-9]|$)
SL|Sierra Leone|🇸🇱|sierra[ -_]*leone|republic[ -_]*of[ -_]*sierra[ -_]*leone|(^|[^a-z0-9])sle([^a-z0-9]|$)|(^|[^a-z0-9])sl([^a-z0-9]|$)
SM|San Marino|🇸🇲|san[ -_]*marino|republic[ -_]*of[ -_]*san[ -_]*marino|(^|[^a-z0-9])smr([^a-z0-9]|$)|(^|[^a-z0-9])sm([^a-z0-9]|$)
SN|Senegal|🇸🇳|senegal|republic[ -_]*of[ -_]*senegal|(^|[^a-z0-9])sen([^a-z0-9]|$)|(^|[^a-z0-9])sn([^a-z0-9]|$)
SO|Somalia|🇸🇴|somalia|federal[ -_]*republic[ -_]*of[ -_]*somalia|(^|[^a-z0-9])som([^a-z0-9]|$)
SR|Suriname|🇸🇷|suriname|republic[ -_]*of[ -_]*suriname|(^|[^a-z0-9])sur([^a-z0-9]|$)|(^|[^a-z0-9])sr([^a-z0-9]|$)
SS|South Sudan|🇸🇸|south[ -_]*sudan|republic[ -_]*of[ -_]*south[ -_]*sudan|(^|[^a-z0-9])ssd([^a-z0-9]|$)|(^|[^a-z0-9])ss([^a-z0-9]|$)
ST|Sao Tome and Principe|🇸🇹|sao[ -_]*tome[ -_]*and[ -_]*principe|democratic[ -_]*republic[ -_]*of[ -_]*sao[ -_]*tome[ -_]*and[ -_]*principe|(^|[^a-z0-9])stp([^a-z0-9]|$)|(^|[^a-z0-9])st([^a-z0-9]|$)
SV|El Salvador|🇸🇻|el[ -_]*salvador|republic[ -_]*of[ -_]*el[ -_]*salvador|(^|[^a-z0-9])slv([^a-z0-9]|$)|(^|[^a-z0-9])sv([^a-z0-9]|$)
SX|Sint Maarten (Dutch part)|🇸🇽|sint[ -_]*maarten[ -_]*\(dutch[ -_]*part\)|(^|[^a-z0-9])sxm([^a-z0-9]|$)|(^|[^a-z0-9])sx([^a-z0-9]|$)
SY|Syrian Arab Republic|🇸🇾|syrian[ -_]*arab[ -_]*republic|(^|[^a-z0-9])syr([^a-z0-9]|$)|(^|[^a-z0-9])sy([^a-z0-9]|$)
SZ|Eswatini|🇸🇿|eswatini|kingdom[ -_]*of[ -_]*eswatini|(^|[^a-z0-9])swz([^a-z0-9]|$)|(^|[^a-z0-9])sz([^a-z0-9]|$)
TC|Turks and Caicos Islands|🇹🇨|turks[ -_]*and[ -_]*caicos[ -_]*islands|(^|[^a-z0-9])tca([^a-z0-9]|$)|(^|[^a-z0-9])tc([^a-z0-9]|$)
TD|Chad|🇹🇩|chad|republic[ -_]*of[ -_]*chad|(^|[^a-z0-9])tcd([^a-z0-9]|$)|(^|[^a-z0-9])td([^a-z0-9]|$)
TF|French Southern Territories|🇹🇫|french[ -_]*southern[ -_]*territories|(^|[^a-z0-9])atf([^a-z0-9]|$)|(^|[^a-z0-9])tf([^a-z0-9]|$)
TG|Togo|🇹🇬|togo|togolese[ -_]*republic|(^|[^a-z0-9])tgo([^a-z0-9]|$)|(^|[^a-z0-9])tg([^a-z0-9]|$)
TJ|Tajikistan|🇹🇯|tajikistan|republic[ -_]*of[ -_]*tajikistan|(^|[^a-z0-9])tjk([^a-z0-9]|$)|(^|[^a-z0-9])tj([^a-z0-9]|$)
TK|Tokelau|🇹🇰|tokelau|(^|[^a-z0-9])tkl([^a-z0-9]|$)|(^|[^a-z0-9])tk([^a-z0-9]|$)
TL|Timor-Leste|🇹🇱|timor[ -_]*leste|democratic[ -_]*republic[ -_]*of[ -_]*timor[ -_]*leste|(^|[^a-z0-9])tls([^a-z0-9]|$)|(^|[^a-z0-9])tl([^a-z0-9]|$)
TM|Turkmenistan|🇹🇲|turkmenistan|(^|[^a-z0-9])tkm([^a-z0-9]|$)|(^|[^a-z0-9])tm([^a-z0-9]|$)
TN|突尼斯|🇹🇳|突尼斯|tunisia|tunis|(^|[^a-z0-9])tn([^a-z0-9]|$)|(^|[^a-z0-9])tun([^a-z0-9]|$)|republic[ -_]*of[ -_]*tunisia
TO|Tonga|🇹🇴|tonga|kingdom[ -_]*of[ -_]*tonga|(^|[^a-z0-9])ton([^a-z0-9]|$)
TT|Trinidad and Tobago|🇹🇹|trinidad[ -_]*and[ -_]*tobago|republic[ -_]*of[ -_]*trinidad[ -_]*and[ -_]*tobago|(^|[^a-z0-9])tto([^a-z0-9]|$)|(^|[^a-z0-9])tt([^a-z0-9]|$)
TV|Tuvalu|🇹🇻|tuvalu|(^|[^a-z0-9])tuv([^a-z0-9]|$)|(^|[^a-z0-9])tv([^a-z0-9]|$)
TZ|坦桑尼亚|🇹🇿|坦桑尼亚|坦桑尼亞|tanzania|dar[ -_]*es[ -_]*salaam|(^|[^a-z0-9])tz([^a-z0-9]|$)|(^|[^a-z0-9])tza([^a-z0-9]|$)|tanzania,[ -_]*united[ -_]*republic[ -_]*of|united[ -_]*republic[ -_]*of[ -_]*tanzania
UG|乌干达|🇺🇬|乌干达|烏干達|uganda|kampala|(^|[^a-z0-9])ug([^a-z0-9]|$)|(^|[^a-z0-9])uga([^a-z0-9]|$)|republic[ -_]*of[ -_]*uganda
UM|United States Minor Outlying Islands|🇺🇲|united[ -_]*states[ -_]*minor[ -_]*outlying[ -_]*islands|(^|[^a-z0-9])umi([^a-z0-9]|$)|(^|[^a-z0-9])um([^a-z0-9]|$)
UY|乌拉圭|🇺🇾|乌拉圭|烏拉圭|uruguay|montevideo|(^|[^a-z0-9])uy([^a-z0-9]|$)|(^|[^a-z0-9])ury([^a-z0-9]|$)|蒙得维的亚|eastern[ -_]*republic[ -_]*of[ -_]*uruguay
UZ|Uzbekistan|🇺🇿|uzbekistan|republic[ -_]*of[ -_]*uzbekistan|(^|[^a-z0-9])uzb([^a-z0-9]|$)|(^|[^a-z0-9])uz([^a-z0-9]|$)
VA|Holy See (Vatican City State)|🇻🇦|holy[ -_]*see[ -_]*\(vatican[ -_]*city[ -_]*state\)|(^|[^a-z0-9])vat([^a-z0-9]|$)|(^|[^a-z0-9])va([^a-z0-9]|$)
VC|Saint Vincent and the Grenadines|🇻🇨|saint[ -_]*vincent[ -_]*and[ -_]*the[ -_]*grenadines|(^|[^a-z0-9])vct([^a-z0-9]|$)|(^|[^a-z0-9])vc([^a-z0-9]|$)
VE|委内瑞拉|🇻🇪|委内瑞拉|委內瑞拉|venezuela|caracas|(^|[^a-z0-9])ve([^a-z0-9]|$)|(^|[^a-z0-9])ven([^a-z0-9]|$)|加拉加斯|venezuela,[ -_]*bolivarian[ -_]*republic[ -_]*of|bolivarian[ -_]*republic[ -_]*of[ -_]*venezuela
VG|Virgin Islands, British|🇻🇬|virgin[ -_]*islands,[ -_]*british|british[ -_]*virgin[ -_]*islands|(^|[^a-z0-9])vgb([^a-z0-9]|$)|(^|[^a-z0-9])vg([^a-z0-9]|$)
VI|Virgin Islands, U.S.|🇻🇮|virgin[ -_]*islands,[ -_]*u\.s\.|virgin[ -_]*islands[ -_]*of[ -_]*the[ -_]*united[ -_]*states|(^|[^a-z0-9])vir([^a-z0-9]|$)|(^|[^a-z0-9])vi([^a-z0-9]|$)
VU|Vanuatu|🇻🇺|vanuatu|republic[ -_]*of[ -_]*vanuatu|(^|[^a-z0-9])vut([^a-z0-9]|$)|(^|[^a-z0-9])vu([^a-z0-9]|$)
WF|Wallis and Futuna|🇼🇫|wallis[ -_]*and[ -_]*futuna|(^|[^a-z0-9])wlf([^a-z0-9]|$)|(^|[^a-z0-9])wf([^a-z0-9]|$)
WS|Samoa|🇼🇸|samoa|independent[ -_]*state[ -_]*of[ -_]*samoa|(^|[^a-z0-9])wsm([^a-z0-9]|$)|(^|[^a-z0-9])ws([^a-z0-9]|$)
YE|Yemen|🇾🇪|yemen|republic[ -_]*of[ -_]*yemen|(^|[^a-z0-9])yem([^a-z0-9]|$)|(^|[^a-z0-9])ye([^a-z0-9]|$)
YT|Mayotte|🇾🇹|mayotte|(^|[^a-z0-9])myt([^a-z0-9]|$)|(^|[^a-z0-9])yt([^a-z0-9]|$)
ZM|Zambia|🇿🇲|zambia|republic[ -_]*of[ -_]*zambia|(^|[^a-z0-9])zmb([^a-z0-9]|$)|(^|[^a-z0-9])zm([^a-z0-9]|$)
ZW|Zimbabwe|🇿🇼|zimbabwe|republic[ -_]*of[ -_]*zimbabwe|(^|[^a-z0-9])zwe([^a-z0-9]|$)|(^|[^a-z0-9])zw([^a-z0-9]|$)
XK|科索沃|🇽🇰|科索沃|kosovo|pristina|(^|[^a-z0-9])xk([^a-z0-9]|$)|(^|[^a-z0-9])xkx([^a-z0-9]|$)
EOF_COUNTRY_MAP
}

country_label() {
    code="$1"
    country_map | awk -F'|' -v c="$code" '$1==c {print $2; exit}'
}

country_regex() {
    code="$1"
    country_map | awk -F'|' -v c="$code" '$1==c {for(i=3;i<=NF;i++){printf "%s%s", (i==3?"":"|"), $i} print ""; exit}'
}

sub_detect_countries() {
    names_file="$1"
    countries_file="$2"
    counts_file="$3"
    : > "$countries_file"
    : > "$counts_file"

    country_map | while IFS='|' read -r code label rest; do
        [ -n "$code" ] || continue
        regex="$(country_regex "$code")"
        [ -n "$regex" ] || continue
        count="$(grep -Eic "$regex" "$names_file" 2>/dev/null || echo 0)"
        count="$(printf '%s' "$count" | awk '{print $1}')"
        if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
            printf '%s\n' "$code" >> "$countries_file"
            printf '%s|%s|%s\n' "$code" "$label" "$count" >> "$counts_file"
        fi
    done
}

generate_password() {
    if [ -r /dev/urandom ] && have tr && have head; then
        pw="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 14)"
        if [ -n "$pw" ]; then
            printf '%s\n' "$pw"
            return 0
        fi
    fi
    printf 'mg%s%s\n' "$(date +%s 2>/dev/null || echo 0)" "$$"
}

get_account_default_password() {
    if [ -s "$ACCOUNT_DEFAULT_PASSWORD_FILE" ]; then
        sed -n '1p' "$ACCOUNT_DEFAULT_PASSWORD_FILE" 2>/dev/null
        return 0
    fi
    printf '%s\n' "$DEFAULT_ACCOUNT_PASSWORD"
}

validate_account_password() {
    pw="$1"
    [ -n "$pw" ] || die "默认密码不能为空"
    case "$pw" in
        *:*|*\"*|*\\*) die "默认密码不能包含冒号、双引号或反斜杠" ;;
        *' '*|*'\t'*) die "默认密码不能包含空格" ;;
    esac
    return 0
}

save_account_default_password() {
    pw="$1"
    validate_account_password "$pw"
    mkdir -p "$DATA_DIR" || die "创建数据目录失败：$DATA_DIR"
    printf '%s\n' "$pw" > "$ACCOUNT_DEFAULT_PASSWORD_FILE" || die "保存默认密码失败"
    chmod 600 "$ACCOUNT_DEFAULT_PASSWORD_FILE" 2>/dev/null || true
}

generate_accounts_file() {
    countries_file="$1"
    old_file="$2"
    new_file="$3"
    pw="$(get_account_default_password)"
    : > "$new_file"
    while IFS= read -r code; do
        [ -n "$code" ] || continue
        printf '%s:%s\n' "$code" "$pw" >> "$new_file"
    done < "$countries_file"
}

generate_sub_config_file() {
    out="$1"
    provider_path="$2"
    accounts_file="$3"
    countries_file="$4"

    cat > "$out" <<EOF_SUB_CONFIG
mode: rule
log-level: warning
ipv6: false

authentication:
EOF_SUB_CONFIG
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        printf '  - "%s"\n' "$line" >> "$out"
    done < "$accounts_file"

    cat >> "$out" <<EOF_SUB_CONFIG

listeners:
  - name: mixed-users
    type: mixed
    listen: 0.0.0.0
    port: $DEFAULT_MIXED_PORT
    udp: true

proxy-providers:
  mgate-sub:
    type: file
    path: "$provider_path"
    health-check:
      enable: false

proxy-groups:
EOF_SUB_CONFIG

    while IFS= read -r code; do
        [ -n "$code" ] || continue
        regex="$(country_regex "$code")"
        cat >> "$out" <<EOF_GROUP
  - name: $code
    type: select
    use:
      - mgate-sub
    filter: "(?i)$regex"

EOF_GROUP
    done < "$countries_file"

    cat >> "$out" <<EOF_RULES
rules:
EOF_RULES
    while IFS= read -r code; do
        [ -n "$code" ] || continue
        printf '  - IN-USER,%s,%s\n' "$code" "$code" >> "$out"
    done < "$countries_file"
    printf '  - MATCH,REJECT\n' >> "$out"
}

sub_update_from_url() {
    url="$1"
    [ -n "$url" ] || die "订阅链接为空"
    [ -x "$CORE_BIN" ] || die "Mihomo 内核不存在，请先执行：mgate install-core"
    ensure_sub_dirs

    sub_lock="$RUN_DIR/sub-update.lock"
    sub_lock_acquired=0
    if mkdir "$sub_lock" 2>/dev/null; then
        sub_lock_acquired=1
        trap 'if [ "${sub_lock_acquired:-0}" = "1" ]; then rmdir "$RUN_DIR/sub-update.lock" 2>/dev/null || true; fi' EXIT INT TERM
    else
        die "订阅更新正在进行中，请稍后再试"
    fi

    work="$TMP_DIR/sub-update.$$"
    rm -rf "$work"
    mkdir -p "$work" || die "创建临时目录失败：$work"
    tmp_sub="$work/sub.yaml"
    tmp_names="$work/names.txt"
    tmp_countries="$work/countries.txt"
    tmp_counts="$work/counts.txt"
    tmp_accounts="$work/accounts.txt"
    tmp_test_dir="$work/test-config"
    tmp_test_provider_dir="$tmp_test_dir/providers"
    tmp_test_provider_file="$tmp_test_provider_dir/sub.yaml"
    tmp_config_test="$tmp_test_dir/config.yaml"
    tmp_config_final="$work/config-final.yaml"
    mkdir -p "$tmp_test_provider_dir" || die "创建临时配置目录失败：$tmp_test_provider_dir"

    step "拉取订阅"
    info "订阅客户端：$SUB_USER_AGENT"
    sub_fetch_to_file "$url" "$tmp_sub" || die "订阅下载失败"
    validate_sub_file "$tmp_sub"

    step "识别节点国家/地区"
    extract_sub_names "$tmp_sub" "$tmp_names"
    node_count="$(wc -l < "$tmp_names" 2>/dev/null | awk '{print $1}')"
    [ "${node_count:-0}" -gt 0 ] 2>/dev/null || die "未提取到节点名称"
    sub_detect_countries "$tmp_names" "$tmp_countries" "$tmp_counts"
    country_count="$(wc -l < "$tmp_countries" 2>/dev/null | awk '{print $1}')"
    [ "${country_count:-0}" -gt 0 ] 2>/dev/null || die "未识别到可用国家/地区，请检查节点命名"
    info "节点数量：$node_count"
    info "识别国家/地区：$country_count"
    cat "$tmp_counts" | while IFS='|' read -r code label count; do
        info "$code $label：$count 个节点"
    done

    step "生成账号和配置"
    generate_accounts_file "$tmp_countries" "$SUB_ACCOUNTS_FILE" "$tmp_accounts"
    cp "$tmp_sub" "$tmp_test_provider_file" || die "写入临时 provider 失败"
    generate_sub_config_file "$tmp_config_test" "./providers/sub.yaml" "$tmp_accounts" "$tmp_countries"
    test_out="$work/test.out"
    printf '%s
' "$work" > "$SUB_LAST_TMP_FILE" 2>/dev/null || true
    # Mihomo restricts file provider paths to the configured home directory.
    # Test the subscription config with a temporary home directory that mirrors the final /opt/mgate/config layout.
    if ! "$CORE_BIN" -t -d "$tmp_test_dir" -f "$tmp_config_test" >"$test_out" 2>&1; then
        err "订阅配置测试失败"
        cp "$test_out" "$SUB_LAST_LOG_FILE" 2>/dev/null || true
        warn "已保留调试目录：$work"
        warn "临时配置目录：$tmp_test_dir"
        warn "临时配置文件：$tmp_config_test"
        warn "临时 provider：$tmp_test_provider_file"
        warn "测试错误日志：$SUB_LAST_LOG_FILE"
        sed 's/^/[DETAIL] /' "$test_out" 2>/dev/null | tail -n 80
        hint "可执行 mgate sub-debug 查看最近一次订阅失败详情"
        if [ "${sub_lock_acquired:-0}" = "1" ]; then
            rmdir "$sub_lock" 2>/dev/null || true
            sub_lock_acquired=0
            trap - EXIT INT TERM
        fi
        return 1
    fi

    generate_sub_config_file "$tmp_config_final" "./providers/sub.yaml" "$tmp_accounts" "$tmp_countries"

    step "备份并应用配置"
    backup_id="sub-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    cmd_backup "$backup_id" >/dev/null 2>&1 || true
    mkdir -p "$SUB_PROVIDER_DIR"
    cp "$tmp_sub" "$SUB_PROVIDER_FILE" || die "写入订阅 provider 失败"
    cp "$tmp_accounts" "$SUB_ACCOUNTS_FILE" || die "写入账号文件失败"
    cp "$tmp_countries" "$SUB_COUNTRIES_FILE" || die "写入国家文件失败"
    cp "$tmp_counts" "$SUB_STATUS_FILE" || die "写入订阅状态失败"
    printf '%s\n' "$url" > "$SUB_URL_FILE"
    date '+%Y-%m-%d %H:%M:%S' 2>/dev/null > "$SUB_LAST_UPDATE_FILE" || true
    cp "$tmp_config_final" "$CONFIG_FILE" || die "写入配置文件失败"
    chmod 600 "$CONFIG_FILE" "$SUB_ACCOUNTS_FILE" 2>/dev/null || true

    ok "订阅配置已更新"
    service_restart
    rm -rf "$work"
    if [ "${sub_lock_acquired:-0}" = "1" ]; then
        rmdir "$sub_lock" 2>/dev/null || true
        sub_lock_acquired=0
        trap - EXIT INT TERM
    fi
}


cmd_account_password() {
    action="${1:-}"
    case "$action" in
        "")
            info "当前代理账号默认密码：$(get_account_default_password)"
            info "默认密码文件：$ACCOUNT_DEFAULT_PASSWORD_FILE"
            if [ -s "$SUB_ACCOUNTS_FILE" ]; then
                step "当前自动账号"
                sed 's/^/[INFO] /' "$SUB_ACCOUNTS_FILE" 2>/dev/null
            fi
            ;;
        set)
            need_root
            pw="${2:-}"
            if [ -z "$pw" ]; then
                printf '请输入新的代理账号默认密码: '
                read -r pw
            fi
            save_account_default_password "$pw"
            ok "代理账号默认密码已更新"
            warn "客户端代理密码需要同步修改为新密码"
            if [ -s "$SUB_URL_FILE" ]; then
                step "重新生成订阅账号和配置"
                cmd_sub_update
            else
                hint "当前未启用订阅模式。下次订阅更新时会使用新默认密码。"
            fi
            ;;
        *)
            die "用法：mgate account-password 或 mgate account-password set <password>"
            ;;
    esac
}

cmd_sub_set() {
    need_root
    url="${1:-}"
    if [ -z "$url" ]; then
        printf '请输入 Clash/Mihomo 订阅链接: '
        read -r url
    fi
    [ -n "$url" ] || die "订阅链接为空"
    sub_update_from_url "$url"
}

cmd_sub_update() {
    need_root
    [ -s "$SUB_URL_FILE" ] || die "未设置订阅链接，请先执行：mgate sub-set <url>"
    url="$(cat "$SUB_URL_FILE" 2>/dev/null)"
    sub_update_from_url "$url"
}

cmd_sub_debug() {
    step "最近一次订阅调试信息"
    if [ -s "$SUB_LAST_TMP_FILE" ]; then
        last_tmp="$(cat "$SUB_LAST_TMP_FILE" 2>/dev/null)"
        info "调试目录：$last_tmp"
        [ -f "$last_tmp/test-config/config.yaml" ] && info "临时配置：$last_tmp/test-config/config.yaml"
        [ -f "$last_tmp/test-config/providers/sub.yaml" ] && info "临时 provider：$last_tmp/test-config/providers/sub.yaml"
        [ -f "$last_tmp/sub.yaml" ] && info "订阅缓存：$last_tmp/sub.yaml"
        [ -f "$last_tmp/names.txt" ] && info "节点名称：$last_tmp/names.txt"
        [ -f "$last_tmp/counts.txt" ] && info "识别统计：$last_tmp/counts.txt"
    else
        warn "暂无调试目录记录"
    fi
    if [ -s "$SUB_LAST_LOG_FILE" ]; then
        step "最近一次配置测试错误"
        sed 's/^/[DETAIL] /' "$SUB_LAST_LOG_FILE" 2>/dev/null | tail -n 120
    else
        warn "暂无订阅错误日志"
    fi
}

cmd_sub_status() {
    info "订阅模式：$([ -s "$SUB_URL_FILE" ] && echo enabled || echo disabled)"
    if [ -s "$SUB_URL_FILE" ]; then
        info "订阅链接：$(cat "$SUB_URL_FILE")"
    fi
    info "订阅客户端：$SUB_USER_AGENT"
    info "代理账号默认密码：$(get_account_default_password)"
    if [ -s "$SUB_LAST_UPDATE_FILE" ]; then
        info "上次更新：$(cat "$SUB_LAST_UPDATE_FILE")"
    fi
    if [ -s "$SUB_STATUS_FILE" ]; then
        step "识别到的国家/地区"
        while IFS='|' read -r code label count; do
            [ -n "$code" ] || continue
            info "$code $label：$count 个节点"
        done < "$SUB_STATUS_FILE"
    else
        warn "暂无订阅识别结果"
    fi
    if [ -s "$SUB_ACCOUNTS_FILE" ]; then
        step "账号列表"
        cat "$SUB_ACCOUNTS_FILE" | sed 's/^/[INFO] /'
    else
        warn "暂无自动生成账号"
    fi
}

cmd_sub_clear() {
    need_root
    say "这将清除订阅链接、订阅缓存和自动账号文件。当前 config.yaml 不会自动恢复为手动模板。"
    if [ "${MGATE_ASSUME_YES:-0}" != "1" ]; then
        printf '输入 CLEAR 确认: '
        read -r ans
        [ "$ans" = "CLEAR" ] || die "已取消"
    fi
    cmd_backup "pre-sub-clear" >/dev/null 2>&1 || true
    rm -f "$SUB_URL_FILE" "$SUB_STATUS_FILE" "$SUB_COUNTRIES_FILE" "$SUB_ACCOUNTS_FILE" "$SUB_LAST_UPDATE_FILE" "$SUB_PROVIDER_FILE"
    ok "订阅信息已清除"
    hint "如需重新生成手动模板：FORCE=1 mgate install"
}


cmd_proxy_info() {
    host="设备IP"
    mixed_port="$(config_listener_port mixed-users "$DEFAULT_MIXED_PORT")"
    info "Mixed 代理端口：$mixed_port"
    info "同一个端口同时支持 HTTP 和 SOCKS5 协议"
    if [ -f "$CONFIG_FILE" ]; then
        step "代理连接信息"
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
            info "$user HTTP  : http://$user:$pass@$host:$mixed_port"
            info "$user SOCKS5: socks5://$user:$pass@$host:$mixed_port"
        done
    else
        warn "配置文件不存在：$CONFIG_FILE"
    fi
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

用法：
  mgate                     进入 TUI 菜单

安装与更新：
  mgate install             初始化/修复 mgate 工作区
  mgate self-update         从 GitHub 更新 mgate 管理脚本
  mgate update              self-update 的别名
  mgate install-core        安装/更新 Mihomo 内核
  mgate uninstall-core      仅卸载 Mihomo 内核，保留配置和管理脚本
  mgate uninstall [--yes]   完整卸载 mgate

服务管理：
  mgate start               启动服务
  mgate stop                停止服务
  mgate restart             重启服务
  mgate status              查看服务状态
  mgate enable              设置开机启动
  mgate disable             关闭开机启动

配置与诊断：
  mgate config              查看配置
  mgate edit                编辑配置
  mgate test                测试配置
  mgate logs [50|100|200]   查看日志
  mgate doctor              系统诊断

备份与恢复：
  mgate backup [label]      创建备份
  mgate backups             查看备份列表
  mgate restore [id|latest] 恢复备份

订阅管理：
  mgate sub-set <url>       设置/替换订阅并立即更新配置
  mgate sub-update          拉取已保存订阅并更新配置
  mgate sub-status          查看订阅状态和账号
  mgate sub-debug           查看最近一次订阅失败详情
  mgate sub-clear           清除订阅设置和缓存

账号与连接：
  mgate account-password    查看/修改代理账号默认密码
  mgate passwd              account-password 的别名
  mgate proxy-info          查看代理连接信息

Web 管理：
  mgate web-enable          开启 Web 管理
  mgate web-disable         关闭 Web 管理并关闭开机自启
  mgate web-start           启动 Web 管理服务
  mgate web-stop            停止 Web 管理服务
  mgate web-restart         重启 Web 管理服务
  mgate web-status          查看 Web 管理状态
  mgate web-token [reset]   查看或重置 Web Token
  mgate web-refresh         重新生成 Web 页面文件

其他：
  mgate version             查看版本
  mgate help                查看帮助
EOF_USAGE
}
menu() {
    while :; do
        say ""
        say "mgate - Mobile Gateway Manager"
        say "Workspace: $WORKDIR"
        say ""
        say "安装与更新"
        say "1)  初始化/修复 mgate 工作区"
        say "2)  更新 mgate 管理脚本（从 GitHub）"
        say "3)  安装/更新 Mihomo 内核"
        say "4)  卸载 Mihomo 内核"
        say "5)  完整卸载 mgate"
        say ""
        say "服务管理"
        say "6)  启动服务"
        say "7)  停止服务"
        say "8)  重启服务"
        say "9)  查看服务状态"
        say "10) 设置开机启动"
        say "11) 关闭开机启动"
        say ""
        say "配置与诊断"
        say "12) 查看配置"
        say "13) 编辑配置"
        say "14) 测试配置"
        say "15) 查看日志"
        say "16) 系统诊断"
        say ""
        say "备份与恢复"
        say "17) 创建备份"
        say "18) 查看备份列表"
        say "19) 恢复备份"
        say ""
        say "订阅管理"
        say "20) 设置/替换订阅"
        say "21) 更新订阅"
        say "22) 查看订阅状态"
        say "23) 查看订阅调试信息"
        say "24) 清除订阅设置"
        say ""
        say "账号与连接"
        say "25) 查看代理账号默认密码"
        say "26) 修改代理账号默认密码"
        say "27) 查看代理连接信息"
        say ""
        say "版本信息"
        say "28) 查看版本"
        say ""
        say "Web 管理"
        say "29) 开启 Web 管理"
        say "30) 关闭 Web 管理"
        say "31) 启动 Web 管理"
        say "32) 停止 Web 管理"
        say "33) 查看 Web 管理状态"
        say "34) 重置 Web 管理 Token"
        say "35) 刷新 Web 管理文件"
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
            17) cmd_backup; pause_enter ;;
            18) cmd_backups; pause_enter ;;
            19) cmd_restore; pause_enter ;;
            20) cmd_sub_set; pause_enter ;;
            21) cmd_sub_update; pause_enter ;;
            22) cmd_sub_status; pause_enter ;;
            23) cmd_sub_debug; pause_enter ;;
            24) cmd_sub_clear; pause_enter ;;
            25) cmd_account_password; pause_enter ;;
            26) cmd_account_password set; pause_enter ;;
            27) cmd_proxy_info; pause_enter ;;
            28) cmd_version; pause_enter ;;
            29) web_enable; pause_enter ;;
            30) web_disable; pause_enter ;;
            31) web_start; pause_enter ;;
            32) web_stop; pause_enter ;;
            33) web_status; pause_enter ;;
            34) web_token reset; pause_enter ;;
            35) web_refresh; pause_enter ;;
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
        backup) cmd_backup "$@" ;;
        backups) cmd_backups "$@" ;;
        restore) cmd_restore "$@" ;;
        sub-set) cmd_sub_set "$@" ;;
        sub-update) cmd_sub_update "$@" ;;
        sub-status) cmd_sub_status "$@" ;;
        account-password|passwd) cmd_account_password "$@" ;;
        proxy-info) cmd_proxy_info "$@" ;;
        sub-debug) cmd_sub_debug "$@" ;;
        sub-clear) cmd_sub_clear "$@" ;;
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
