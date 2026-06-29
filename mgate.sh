#!/bin/sh
# mgate - Mobile Gateway Manager for Mihomo
# POSIX/BusyBox friendly management script.

set -u
umask 022

APP_NAME="mgate"
APP_DESC="Mobile Gateway Manager"
MGATE_VERSION="0.4.0-rc14"

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

AP_CONFIG_FILE="$CONFIG_DIR/ap.conf"
AP_RUN_DIR="$RUN_DIR/ap"
AP_HOSTAPD_CONF="$AP_RUN_DIR/hostapd.conf"
AP_DNSMASQ_CONF="$AP_RUN_DIR/dnsmasq.conf"
AP_HOSTAPD_PID_FILE="$AP_RUN_DIR/hostapd.pid"
AP_DNSMASQ_PID_FILE="$AP_RUN_DIR/dnsmasq.pid"
AP_OWNER_FILE="$AP_RUN_DIR/ap0.owner"
AP_HOSTAPD_LOG_FILE="$LOG_DIR/ap-hostapd.log"
AP_DNSMASQ_LOG_FILE="$LOG_DIR/ap-dnsmasq.log"
AP_DEP_PACKAGES="hostapd dnsmasq iw iproute2"

GATEWAY_RUN_DIR="$RUN_DIR/gateway"
GATEWAY_IP_FORWARD_PREV="$GATEWAY_RUN_DIR/ip_forward.prev"
GATEWAY_BACKEND_FILE="$GATEWAY_RUN_DIR/backend"
GATEWAY_NAT_CHAIN="MGATE_NAT_POSTROUTING"
GATEWAY_FORWARD_CHAIN="MGATE_FORWARD"
TPROXY_MANGLE_CHAIN="${MGATE_TPROXY_MANGLE_CHAIN:-MGATE_TPROXY}"
TPROXY_MARK="${MGATE_TPROXY_MARK:-0x1}"
TPROXY_ROUTE_TABLE="${MGATE_TPROXY_ROUTE_TABLE:-100}"
TPROXY_PORT="${MGATE_TPROXY_PORT:-31802}"
TPROXY_OUT_GROUP="${MGATE_TPROXY_OUT_GROUP:-TPROXY-OUT}"
TPROXY_SOCKET_BYPASS="${MGATE_TPROXY_SOCKET_BYPASS:-0}"
TPROXY_ENABLED_FILE="$DATA_DIR/tproxy.enabled"
TPROXY_LAST_ERROR_FILE="$DATA_DIR/tproxy.last_error"
TPROXY_CONFIG_BACKUP_FILE="$DATA_DIR/tproxy.config_backup"
TPROXY_CONFIG_OWNED_FILE="$DATA_DIR/tproxy.config_owned"
TPROXY_LOG_FILE="$LOG_DIR/tproxy.log"

DEFAULT_MIXED_PORT="${MIXED_PORT:-31800}"
# Backward-compatible internal aliases. The default proxy entry is now a single mixed listener.
DEFAULT_SOCKS_PORT="$DEFAULT_MIXED_PORT"
DEFAULT_HTTP_PORT="$DEFAULT_MIXED_PORT"
DEFAULT_MIHOMO_API_PORT="${MGATE_MIHOMO_API_PORT:-9090}"

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
SUB_NODES_FILE="$DATA_DIR/sub.nodes"
SUB_UNMATCHED_FILE="$DATA_DIR/sub.unmatched"

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
missing() { _msg "MISSING" "$@"; }
warn() { _msg "WARN" "$@" >&2; }
err() { _msg "ERROR" "$@" >&2; }

die() {
    err "$*"
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

check_no_crlf_file() {
    file="$1"
    [ -f "$file" ] || return 0
    if have od && od -An -tx1 "$file" >/dev/null 2>&1; then
        od -An -tx1 "$file" 2>/dev/null | awk -v f="$file" '
            BEGIN { line=1; prev="" }
            {
                for (i=1; i<=NF; i++) {
                    b=tolower($i)
                    if (prev == "0d" && b == "0a") {
                        print f ":" line ": CRLF line ending detected"
                        found=1
                    }
                    if (b == "0a") line++
                    prev=b
                }
            }
            END { exit found ? 1 : 0 }
        '
        return $?
    fi
    awk 'BEGIN { cr=sprintf("%c", 13) } length($0) > 0 && substr($0, length($0), 1) == cr { print FILENAME ":" FNR ": CRLF line ending detected"; found=1 } END { exit found ? 1 : 0 }' "$file"
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

ensure_ap_dirs() {
    ensure_dirs
    mkdir -p "$AP_RUN_DIR" || die "failed to create $AP_RUN_DIR"
}

ensure_gateway_dirs() {
    ensure_dirs
    mkdir -p "$GATEWAY_RUN_DIR" || die "failed to create $GATEWAY_RUN_DIR"
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
allow-lan: true
bind-address: '*'
tproxy-port: __TPROXY_PORT__
external-controller: 127.0.0.1:__MIHOMO_API_PORT__

profile:
  store-selected: true

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
  - name: TPROXY-OUT
    type: select
    proxies:
      - node-DE
      - node-JP
      - node-US
      - node-UK

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
  - IN-TYPE,TPROXY,TPROXY-OUT
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
        -e "s/__HTTP_PORT__/$DEFAULT_HTTP_PORT/g" \
        -e "s/__TPROXY_PORT__/$TPROXY_PORT/g" \
        -e "s/__MIHOMO_API_PORT__/$DEFAULT_MIHOMO_API_PORT/g"
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
ExecStartPre=/bin/sleep 3
ExecStart=$CORE_BIN -d $CONFIG_DIR
Restart=always
RestartSec=5
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
    check_no_crlf_file "$file" || die "下载内容包含 CRLF 行尾，请转换为 LF 后重试"
    /bin/sh -n "$file" >/dev/null 2>&1 || die "下载内容不是有效 shell 脚本"
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
    step "自动执行 migrate 同步配置和生成文件"
    "$SCRIPT_PATH" migrate || warn "migrate 未完全成功，请手动执行：mgate migrate"
    hint "执行 mgate version 查看版本信息"
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
TPROXY_PORT="__TPROXY_PORT__"
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
<a class="btn" href="/cgi-bin/mgate.cgi?action=gateway-status">网关状态</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=tproxy-health">TProxy 健康</a>
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
    keep="${1:-20}"
    case "$keep" in ''|*[!0-9]*) keep=20 ;; esac
    first_delete=$((keep + 1))
    mkdir -p "$WEB_JOB_DIR" 2>/dev/null || return 0
    # Each job has .log/.status/.meta files. Keep only the newest status-backed jobs.
    ls -1t "$WEB_JOB_DIR"/*.status 2>/dev/null | sed -n "${first_delete},\$p" | while IFS= read -r st; do
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

run_job_page_delayed() {
    delay="$1"
    shift
    title="$1"
    shift
    if ! mkdir -p "$WEB_JOB_DIR" 2>/dev/null; then
        header
        page_start "$title"
        nav
        cat <<'EOF'
<div class="card"><h2>任务未启动</h2><p>无法创建 Web 任务目录，请检查 /opt/mgate/run/web-jobs/ 权限。</p></div>
EOF
        page_end
        return 0
    fi
    # Leave room for the new job so the directory is capped at 20 after creation.
    job_cleanup 19
    id="$(job_id_new)"
    base="$WEB_JOB_DIR/$id"
    printf 'running\n' > "$base.status"
    printf '%s\n' "$title" > "$base.meta"
    (
        printf '[STEP] 开始执行：%s\n' "$title"
        printf '[INFO] 命令：mgate'
        for a in "$@"; do printf ' %s' "$a"; done
        printf '\n'
        case "$delay" in
            ''|0) : ;;
            *[!0-9]*) : ;;
            *)
                printf '[INFO] %s 秒后执行，浏览器可先进入任务页。\n' "$delay"
                sleep "$delay"
                ;;
        esac
        "$MGATE" "$@"
        rc=$?
        printf '[INFO] exit code: %s\n' "$rc"
        if [ "$rc" -eq 0 ]; then
            printf 'success\n' > "$base.status"
        else
            printf 'failed\n' > "$base.status"
        fi
    ) </dev/null > "$base.log" 2>&1 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&- &
    _CGI_LOCATION="/cgi-bin/mgate.cgi?action=job&id=$id"
}

run_job_page() {
    run_job_page_delayed 0 "$@"
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


web_value() {
    data="$1"
    key="$2"
    printf '%s\n' "$data" | sed -n "s/^\[[^]]*\] $key:[[:space:]]*//p" | head -n 1
}

web_tproxy_out_type() {
    [ -f "$CONFIG_FILE" ] || { printf 'unknown\n'; return 0; }
    awk '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_group=0; in_groups=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            in_group=(line == "TPROXY-OUT")
            next
        }
        in_group && /^[[:space:]]*type:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*type:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            print line
            found=1
            exit
        }
        END {if (!found) print "unknown"}
    ' "$CONFIG_FILE" 2>/dev/null | head -n 1
}

web_class_for_state() {
    case "$1" in
        yes|active|running|healthy|enabled|nat|tproxy) printf 'good\n' ;;
        no|inactive|stopped|disabled|degraded|partial|unknown) printf 'warn\n' ;;
        broken|failed) printf 'danger\n' ;;
        *) printf '\n' ;;
    esac
}

web_json_section_value() {
    data="$1"
    section="$2"
    key="$3"
    printf '%s\n' "$data" | awk -v section="$section" -v key="$key" '
        !in_section && index($0, "\"" section "\"") > 0 && index($0, "{") > 0 {in_section=1; next}
        in_section && /^[[:space:]]*}/ {exit}
        in_section && index($0, "\"" key "\"") > 0 {
            line=$0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            sub(/[[:space:]]*,[[:space:]]*$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            print line
            exit
        }
    '
}

web_json_scalar() {
    raw="$1"
    case "$raw" in
        \"*\")
            printf '%s' "$raw" | sed 's/^"//; s/"$//; s/\\"/"/g; s/\\\\/\\/g'
            ;;
        true|false|null) printf '%s' "$raw" ;;
        *) printf '%s' "$raw" ;;
    esac
}

web_json_bool_state() {
    raw="$1"
    yes_value="$2"
    no_value="$3"
    case "$raw" in
        true) printf '%s\n' "$yes_value" ;;
        false) printf '%s\n' "$no_value" ;;
        *) printf 'unknown\n' ;;
    esac
}

web_collect_gateway_state_from_json() {
    data="$1"
    printf '%s\n' "$data" | grep '"ok"[[:space:]]*:[[:space:]]*true' >/dev/null 2>&1 || return 1

    ap_running_raw="$(web_json_section_value "$data" ap running)"
    ap_healthy_raw="$(web_json_section_value "$data" ap healthy)"
    ap_ip_raw="$(web_json_section_value "$data" ap ip)"
    gateway_mode_raw="$(web_json_section_value "$data" gateway mode)"
    fallback_raw="$(web_json_section_value "$data" gateway fallback_active)"
    tproxy_state_raw="$(web_json_section_value "$data" tproxy state)"
    final_health_raw="$(web_json_section_value "$data" summary final_health)"

    [ -n "$ap_running_raw" ] || return 1
    [ -n "$gateway_mode_raw" ] || return 1
    [ -n "$fallback_raw" ] || return 1
    [ -n "$tproxy_state_raw" ] || return 1
    [ -n "$final_health_raw" ] || return 1

    WEB_AP_STATE="$(web_json_bool_state "$ap_running_raw" running stopped)"
    WEB_AP_HEALTHY="$(web_json_bool_state "$ap_healthy_raw" yes no)"
    WEB_AP_IP="$(web_json_scalar "$ap_ip_raw")"
    [ -n "$WEB_AP_IP" ] && [ "$WEB_AP_IP" != "null" ] || WEB_AP_IP="none"

    WEB_GATEWAY_MODE="$(web_json_scalar "$gateway_mode_raw")"
    case "$WEB_GATEWAY_MODE" in nat|tproxy|unknown) : ;; *) WEB_GATEWAY_MODE="unknown" ;; esac

    WEB_NAT_FALLBACK="$(web_json_bool_state "$fallback_raw" active inactive)"
    WEB_TPROXY_ENABLED="$(web_json_scalar "$tproxy_state_raw")"
    case "$WEB_TPROXY_ENABLED" in enabled|disabled|partial|unknown) : ;; *) WEB_TPROXY_ENABLED="unknown" ;; esac

    WEB_FINAL_HEALTH="$(web_json_scalar "$final_health_raw")"
    case "$WEB_FINAL_HEALTH" in healthy|degraded|broken|disabled|unknown) : ;; *) WEB_FINAL_HEALTH="unknown" ;; esac

    WEB_IPV4_FORWARDING="unknown"
    WEB_TPROXY_PORT="none"
    WEB_TPROXY_OUT_TYPE="unknown"
    WEB_MIHOMO_RUNNING="unknown"
    WEB_GATEWAY_STATUS_OUT=""
    WEB_TPROXY_STATUS_OUT=""
    WEB_SUMMARY_SOURCE="status-json"
    return 0
}

web_collect_gateway_state() {
    WEB_STATUS_OUT="$1"
    WEB_STATUS_JSON_OUT="$($MGATE status-json 2>/dev/null || true)"
    if [ -n "$WEB_STATUS_JSON_OUT" ] && web_collect_gateway_state_from_json "$WEB_STATUS_JSON_OUT"; then
        return 0
    fi
    WEB_SUMMARY_SOURCE="text-fallback"
    web_collect_gateway_state_from_text "$WEB_STATUS_OUT"
}
web_collect_gateway_state_from_text() {
    WEB_STATUS_OUT="$1"
    WEB_AP_STATUS_OUT="$($MGATE ap-status 2>&1)"
    WEB_GATEWAY_STATUS_OUT="$($MGATE gateway-status 2>&1)"
    WEB_TPROXY_STATUS_OUT="$($MGATE tproxy-status 2>&1)"

    WEB_AP_EXISTS="$(web_value "$WEB_AP_STATUS_OUT" 'ap0 exists')"
    WEB_AP_LINK="$(web_value "$WEB_AP_STATUS_OUT" 'ap0 link')"
    WEB_AP_IP="$(web_value "$WEB_AP_STATUS_OUT" 'ap0 ip')"
    [ -n "$WEB_AP_IP" ] || WEB_AP_IP="none"
    WEB_HOSTAPD_RUNNING="$(web_value "$WEB_AP_STATUS_OUT" 'hostapd running')"
    WEB_DNSMASQ_RUNNING="$(web_value "$WEB_AP_STATUS_OUT" 'dnsmasq running')"
    if [ "$WEB_AP_LINK" = "up" ] && [ "$WEB_HOSTAPD_RUNNING" = "yes" ] && [ "$WEB_DNSMASQ_RUNNING" = "yes" ]; then
        WEB_AP_STATE="running"
        WEB_AP_HEALTHY="yes"
    elif [ "$WEB_AP_EXISTS" = "no" ] || [ "$WEB_HOSTAPD_RUNNING" = "no" ] || [ "$WEB_DNSMASQ_RUNNING" = "no" ]; then
        WEB_AP_STATE="stopped"
        WEB_AP_HEALTHY="no"
    else
        WEB_AP_STATE="unknown"
        WEB_AP_HEALTHY="no"
    fi

    WEB_IPV4_FORWARDING="$(web_value "$WEB_GATEWAY_STATUS_OUT" 'ipv4 forwarding')"
    [ "$WEB_IPV4_FORWARDING" = "1" ] && WEB_IPV4_FORWARDING="yes"
    [ "$WEB_IPV4_FORWARDING" = "0" ] && WEB_IPV4_FORWARDING="no"
    [ -n "$WEB_IPV4_FORWARDING" ] || WEB_IPV4_FORWARDING="unknown"
    WEB_NAT_ACTIVE_RAW="$(web_value "$WEB_GATEWAY_STATUS_OUT" 'nat rules active')"
    case "$WEB_NAT_ACTIVE_RAW" in
        yes) WEB_NAT_FALLBACK="active" ;;
        no) WEB_NAT_FALLBACK="inactive" ;;
        *)
            WEB_FALLBACK_RAW="$(web_value "$WEB_TPROXY_STATUS_OUT" 'gateway fallback active')"
            case "$WEB_FALLBACK_RAW" in
                yes) WEB_NAT_FALLBACK="active" ;;
                no) WEB_NAT_FALLBACK="inactive" ;;
                *) WEB_NAT_FALLBACK="unknown" ;;
            esac
            ;;
    esac

    WEB_TPROXY_ENABLED="$(web_value "$WEB_TPROXY_STATUS_OUT" 'tproxy enabled')"
    [ -n "$WEB_TPROXY_ENABLED" ] || WEB_TPROXY_ENABLED="unknown"
    WEB_TPROXY_PORT="$(web_value "$WEB_TPROXY_STATUS_OUT" 'mihomo tproxy-port')"
    [ -n "$WEB_TPROXY_PORT" ] || WEB_TPROXY_PORT="none"
    WEB_TPROXY_OUT_TYPE="$(web_tproxy_out_type)"
    [ -n "$WEB_TPROXY_OUT_TYPE" ] || WEB_TPROXY_OUT_TYPE="unknown"

    WEB_MIHOMO_RUNNING="no"
    printf '%s\n' "$WEB_STATUS_OUT" | grep -Ei 'active|running' >/dev/null 2>&1 && WEB_MIHOMO_RUNNING="yes"

    case "$WEB_TPROXY_ENABLED" in
        yes) WEB_GATEWAY_MODE="tproxy" ;;
        no)
            if [ "$WEB_NAT_FALLBACK" = "active" ]; then WEB_GATEWAY_MODE="nat"; else WEB_GATEWAY_MODE="unknown"; fi
            ;;
        partial) WEB_GATEWAY_MODE="tproxy" ;;
        *) WEB_GATEWAY_MODE="unknown" ;;
    esac

    case "$WEB_TPROXY_ENABLED" in
        yes)
            if [ "$WEB_AP_HEALTHY" = "yes" ] && [ "$WEB_MIHOMO_RUNNING" = "yes" ] && [ "$WEB_NAT_FALLBACK" = "active" ] && [ "$WEB_TPROXY_PORT" != "none" ]; then
                WEB_FINAL_HEALTH="healthy"
            else
                WEB_FINAL_HEALTH="degraded"
            fi
            ;;
        no) WEB_FINAL_HEALTH="disabled" ;;
        partial) WEB_FINAL_HEALTH="broken" ;;
        *) WEB_FINAL_HEALTH="unknown" ;;
    esac
}

web_table_row() {
    label="$1"
    value="$2"
    printf '<tr><th>%s</th><td><span class="code">%s</span></td></tr>\n' \
        "$(printf '%s' "$label" | html_escape)" \
        "$(printf '%s' "$value" | html_escape)"
}

gateway_status_page() {
    header
    page_start "网关状态"
    nav
    status_out="$($MGATE status 2>&1)"
    web_collect_gateway_state_from_text "$status_out"
    cat <<'EOF'
<div class="card"><h2>网关状态</h2>
<table class="table"><tbody>
EOF
    web_table_row "AP 接口" "ap0"
    web_table_row "上游接口" "wlan0"
    web_table_row "AP IP" "$WEB_AP_IP"
    web_table_row "AP 健康" "$WEB_AP_HEALTHY"
    web_table_row "网关模式" "$WEB_GATEWAY_MODE"
    web_table_row "IPv4 转发" "$WEB_IPV4_FORWARDING"
    web_table_row "NAT fallback" "$WEB_NAT_FALLBACK"
    web_table_row "TProxy 状态" "$WEB_TPROXY_ENABLED"
    web_table_row "mihomo 运行" "$WEB_MIHOMO_RUNNING"
    web_table_row "tproxy-port" "$WEB_TPROXY_PORT"
    web_table_row "TPROXY-OUT 类型" "$WEB_TPROXY_OUT_TYPE"
    web_table_row "健康结果" "$WEB_FINAL_HEALTH"
    cat <<'EOF'
</tbody></table>
<p><a class="btn" href="/cgi-bin/mgate.cgi?action=tproxy-health">TProxy 健康</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=gateway-doctor">网关诊断</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=tproxy-doctor">TProxy 诊断</a></p>
</div>
EOF

    printf '<div class="card"><h2>gateway-status</h2><pre>'
    printf '%s\n' "$WEB_GATEWAY_STATUS_OUT" | html_escape
    printf '</pre></div>\n'
    printf '<div class="card"><h2>tproxy-status</h2><pre>'
    printf '%s\n' "$WEB_TPROXY_STATUS_OUT" | html_escape
    printf '</pre></div>\n'
    page_end
}
status_page() {
    header
    page_start "状态"
    nav
    status_out="$($MGATE status 2>&1)"
    version_out="$($MGATE version 2>&1)"
    web_collect_gateway_state "$status_out"

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
    summary_card "AP" "$WEB_AP_STATE" "$(web_class_for_state "$WEB_AP_STATE")"
    summary_card "网关模式" "$WEB_GATEWAY_MODE" "$(web_class_for_state "$WEB_GATEWAY_MODE")"
    summary_card "NAT fallback" "$WEB_NAT_FALLBACK" "$(web_class_for_state "$WEB_NAT_FALLBACK")"
    summary_card "TProxy" "$WEB_TPROXY_ENABLED" "$(web_class_for_state "$WEB_TPROXY_ENABLED")"
    summary_card "健康状态" "$WEB_FINAL_HEALTH" "$(web_class_for_state "$WEB_FINAL_HEALTH")"
    cat <<'EOF'
</div></div>
EOF
    cat <<'EOF'
<div class="card"><h2>网关状态</h2>
<p><span class="pill">只读</span></p>
<p><a class="btn" href="/cgi-bin/mgate.cgi?action=gateway-status">网关状态</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=tproxy-health">TProxy 健康</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=gateway-doctor">网关诊断</a>
<a class="btn" href="/cgi-bin/mgate.cgi?action=tproxy-doctor">TProxy 诊断</a></p>
</div>
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

request_proxy_host() {
    host="${HTTP_HOST:-}"
    host="${host#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    [ -n "$host" ] || host="设备IP"
    case "$host" in
        *:*) host="${host%%:*}" ;;
    esac
    printf '%s\n' "$host"
}

proxy_info_page() {
    host="$(request_proxy_host)"
    mixed_port="$(listener_port mixed-users "$DEFAULT_MIXED_PORT")"
    tproxy_port="$(tproxy_mihomo_port 2>/dev/null || true)"
    [ -n "$tproxy_port" ] || tproxy_port="$TPROXY_PORT"
    out_type="$(awk '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_group=0; in_groups=0}
        in_groups && /name:[[:space:]]*TPROXY-OUT/ {in_group=1; next}
        in_group && /^[[:space:]]*type:[[:space:]]*/ {
            sub(/.*type:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit
        }
    ' "$CONFIG_FILE" 2>/dev/null | head -1)"
    [ -n "$out_type" ] || out_type="unknown"

    header
    page_start "连接信息"
    nav
    cat <<EOF
<div class="card">
<h2>Mixed 代理连接信息</h2>
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
    cat <<EOF
</tbody></table>
</div>
<div class="card">
<h2>TProxy 透明代理端口</h2>
<p class="muted">TProxy 端口由 mihomo 启动后自动监听，AP 客户端流量由 iptables 规则自动重定向，无需客户端手动配置代理。</p>
<table class="table"><tbody>
<tr><td>端口</td><td><span class="code">$tproxy_port</span></td></tr>
<tr><td>协议</td><td>TCP / UDP 透明代理</td></tr>
<tr><td>监听地址</td><td><span class="code">0.0.0.0:$tproxy_port</span></td></tr>
<tr><td>启用方式</td><td>mgate start 后自动监听；mgate tproxy-start 后流量才实际转入</td></tr>
</tbody></table>
</div>
<div class="card">
<h2>透明代理节点切换</h2>
<p class="muted">TProxy 流量由 <span class="code">TPROXY-OUT</span> 代理组统一处理。</p>
<table class="table"><tbody>
<tr><td>TPROXY-OUT 类型</td><td><span class="code">$out_type</span></td></tr>
EOF
    case "$out_type" in
        url-test)
            cat <<'EOF'
<tr><td>节点选择</td><td>自动测速，选最快节点</td></tr>
</tbody></table>
<p class="muted">订阅模式下 TPROXY-OUT 自动测速并选择最快节点，无需手动切换。如需固定到某个节点，请执行 <span class="code">mgate edit</span>，将 TPROXY-OUT 类型改为 <span class="code">select</span> 并指定目标代理，然后执行 <span class="code">mgate restart</span>。</p>
EOF
            ;;
        select)
            cat <<'EOF'
<tr><td>节点选择</td><td>手动指定</td></tr>
</tbody></table>
<p class="muted">手动模式下请执行 <span class="code">mgate edit</span>，在 TPROXY-OUT 的 proxies 列表中调整顺序或选择目标代理，然后执行 <span class="code">mgate restart</span> 生效。</p>
EOF
            ;;
        *)
            cat <<'EOF'
<tr><td>节点选择</td><td>-</td></tr>
</tbody></table>
<p class="muted">当前 config.yaml 中没有 TPROXY-OUT 代理组，这通常是因为配置文件是在本次更新前生成的。</p>
<p class="muted">修复方法：如果使用订阅，请执行 <span class="code">mgate sub-update</span> 重新生成配置；如果使用手动配置，请执行 <span class="code">FORCE=1 mgate install</span> 重建配置文件。之后再执行 <span class="code">mgate web-refresh &amp;&amp; mgate web-restart</span> 刷新页面。</p>
EOF
            ;;
    esac
    cat <<'EOF'
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
    page_start "退出登录"
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
        gateway-status) gateway_status_page ;;
        tproxy-health) run_job_page "TProxy 健康" tproxy-health ;;
        gateway-doctor) run_job_page "网关诊断" gateway-doctor ;;
        tproxy-doctor) run_job_page "TProxy 诊断" tproxy-doctor ;;
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
                web-disable) run_job_page_delayed 2 "关闭 Web 管理" web-disable ;;
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
        -e "s#__TPROXY_PORT__#$TPROXY_PORT#g" \
        -e "s#__MIHOMO_API_PORT__#$DEFAULT_MIHOMO_API_PORT#g" \
        "$WEB_CGI_FILE"

    chmod 755 "$WEB_CGI_FILE" || die "failed to chmod $WEB_CGI_FILE"
    check_no_crlf_file "$WEB_CGI_FILE" || die "generated CGI contains CRLF line endings; convert it to LF"
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
ExecStartPre=/bin/sleep 3
ExecStart=$httpd_cmd -f -p $WEB_LISTEN:$WEB_PORT -h $WEB_DIR
Restart=always
RestartSec=5
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
# -----------------------------
# AP management: ap0 only, no routing/NAT/TProxy
# -----------------------------
ap_default_config() {
    cat <<'EOF_AP_CONFIG'
ssid=mgate
password=mgate12345678
interface=ap0
upstream=wlan0
ipaddr=10.88.0.1
netmask=255.255.255.0
dhcp_start=10.88.0.100
dhcp_end=10.88.0.200
dhcp_lease=12h
EOF_AP_CONFIG
}

ap_config_get() {
    key="$1"
    def="$2"
    if [ -f "$AP_CONFIG_FILE" ]; then
        awk -F= -v k="$key" -v d="$def" '
            /^[[:space:]]*#/ {next}
            {
                name=$1
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                if (name == k) {
                    val=$0
                    sub(/^[^=]*=/, "", val)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                    print val
                    found=1
                    exit
                }
            }
            END {if (!found) print d}
        ' "$AP_CONFIG_FILE" 2>/dev/null
    else
        printf '%s\n' "$def"
    fi
}

ap_load_config() {
    AP_SSID="$(ap_config_get ssid mgate)"
    AP_PASSWORD="$(ap_config_get password mgate12345678)"
    AP_IF="$(ap_config_get interface ap0)"
    AP_UPSTREAM="$(ap_config_get upstream wlan0)"
    AP_IPADDR="$(ap_config_get ipaddr 10.88.0.1)"
    AP_NETMASK="$(ap_config_get netmask 255.255.255.0)"
    AP_DHCP_START="$(ap_config_get dhcp_start 10.88.0.100)"
    AP_DHCP_END="$(ap_config_get dhcp_end 10.88.0.200)"
    AP_DHCP_LEASE="$(ap_config_get dhcp_lease 12h)"
}

ap_ensure_config() {
    ensure_dirs
    if [ ! -f "$AP_CONFIG_FILE" ]; then
        ap_default_config > "$AP_CONFIG_FILE" || die "failed to write $AP_CONFIG_FILE"
        chmod 600 "$AP_CONFIG_FILE" 2>/dev/null || true
        ok "AP 配置已生成：$AP_CONFIG_FILE"
    fi
}

ap_netmask_prefix() {
    case "$1" in
        255.255.255.255) printf '32\n' ;;
        255.255.255.254) printf '31\n' ;;
        255.255.255.252) printf '30\n' ;;
        255.255.255.248) printf '29\n' ;;
        255.255.255.240) printf '28\n' ;;
        255.255.255.224) printf '27\n' ;;
        255.255.255.192) printf '26\n' ;;
        255.255.255.128) printf '25\n' ;;
        255.255.255.0) printf '24\n' ;;
        255.255.254.0) printf '23\n' ;;
        255.255.252.0) printf '22\n' ;;
        255.255.248.0) printf '21\n' ;;
        255.255.240.0) printf '20\n' ;;
        255.255.224.0) printf '19\n' ;;
        255.255.192.0) printf '18\n' ;;
        255.255.128.0) printf '17\n' ;;
        255.255.0.0) printf '16\n' ;;
        *) printf '24\n' ;;
    esac
}

interface_exists() {
    ifname="$1"
    [ -d "/sys/class/net/$ifname" ] && return 0
    have ip && ip link show dev "$ifname" >/dev/null 2>&1
}

ap_pid_running() {
    pid_file="$1"
    [ -f "$pid_file" ] || return 1
    pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" >/dev/null 2>&1
}

ap_ipv4_addr() {
    ifname="$1"
    have ip || return 0
    ip -4 addr show dev "$ifname" 2>/dev/null | awk '/inet / {print $2; exit}'
}

ap_ensure_iface_ip() {
    ifname="$1"
    ipaddr="$2"
    prefix="$3"
    if ! ip -4 addr show dev "$ifname" 2>/dev/null | grep -q "[[:space:]]$ipaddr/"; then
        ip addr add "$ipaddr/$prefix" dev "$ifname" || return 1
    fi
    return 0
}

ap_iface_is_up() {
    ifname="$1"
    have ip || return 1
    ip link show dev "$ifname" 2>/dev/null | grep -q '<[^>]*UP'
}

ap_iface_link_state() {
    ifname="$1"
    have ip || { printf 'unknown\n'; return 0; }
    line="$(ip link show dev "$ifname" 2>/dev/null | sed -n '1p')"
    if printf '%s\n' "$line" | grep -q '<[^>]*UP'; then
        printf 'up\n'
    elif [ -n "$line" ]; then
        printf 'down\n'
    else
        printf 'missing\n'
    fi
}


ap_iface_type() {
    ifname="$1"
    have iw || return 0
    iw dev "$ifname" info 2>/dev/null | awk '/^[[:space:]]*type[[:space:]]/ {print $2; exit}'
}

ap_mark_unmanaged() {
    ifname="$1"
    if have nmcli; then
        if nmcli device set "$ifname" managed no >/dev/null 2>&1; then
            info "$ifname marked unmanaged in NetworkManager"
        fi
    fi
}

ap_wait_ap_ready() {
    ifname="$1"
    pid_file="$2"
    ok_count=0
    i=0
    while [ "$i" -lt 8 ]; do
        ap_pid_running "$pid_file" || return 1
        if ap_iface_is_up "$ifname" && [ "$(ap_iface_type "$ifname")" = "AP" ]; then
            ok_count=$((ok_count + 1))
            [ "$ok_count" -ge 3 ] && return 0
        else
            ok_count=0
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

ap_is_running_healthy() {
    interface_exists "$AP_IF" || return 1
    ap_pid_running "$AP_HOSTAPD_PID_FILE" || return 1
    ap_pid_running "$AP_DNSMASQ_PID_FILE" || return 1
    ap_iface_is_up "$AP_IF" || return 1
    [ "$(ap_iface_type "$AP_IF")" = "AP" ] || return 1
    ip -4 addr show dev "$AP_IF" 2>/dev/null | grep -q "[[:space:]]$AP_IPADDR/"
}

ap_iface_mac() {
    ifname="$1"
    if [ -r "/sys/class/net/$ifname/address" ]; then
        sed -n '1p' "/sys/class/net/$ifname/address" 2>/dev/null
        return 0
    fi
    have ip || return 0
    ip link show dev "$ifname" 2>/dev/null | awk '/link\/ether/ {print $2; exit}'
}

ap_derive_mac() {
    mac="$(printf '%s' "$1" | tr 'A-F' 'a-f')"
    old_ifs="$IFS"
    IFS=:
    set -- $mac
    IFS="$old_ifs"
    [ "$#" -eq 6 ] || return 1
    for octet in "$1" "$2" "$3" "$4" "$5" "$6"; do
        case "$octet" in
            [0-9a-f][0-9a-f]) : ;;
            *) return 1 ;;
        esac
    done
    case "$1" in
        02) first="06" ;;
        06) first="0a" ;;
        0a) first="0e" ;;
        0e) first="12" ;;
        *) first="02" ;;
    esac
    printf '%s:%s:%s:%s:%s:%s\n' "$first" "$2" "$3" "$4" "$5" "$6"
}

ap_prepare_iface_mac() {
    ifname="$1"
    upstream="$2"
    ap_mac="$(ap_iface_mac "$ifname" | sed -n '1p')"
    upstream_mac="$(ap_iface_mac "$upstream" | sed -n '1p')"
    [ -n "$ap_mac" ] || return 0
    [ -n "$upstream_mac" ] || return 0
    [ "$ap_mac" = "$upstream_mac" ] || return 0

    new_mac="$(ap_derive_mac "$upstream_mac" || true)"
    [ -n "$new_mac" ] || die "failed to derive a unique MAC for $ifname from $upstream"
    ip link set "$ifname" address "$new_mac" || die "failed to set $ifname MAC address to $new_mac"
    ok "$ifname MAC set to $new_mac"
}

ap_freq_to_channel() {
    freq="$1"
    case "$freq" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$freq" -eq 2484 ] 2>/dev/null; then
        printf '14\n'
        return 0
    fi
    if [ "$freq" -ge 2412 ] 2>/dev/null && [ "$freq" -le 2472 ] 2>/dev/null; then
        printf '%s\n' $(((freq - 2407) / 5))
        return 0
    fi
    if [ "$freq" -ge 5000 ] 2>/dev/null && [ "$freq" -le 5900 ] 2>/dev/null; then
        printf '%s\n' $(((freq - 5000) / 5))
        return 0
    fi
    return 1
}

ap_upstream_channel() {
    ifname="$1"
    have iw || return 1
    ch="$(iw dev "$ifname" info 2>/dev/null | awk '/channel/ {for(i=1;i<=NF;i++){if($i=="channel"){print $(i+1); exit}}}')"
    if [ -n "$ch" ]; then
        printf '%s\n' "$ch"
        return 0
    fi
    link="$(iw dev "$ifname" link 2>/dev/null || true)"
    printf '%s\n' "$link" | grep -qi 'Not connected' && return 1
    freq="$(printf '%s\n' "$link" | awk '/freq:/ {print $2; exit}')"
    [ -n "$freq" ] || return 1
    ap_freq_to_channel "$freq"
}

ap_channel_hw_mode() {
    ch="$1"
    case "$ch" in ''|*[!0-9]*) printf 'g\n' ;; *)
        if [ "$ch" -le 14 ] 2>/dev/null; then
            printf 'g\n'
        else
            printf 'a\n'
        fi
        ;;
    esac
}

ap_validate_start_config() {
    [ "$AP_IF" = "ap0" ] || die "v0.4.0 only manages ap0; config interface=$AP_IF is not allowed"
    [ -n "$AP_SSID" ] || die "AP ssid is empty"
    pass_len="$(printf '%s' "$AP_PASSWORD" | wc -c | awk '{print $1}')"
    [ "$pass_len" -ge 8 ] 2>/dev/null && [ "$pass_len" -le 63 ] 2>/dev/null || die "AP password must be 8-63 characters"
}

ap_write_hostapd_conf() {
    channel="$1"
    hw_mode="$(ap_channel_hw_mode "$channel")"
    cat > "$AP_HOSTAPD_CONF" <<EOF_HOSTAPD
interface=$AP_IF
driver=nl80211
ssid=$AP_SSID
hw_mode=$hw_mode
channel=$channel
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF_HOSTAPD
    chmod 600 "$AP_HOSTAPD_CONF" 2>/dev/null || true
}

ap_write_dnsmasq_conf() {
    cat > "$AP_DNSMASQ_CONF" <<EOF_DNSMASQ
interface=$AP_IF
bind-interfaces
listen-address=$AP_IPADDR
port=53
resolv-file=/etc/resolv.conf
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,$AP_NETMASK,$AP_DHCP_LEASE
dhcp-option=3,$AP_IPADDR
dhcp-option=6,$AP_IPADDR
dhcp-authoritative
log-facility=$AP_DNSMASQ_LOG_FILE
EOF_DNSMASQ
    chmod 600 "$AP_DNSMASQ_CONF" 2>/dev/null || true
}

ap_remove_owned_iface() {
    [ -f "$AP_OWNER_FILE" ] || return 0
    if interface_exists "$AP_IF"; then
        have ip && ip link set "$AP_IF" down >/dev/null 2>&1 || true
        if have iw; then
            iw dev "$AP_IF" del >/dev/null 2>&1 || true
        fi
        if interface_exists "$AP_IF" && have ip; then
            ip link delete "$AP_IF" >/dev/null 2>&1 || true
        fi
        if interface_exists "$AP_IF"; then
            warn "$AP_IF still exists after cleanup; remove it manually if needed"
        else
            ok "$AP_IF removed"
        fi
    fi
    rm -f "$AP_OWNER_FILE" 2>/dev/null || true
}

ap_cleanup_owned_state() {
    ap_stop_pid "$AP_DNSMASQ_PID_FILE" "dnsmasq"
    ap_stop_pid "$AP_HOSTAPD_PID_FILE" "hostapd"
    ap_remove_owned_iface
}

ap_stop_pid() {
    pid_file="$1"
    label="$2"
    if ap_pid_running "$pid_file"; then
        pid="$(sed -n '1p' "$pid_file" 2>/dev/null || true)"
        kill "$pid" >/dev/null 2>&1 || true
        i=0
        while kill -0 "$pid" >/dev/null 2>&1; do
            i=$((i + 1))
            [ "$i" -ge 8 ] && break
            sleep 1
        done
        kill -0 "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
        ok "$label stopped"
    else
        info "$label not running"
    fi
    rm -f "$pid_file" 2>/dev/null || true
}

ap_cmd_path() {
    command -v "$1" 2>/dev/null || true
}

ap_check_command() {
    cmd="$1"
    desc="$2"
    path="$(ap_cmd_path "$cmd")"
    if [ -n "$path" ]; then
        ok "$cmd: $path"
        return 0
    fi
    missing "$cmd: $desc"
    return 1
}

ap_manual_install_hint() {
    info "suggested command: apt-get update && apt-get install -y $AP_DEP_PACKAGES"
}

ap_run_check() {
    ap_load_config
    AP_CHECK_MISSING_DEPS=0
    AP_CHECK_WIRELESS_READY=1

    info "checking AP dependencies..."
    ap_check_command ip "required to configure ap0 IP address" || AP_CHECK_MISSING_DEPS=1
    ap_check_command iw "required to create ap0 and detect wlan channel" || AP_CHECK_MISSING_DEPS=1
    ap_check_command hostapd "required to create WiFi AP" || AP_CHECK_MISSING_DEPS=1
    ap_check_command dnsmasq "required to provide DHCP and DNS for AP clients" || AP_CHECK_MISSING_DEPS=1

    info "checking wireless upstream..."
    if interface_exists "$AP_UPSTREAM"; then
        ok "$AP_UPSTREAM exists"
    else
        missing "$AP_UPSTREAM: wireless upstream interface not found"
        AP_CHECK_WIRELESS_READY=0
    fi

    ch="$(ap_upstream_channel "$AP_UPSTREAM" 2>/dev/null || true)"
    if [ -n "$ch" ]; then
        ok "$AP_UPSTREAM channel: $ch"
        AP_CHECK_CHANNEL="$ch"
    else
        warn "$AP_UPSTREAM channel: unknown"
        AP_CHECK_CHANNEL=""
        AP_CHECK_WIRELESS_READY=0
    fi

    if [ "$AP_CHECK_MISSING_DEPS" = "1" ]; then
        warn "AP dependencies are incomplete"
        ap_manual_install_hint
    fi
    if [ "$AP_CHECK_WIRELESS_READY" != "1" ]; then
        warn "AP wireless upstream is not ready"
    fi

    [ "$AP_CHECK_MISSING_DEPS" = "0" ] && [ "$AP_CHECK_WIRELESS_READY" = "1" ]
}

cmd_ap_check() {
    ap_run_check
}

ap_is_interactive() {
    [ -t 0 ] && [ -t 1 ]
}

ap_confirm_install() {
    printf 'Install AP dependencies now? [y/N] '
    read -r ans || ans=""
    case "$ans" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

ap_install_deps_run() {
    if have apt-get; then
        apt_cmd="apt-get"
    elif have apt; then
        apt_cmd="apt"
    else
        err "apt-get or apt is required to install AP dependencies automatically"
        ap_manual_install_hint
        return 1
    fi

    info "AP dependency packages: $AP_DEP_PACKAGES"
    info "hostapd: create AP"
    info "dnsmasq: DHCP and DNS forwarding for AP clients"
    info "iw: wireless interface/channel control"
    info "iproute2: ip command"

    if ! ap_is_interactive; then
        warn "non-interactive terminal; refusing to install without confirmation"
        ap_manual_install_hint
        return 1
    fi

    if ! ap_confirm_install; then
        info "installation cancelled"
        hint "run mgate ap-install-deps when ready"
        return 1
    fi

    step "installing AP dependencies with $apt_cmd"
    if ! "$apt_cmd" update; then
        err "failed to run $apt_cmd update"
        ap_manual_install_hint
        return 1
    fi
    if ! "$apt_cmd" install -y $AP_DEP_PACKAGES; then
        err "failed to install AP dependencies"
        ap_manual_install_hint
        return 1
    fi

    info "mgate uses its own isolated hostapd/dnsmasq instances under /opt/mgate/run/ap"
    if have systemctl; then
        info "stopping system hostapd service to avoid port/interface conflicts"
        systemctl stop hostapd >/dev/null 2>&1 || true
        info "disabling system hostapd service; mgate starts its own instance when needed"
        systemctl disable hostapd >/dev/null 2>&1 || true
        info "stopping system dnsmasq service to avoid DHCP conflicts on ap0"
        systemctl stop dnsmasq >/dev/null 2>&1 || true
        info "disabling system dnsmasq service; mgate starts its own instance when needed"
        systemctl disable dnsmasq >/dev/null 2>&1 || true
    else
        info "systemctl not found; skipping system hostapd/dnsmasq service disable"
    fi

    ap_run_check
}

cmd_ap_install_deps() {
    need_root
    ap_install_deps_run
}

ap_preflight_for_start() {
    if ap_run_check; then
        return 0
    fi

    if [ "$AP_CHECK_MISSING_DEPS" = "1" ]; then
        if ! ap_is_interactive; then
            die "missing AP dependencies; run mgate ap-install-deps first"
        fi
        hint "run mgate ap-install-deps to install AP dependencies"
        uid="$(id -u 2>/dev/null || echo 1)"
        if [ "$uid" != "0" ]; then
            die "missing AP dependencies; run mgate ap-install-deps first as root"
        fi
        if ap_install_deps_run; then
            ap_run_check || die "AP environment is still not ready after dependency installation"
            return 0
        fi
        die "missing AP dependencies; run mgate ap-install-deps first"
    fi

    die "AP environment is not ready; check $AP_UPSTREAM connection and channel"
}
cmd_ap_config() {
    ap_ensure_config
    ap_load_config
    info "ap config path: $AP_CONFIG_FILE"
    cat "$AP_CONFIG_FILE"
}

cmd_ap_status() {
    ap_load_config
    info "ap config path: $AP_CONFIG_FILE"
    [ -f "$AP_CONFIG_FILE" ] && info "ap config exists: yes" || info "ap config exists: no"
    if interface_exists "$AP_IF"; then
        info "$AP_IF exists: yes"
        info "$AP_IF link: $(ap_iface_link_state "$AP_IF")"
        ap_type="$(ap_iface_type "$AP_IF" || true)"
        [ -n "$ap_type" ] || ap_type="unknown"
        info "$AP_IF type: $ap_type"
        ip4="$(ap_ipv4_addr "$AP_IF" || true)"
        [ -n "$ip4" ] || ip4="none"
        info "$AP_IF ip: $ip4"
    else
        info "$AP_IF exists: no"
        info "$AP_IF ip: none"
    fi
    if interface_exists "$AP_UPSTREAM"; then
        info "$AP_UPSTREAM exists: yes"
    else
        info "$AP_UPSTREAM exists: no"
    fi
    ch="$(ap_upstream_channel "$AP_UPSTREAM" 2>/dev/null || true)"
    [ -n "$ch" ] || ch="unknown"
    info "$AP_UPSTREAM channel: $ch"
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && info "hostapd running: yes" || info "hostapd running: no"
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && info "dnsmasq running: yes" || info "dnsmasq running: no"
    info "ssid: $AP_SSID"
    info "dhcp range: $AP_DHCP_START - $AP_DHCP_END ($AP_DHCP_LEASE)"
}

cmd_ap_start() {
    ap_ensure_config
    ap_load_config
    ap_validate_start_config
    ap_preflight_for_start
    need_root
    ensure_ap_dirs
    channel="$AP_CHECK_CHANNEL"

    if ap_is_running_healthy; then
        ok "AP already running on $AP_IF ($AP_IPADDR), ssid=$AP_SSID"
        return 0
    fi

    if [ -f "$AP_OWNER_FILE" ] || ap_pid_running "$AP_HOSTAPD_PID_FILE" || ap_pid_running "$AP_DNSMASQ_PID_FILE"; then
        warn "existing mgate AP state is not healthy; restarting AP"
        interface_exists "$AP_IF" && printf '%s\n' "$AP_IF" > "$AP_OWNER_FILE" 2>/dev/null || true
        ap_cleanup_owned_state
    fi

    if interface_exists "$AP_IF"; then
        die "$AP_IF already exists but is not marked as mgate-managed; refusing to take over"
    else
        iw dev "$AP_UPSTREAM" interface add "$AP_IF" type __ap 2>/dev/null || \
            iw dev "$AP_UPSTREAM" interface add "$AP_IF" type ap || die "failed to create $AP_IF from $AP_UPSTREAM"
        printf '%s\n' "$AP_IF" > "$AP_OWNER_FILE" 2>/dev/null || true
    fi

    ap_mark_unmanaged "$AP_IF"
    if ! ap_pid_running "$AP_HOSTAPD_PID_FILE"; then
        ap_prepare_iface_mac "$AP_IF" "$AP_UPSTREAM"
    fi

    prefix="$(ap_netmask_prefix "$AP_NETMASK")"
    if ! ap_ensure_iface_ip "$AP_IF" "$AP_IPADDR" "$prefix"; then
        ap_cleanup_owned_state
        die "failed to assign $AP_IPADDR/$prefix to $AP_IF"
    fi

    ap_write_hostapd_conf "$channel"
    ap_write_dnsmasq_conf

    hostapd_started=0
    if ap_pid_running "$AP_HOSTAPD_PID_FILE"; then
        info "hostapd already running: $(sed -n '1p' "$AP_HOSTAPD_PID_FILE")"
    else
        nohup hostapd "$AP_HOSTAPD_CONF" >> "$AP_HOSTAPD_LOG_FILE" 2>&1 &
        echo $! > "$AP_HOSTAPD_PID_FILE"
        sleep 1
        if ! ap_pid_running "$AP_HOSTAPD_PID_FILE"; then
            rm -f "$AP_HOSTAPD_PID_FILE" 2>/dev/null || true
            ap_cleanup_owned_state
            die "hostapd failed to start; see $AP_HOSTAPD_LOG_FILE"
        fi
        hostapd_started=1
        ok "hostapd started: $(cat "$AP_HOSTAPD_PID_FILE")"
    fi

    if ! ap_wait_ap_ready "$AP_IF" "$AP_HOSTAPD_PID_FILE"; then
        ap_type="$(ap_iface_type "$AP_IF" || true)"
        [ -n "$ap_type" ] || ap_type="unknown"
        ap_cleanup_owned_state
        die "$AP_IF is not stable in AP mode (type=$ap_type); see $AP_HOSTAPD_LOG_FILE"
    fi
    ok "$AP_IF link is up"
    ok "$AP_IF type is AP"
    if ! ap_ensure_iface_ip "$AP_IF" "$AP_IPADDR" "$prefix"; then
        ap_cleanup_owned_state
        die "failed to assign $AP_IPADDR/$prefix to $AP_IF after hostapd start"
    fi

    if ap_pid_running "$AP_DNSMASQ_PID_FILE"; then
        info "dnsmasq already running: $(sed -n '1p' "$AP_DNSMASQ_PID_FILE")"
    else
        if ! dnsmasq -C "$AP_DNSMASQ_CONF" -x "$AP_DNSMASQ_PID_FILE" >> "$AP_DNSMASQ_LOG_FILE" 2>&1; then
            ap_cleanup_owned_state
            die "dnsmasq failed to start; see $AP_DNSMASQ_LOG_FILE"
        fi
        sleep 1
        if ! ap_pid_running "$AP_DNSMASQ_PID_FILE"; then
            rm -f "$AP_DNSMASQ_PID_FILE" 2>/dev/null || true
            ap_cleanup_owned_state
            die "dnsmasq failed to stay running; see $AP_DNSMASQ_LOG_FILE"
        fi
        ok "dnsmasq started: $(cat "$AP_DNSMASQ_PID_FILE")"
    fi

    ok "AP started on $AP_IF ($AP_IPADDR/$prefix), ssid=$AP_SSID, channel=$channel"
    warn "AP mode provides WiFi, DHCP, and DNS forwarding only; no NAT, forwarding, TProxy, or gateway rules were enabled"
}

cmd_ap_stop() {
    need_root
    ap_load_config
    [ "$AP_IF" = "ap0" ] || die "v0.4.0 only manages ap0; config interface=$AP_IF is not allowed"
    owned=0
    [ -f "$AP_OWNER_FILE" ] && owned=1
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && owned=1
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && owned=1
    ap_stop_pid "$AP_DNSMASQ_PID_FILE" "dnsmasq"
    ap_stop_pid "$AP_HOSTAPD_PID_FILE" "hostapd"
    if interface_exists "$AP_IF"; then
        if [ "$owned" = "1" ]; then
            have ip && ip link set "$AP_IF" down >/dev/null 2>&1 || true
            if have iw; then
                iw dev "$AP_IF" del >/dev/null 2>&1 || true
            fi
            if interface_exists "$AP_IF" && have ip; then
                ip link delete "$AP_IF" >/dev/null 2>&1 || true
            fi
            if interface_exists "$AP_IF"; then
                warn "$AP_IF still exists; remove it manually if needed"
            else
                ok "$AP_IF removed"
            fi
        else
            warn "$AP_IF exists but is not marked as mgate-managed; not deleting it"
        fi
    else
        info "$AP_IF does not exist"
    fi
    rm -f "$AP_OWNER_FILE" 2>/dev/null || true
}

# -----------------------------
# NAT gateway: ap0 -> upstream only, no TProxy/mangle
# -----------------------------
gateway_subnet() {
    prefix="$(ap_netmask_prefix "$AP_NETMASK")"
    printf '%s/%s\n' "$AP_IPADDR" "$prefix"
}

gateway_have_iptables() {
    have iptables
}

gateway_ip_forward_value() {
    if [ -r /proc/sys/net/ipv4/ip_forward ]; then
        sed -n '1p' /proc/sys/net/ipv4/ip_forward 2>/dev/null
    else
        printf 'unknown\n'
    fi
}

gateway_rules_active() {
    gateway_have_iptables || return 1
    iptables -t nat -S "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1 || return 1
    iptables -S "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t nat -C POSTROUTING -j "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1 || return 1
    iptables -C FORWARD -j "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1
}

gateway_check_env() {
    ap_load_config
    missing_count=0
    info "checking NAT gateway dependencies..."
    if have ip; then ok "ip: $(command -v ip 2>/dev/null)"; else missing "ip: required to inspect interfaces"; missing_count=1; fi
    if gateway_have_iptables; then ok "iptables: $(command -v iptables 2>/dev/null)"; else missing "iptables: required for NAT gateway rules"; missing_count=1; fi
    if [ -r /proc/sys/net/ipv4/ip_forward ]; then ok "ipv4 forwarding control: /proc/sys/net/ipv4/ip_forward"; else missing "ipv4 forwarding control: /proc/sys/net/ipv4/ip_forward not available"; missing_count=1; fi

    info "checking gateway interfaces..."
    if interface_exists "$AP_IF"; then
        ok "$AP_IF exists"
        ap_type="$(ap_iface_type "$AP_IF" || true)"
        [ -n "$ap_type" ] || ap_type="unknown"
        info "$AP_IF type: $ap_type"
        [ "$ap_type" = "AP" ] || { warn "$AP_IF is not in AP mode"; missing_count=1; }
        ap_link="$(ap_iface_link_state "$AP_IF")"
        info "$AP_IF link: $ap_link"
        [ "$ap_link" = "up" ] || { warn "$AP_IF link is not up"; missing_count=1; }
        ap_ip="$(ap_ipv4_addr "$AP_IF" || true)"
        [ -n "$ap_ip" ] || ap_ip="none"
        info "$AP_IF ip: $ap_ip"
        [ "$ap_ip" != "none" ] || { warn "$AP_IF has no IPv4 address"; missing_count=1; }
    else
        missing "$AP_IF: AP interface not found; run mgate ap-start first"
        missing_count=1
    fi
    if interface_exists "$AP_UPSTREAM"; then
        ok "$AP_UPSTREAM exists"
    else
        missing "$AP_UPSTREAM: upstream interface not found"
        missing_count=1
    fi

    [ "$missing_count" = "0" ]
}

cmd_gateway_check() {
    gateway_check_env
}

gateway_enable_ip_forward() {
    ensure_gateway_dirs
    [ -w /proc/sys/net/ipv4/ip_forward ] || die "cannot write /proc/sys/net/ipv4/ip_forward"
    if [ ! -f "$GATEWAY_IP_FORWARD_PREV" ]; then
        gateway_ip_forward_value > "$GATEWAY_IP_FORWARD_PREV" 2>/dev/null || true
    fi
    echo 1 > /proc/sys/net/ipv4/ip_forward || die "failed to enable IPv4 forwarding"
    ok "IPv4 forwarding enabled"
}

gateway_restore_ip_forward() {
    [ -w /proc/sys/net/ipv4/ip_forward ] || return 0
    if [ -f "$GATEWAY_IP_FORWARD_PREV" ]; then
        prev="$(sed -n '1p' "$GATEWAY_IP_FORWARD_PREV" 2>/dev/null || true)"
        case "$prev" in
            0|1)
                echo "$prev" > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
                info "IPv4 forwarding restored to $prev"
                ;;
            *) warn "previous IPv4 forwarding state is unknown; leaving current value" ;;
        esac
        rm -f "$GATEWAY_IP_FORWARD_PREV" 2>/dev/null || true
    else
        info "no saved IPv4 forwarding state; leaving current value: $(gateway_ip_forward_value)"
    fi
}

gateway_iptables_delete_jump_all() {
    table="$1"
    chain="$2"
    target="$3"
    while iptables -t "$table" -D "$chain" -j "$target" >/dev/null 2>&1; do
        :
    done
}

gateway_iptables_remove() {
    gateway_have_iptables || return 0
    gateway_iptables_delete_jump_all nat POSTROUTING "$GATEWAY_NAT_CHAIN"
    iptables -t nat -F "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -X "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1 || true

    gateway_iptables_delete_jump_all filter FORWARD "$GATEWAY_FORWARD_CHAIN"
    iptables -F "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1 || true
    iptables -X "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1 || true
    rm -f "$GATEWAY_BACKEND_FILE" 2>/dev/null || true
}

gateway_iptables_apply() {
    gateway_have_iptables || { err "iptables is required for NAT gateway"; return 1; }
    subnet="$(gateway_subnet)"

    gateway_iptables_remove

    iptables -t nat -N "$GATEWAY_NAT_CHAIN" || return 1
    iptables -t nat -A "$GATEWAY_NAT_CHAIN" -s "$subnet" -o "$AP_UPSTREAM" -j MASQUERADE || return 1
    iptables -t nat -I POSTROUTING 1 -j "$GATEWAY_NAT_CHAIN" || return 1

    iptables -N "$GATEWAY_FORWARD_CHAIN" || return 1
    iptables -A "$GATEWAY_FORWARD_CHAIN" -i "$AP_IF" -o "$AP_UPSTREAM" -s "$subnet" -j ACCEPT || return 1
    if iptables -A "$GATEWAY_FORWARD_CHAIN" -i "$AP_UPSTREAM" -o "$AP_IF" -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        :
    elif iptables -A "$GATEWAY_FORWARD_CHAIN" -i "$AP_UPSTREAM" -o "$AP_IF" -d "$subnet" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        :
    else
        err "iptables conntrack/state match is required for safe return forwarding"
        gateway_iptables_remove
        return 1
    fi
    iptables -I FORWARD 1 -j "$GATEWAY_FORWARD_CHAIN" || return 1
    printf 'iptables\n' > "$GATEWAY_BACKEND_FILE" 2>/dev/null || true
    ok "iptables NAT gateway rules installed"
}

cmd_gateway_start() {
    need_root
    ap_ensure_config
    ap_load_config
    ap_validate_start_config
    gateway_check_env || die "NAT gateway environment is not ready"
    ap_is_running_healthy || die "AP is not healthy; run mgate ap-start first"
    gateway_enable_ip_forward
    if ! gateway_iptables_apply; then
        gateway_iptables_remove
        gateway_restore_ip_forward
        die "failed to install NAT gateway rules"
    fi
    ok "NAT gateway started: $AP_IF -> $AP_UPSTREAM"
    warn "NAT gateway only enables regular IPv4 forwarding; no TProxy, mangle, or transparent proxy rules were enabled"
}

cmd_gateway_stop() {
    need_root
    ap_load_config
    gateway_iptables_remove
    ok "NAT gateway rules removed"
    gateway_restore_ip_forward
}

gateway_transparent_proxy_state() {
    tproxy_port="$(tproxy_mihomo_port || true)"
    [ -n "$tproxy_port" ] || tproxy_port="none"
    tproxy_enabled_state "$(tproxy_state_mangle)" "$(tproxy_state_ip_rule)" "$(tproxy_state_route_table)" "$tproxy_port"
}
cmd_gateway_status() {
    ap_load_config
    info "gateway mode: nat"
    info "transparent proxy: $(gateway_transparent_proxy_state)"
    info "ap interface: $AP_IF"
    info "upstream interface: $AP_UPSTREAM"
    info "subnet: $(gateway_subnet)"
    info "ipv4 forwarding: $(gateway_ip_forward_value)"
    if gateway_rules_active; then
        info "nat rules active: yes"
        info "backend: iptables"
    else
        info "nat rules active: no"
        if gateway_have_iptables; then
            info "backend: iptables available"
        else
            warn "backend: iptables missing"
        fi
    fi
    if ap_is_running_healthy; then
        info "ap healthy: yes"
    else
        warn "ap healthy: no"
    fi
}

debug_section() {
    say ""
    say "[$1]"
}

debug_info() { say "[INFO] $*"; }
debug_ok() { say "[OK] $*"; }
debug_warn() { say "[WARN] $*"; }

debug_iptables_chain() {
    table="$1"
    chain="$2"
    if ! gateway_have_iptables; then
        debug_warn "iptables missing; cannot show $chain"
        return 0
    fi
    if iptables -t "$table" -S "$chain" >/dev/null 2>&1; then
        iptables -t "$table" -S "$chain" 2>&1
    else
        debug_warn "$chain not found in $table table"
    fi
}

gateway_debug_iptables() {
    if ! gateway_have_iptables; then
        debug_warn "iptables missing"
        return 0
    fi

    if iptables -t nat -C POSTROUTING -j "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1; then
        debug_ok "POSTROUTING jump to $GATEWAY_NAT_CHAIN: yes"
    else
        debug_warn "POSTROUTING jump to $GATEWAY_NAT_CHAIN: no"
    fi
    if iptables -C FORWARD -j "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1; then
        debug_ok "FORWARD jump to $GATEWAY_FORWARD_CHAIN: yes"
    else
        debug_warn "FORWARD jump to $GATEWAY_FORWARD_CHAIN: no"
    fi

    say ""
    say "nat chain $GATEWAY_NAT_CHAIN:"
    debug_iptables_chain nat "$GATEWAY_NAT_CHAIN"
    say ""
    say "filter chain $GATEWAY_FORWARD_CHAIN:"
    debug_iptables_chain filter "$GATEWAY_FORWARD_CHAIN"
    say ""
    say "entry jumps:"
    iptables -t nat -S POSTROUTING 2>/dev/null | grep "$GATEWAY_NAT_CHAIN" || debug_warn "no POSTROUTING entry jump found"
    iptables -S FORWARD 2>/dev/null | grep "$GATEWAY_FORWARD_CHAIN" || debug_warn "no FORWARD entry jump found"
}

gateway_debug_dnsmasq_log() {
    if [ ! -s "$AP_DNSMASQ_LOG_FILE" ]; then
        debug_warn "dnsmasq log not found or empty: $AP_DNSMASQ_LOG_FILE"
        return 0
    fi
    if have tail; then
        dhcp_lines="$(tail -80 "$AP_DNSMASQ_LOG_FILE" 2>/dev/null | grep 'dnsmasq-dhcp' | tail -30 2>/dev/null || true)"
        if [ -n "$dhcp_lines" ]; then
            printf '%s\n' "$dhcp_lines"
        else
            debug_warn "no dnsmasq-dhcp entries in recent log"
        fi
    else
        sed -n '$p' "$AP_DNSMASQ_LOG_FILE" 2>/dev/null || true
    fi
}

gateway_debug_dns_hint() {
    debug_info "AP clients should receive DNS server: $AP_IPADDR"
    if [ -f "$AP_DNSMASQ_CONF" ]; then
        dns_opt="$(sed -n 's/^dhcp-option=6,//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ -n "$dns_opt" ] && debug_info "dnsmasq DHCP DNS option: $dns_opt" || debug_warn "dnsmasq DHCP DNS option not found"
        listen_addr="$(sed -n 's/^listen-address=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ -n "$listen_addr" ] && debug_info "dnsmasq listen address: $listen_addr" || debug_warn "dnsmasq listen address not found"
        dns_port="$(sed -n 's/^port=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        if [ -z "$dns_port" ]; then
            debug_info "dnsmasq DNS forwarding: enabled on default port 53"
        elif [ "$dns_port" = "0" ]; then
            debug_warn "dnsmasq DNS forwarding: disabled (port=0)"
        else
            debug_info "dnsmasq DNS forwarding: enabled on port $dns_port"
        fi
        resolv_file="$(sed -n 's/^resolv-file=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ -n "$resolv_file" ] || resolv_file="/etc/resolv.conf"
        debug_info "dnsmasq upstream DNS source: $resolv_file"
        static_servers="$(sed -n 's/^server=//p' "$AP_DNSMASQ_CONF" 2>/dev/null || true)"
        if [ -n "$static_servers" ]; then
            say "dnsmasq static upstream DNS:"
            printf '%s\n' "$static_servers"
        fi
    else
        debug_warn "dnsmasq config not found: $AP_DNSMASQ_CONF"
    fi
    if [ -r /etc/resolv.conf ]; then
        say "resolv.conf nameservers:"
        grep '^nameserver[[:space:]]' /etc/resolv.conf 2>/dev/null || debug_warn "no nameserver entries in /etc/resolv.conf"
    else
        debug_warn "/etc/resolv.conf not readable"
    fi
}

cmd_gateway_debug() {
    ap_load_config
    debug_section "summary"
    debug_info "mgate version: $MGATE_VERSION"
    debug_info "workdir: $WORKDIR"
    debug_info "gateway mode: nat"
    debug_info "transparent proxy: $(gateway_transparent_proxy_state)"
    debug_info "ap interface: $AP_IF"
    debug_info "upstream interface: $AP_UPSTREAM"
    debug_info "subnet: $(gateway_subnet)"

    debug_section "ip forward"
    debug_info "ipv4 forwarding: $(gateway_ip_forward_value)"
    if [ -f "$GATEWAY_IP_FORWARD_PREV" ]; then
        debug_info "saved previous ip_forward: $(sed -n '1p' "$GATEWAY_IP_FORWARD_PREV" 2>/dev/null || echo unknown)"
    else
        debug_info "saved previous ip_forward: none"
    fi

    debug_section "AP health"
    if interface_exists "$AP_IF"; then
        debug_info "$AP_IF exists: yes"
        debug_info "$AP_IF link: $(ap_iface_link_state "$AP_IF")"
        ap_type="$(ap_iface_type "$AP_IF" || true)"
        [ -n "$ap_type" ] || ap_type="unknown"
        debug_info "$AP_IF type: $ap_type"
        ap_ip="$(ap_ipv4_addr "$AP_IF" || true)"
        [ -n "$ap_ip" ] || ap_ip="none"
        debug_info "$AP_IF ip: $ap_ip"
    else
        debug_warn "$AP_IF exists: no"
    fi
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && debug_info "hostapd running: yes ($(sed -n '1p' "$AP_HOSTAPD_PID_FILE" 2>/dev/null))" || debug_warn "hostapd running: no"
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && debug_info "dnsmasq running: yes ($(sed -n '1p' "$AP_DNSMASQ_PID_FILE" 2>/dev/null))" || debug_warn "dnsmasq running: no"
    if ap_is_running_healthy; then debug_ok "AP healthy: yes"; else debug_warn "AP healthy: no"; fi

    debug_section "upstream"
    if interface_exists "$AP_UPSTREAM"; then
        debug_info "$AP_UPSTREAM exists: yes"
        up_ip="$(ap_ipv4_addr "$AP_UPSTREAM" || true)"
        [ -n "$up_ip" ] || up_ip="none"
        debug_info "$AP_UPSTREAM ip: $up_ip"
        if have ip; then
            say "default route:"
            ip route show default 2>/dev/null || debug_warn "failed to read default route"
            say "routes via $AP_UPSTREAM:"
            ip route show dev "$AP_UPSTREAM" 2>/dev/null || debug_warn "failed to read routes for $AP_UPSTREAM"
        fi
    else
        debug_warn "$AP_UPSTREAM exists: no"
    fi

    debug_section "iptables"
    if gateway_rules_active; then
        debug_ok "NAT rules active: yes"
    else
        debug_warn "NAT rules active: no"
    fi
    gateway_debug_iptables

    debug_section "dnsmasq DHCP log"
    gateway_debug_dnsmasq_log

    debug_section "DNS hints"
    gateway_debug_dns_hint
}

gateway_doctor_section() {
    say ""
    say "[$1]"
}

gateway_doctor_ok() {
    say "[OK] $*"
    GATEWAY_DOCTOR_OK=$((GATEWAY_DOCTOR_OK + 1))
}

gateway_doctor_warn() {
    say "[WARN] $*"
    GATEWAY_DOCTOR_WARN=$((GATEWAY_DOCTOR_WARN + 1))
}

gateway_doctor_fail() {
    say "[ERROR] $*"
    GATEWAY_DOCTOR_FAIL=$((GATEWAY_DOCTOR_FAIL + 1))
}

gateway_doctor_recent_dhcp_ack() {
    [ -s "$AP_DNSMASQ_LOG_FILE" ] || return 1
    if have tail; then
        tail -120 "$AP_DNSMASQ_LOG_FILE" 2>/dev/null | grep -q "DHCPACK($AP_IF)"
    else
        grep -q "DHCPACK($AP_IF)" "$AP_DNSMASQ_LOG_FILE" 2>/dev/null
    fi
}

gateway_doctor_chain_counters() {
    gateway_have_iptables || return 0
    say "iptables counters snapshot:"
    if iptables -t nat -L "$GATEWAY_NAT_CHAIN" -v -n -x >/dev/null 2>&1; then
        iptables -t nat -L "$GATEWAY_NAT_CHAIN" -v -n -x 2>/dev/null | sed -n '1,5p'
    else
        gateway_doctor_warn "cannot read NAT chain counters: $GATEWAY_NAT_CHAIN"
    fi
    if iptables -L "$GATEWAY_FORWARD_CHAIN" -v -n -x >/dev/null 2>&1; then
        iptables -L "$GATEWAY_FORWARD_CHAIN" -v -n -x 2>/dev/null | sed -n '1,7p'
    else
        gateway_doctor_warn "cannot read FORWARD chain counters: $GATEWAY_FORWARD_CHAIN"
    fi
}

cmd_gateway_doctor() {
    ap_load_config
    GATEWAY_DOCTOR_OK=0
    GATEWAY_DOCTOR_WARN=0
    GATEWAY_DOCTOR_FAIL=0

    gateway_doctor_section "summary"
    say "[INFO] mgate version: $MGATE_VERSION"
    say "[INFO] gateway mode: nat"
    say "[INFO] transparent proxy: $(gateway_transparent_proxy_state)"
    say "[INFO] ap interface: $AP_IF"
    say "[INFO] upstream interface: $AP_UPSTREAM"
    say "[INFO] subnet: $(gateway_subnet)"
    uid="$(id -u 2>/dev/null || echo 1)"
    if [ "$uid" = "0" ]; then
        gateway_doctor_ok "running as root; iptables diagnostics should be complete"
    else
        gateway_doctor_warn "not running as root; iptables diagnostics may be incomplete"
    fi

    gateway_doctor_section "AP baseline"
    if [ -f "$AP_CONFIG_FILE" ]; then
        gateway_doctor_ok "AP config exists: $AP_CONFIG_FILE"
    else
        gateway_doctor_warn "AP config missing; run mgate ap-config to create it"
    fi
    if interface_exists "$AP_IF"; then
        gateway_doctor_ok "$AP_IF exists"
        ap_link="$(ap_iface_link_state "$AP_IF")"
        [ "$ap_link" = "up" ] && gateway_doctor_ok "$AP_IF link is up" || gateway_doctor_fail "$AP_IF link is $ap_link"
        ap_type="$(ap_iface_type "$AP_IF" || true)"
        [ -n "$ap_type" ] || ap_type="unknown"
        [ "$ap_type" = "AP" ] && gateway_doctor_ok "$AP_IF type is AP" || gateway_doctor_fail "$AP_IF type is $ap_type"
        ap_ip="$(ap_ipv4_addr "$AP_IF" || true)"
        [ -n "$ap_ip" ] || ap_ip="none"
        case "$ap_ip" in
            "$AP_IPADDR"/*) gateway_doctor_ok "$AP_IF ip: $ap_ip" ;;
            none) gateway_doctor_fail "$AP_IF has no IPv4 address" ;;
            *) gateway_doctor_warn "$AP_IF ip differs from config: $ap_ip expected $AP_IPADDR" ;;
        esac
    else
        gateway_doctor_fail "$AP_IF does not exist; run mgate ap-start first"
    fi
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && gateway_doctor_ok "hostapd running: $(sed -n '1p' "$AP_HOSTAPD_PID_FILE" 2>/dev/null)" || gateway_doctor_fail "hostapd is not running"
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && gateway_doctor_ok "dnsmasq running: $(sed -n '1p' "$AP_DNSMASQ_PID_FILE" 2>/dev/null)" || gateway_doctor_fail "dnsmasq is not running"
    ap_is_running_healthy && gateway_doctor_ok "AP health check passed" || gateway_doctor_fail "AP health check failed"

    gateway_doctor_section "upstream"
    if interface_exists "$AP_UPSTREAM"; then
        gateway_doctor_ok "$AP_UPSTREAM exists"
        up_ip="$(ap_ipv4_addr "$AP_UPSTREAM" || true)"
        [ -n "$up_ip" ] && gateway_doctor_ok "$AP_UPSTREAM ip: $up_ip" || gateway_doctor_fail "$AP_UPSTREAM has no IPv4 address"
        if have ip; then
            if ip route show default 2>/dev/null | grep -q "dev $AP_UPSTREAM"; then
                gateway_doctor_ok "default route uses $AP_UPSTREAM"
            else
                gateway_doctor_fail "default route does not use $AP_UPSTREAM"
                ip route show default 2>/dev/null | sed 's/^/[INFO] default route: /'
            fi
        else
            gateway_doctor_fail "ip command missing; cannot inspect routes"
        fi
    else
        gateway_doctor_fail "$AP_UPSTREAM does not exist"
    fi

    gateway_doctor_section "NAT baseline"
    ip_forward="$(gateway_ip_forward_value)"
    [ "$ip_forward" = "1" ] && gateway_doctor_ok "IPv4 forwarding enabled" || gateway_doctor_fail "IPv4 forwarding is $ip_forward"
    if gateway_have_iptables; then
        gateway_doctor_ok "iptables available: $(command -v iptables 2>/dev/null)"
        if gateway_rules_active; then
            gateway_doctor_ok "mgate NAT rules are active"
        else
            gateway_doctor_fail "mgate NAT rules are not active; run mgate gateway-start"
        fi
        subnet="$(gateway_subnet)"
        if iptables -t nat -C "$GATEWAY_NAT_CHAIN" -s "$subnet" -o "$AP_UPSTREAM" -j MASQUERADE >/dev/null 2>&1; then
            gateway_doctor_ok "MASQUERADE rule matches $subnet -> $AP_UPSTREAM"
        else
            gateway_doctor_warn "MASQUERADE rule detail did not match expected $subnet -> $AP_UPSTREAM"
        fi
        if iptables -C "$GATEWAY_FORWARD_CHAIN" -i "$AP_IF" -o "$AP_UPSTREAM" -s "$subnet" -j ACCEPT >/dev/null 2>&1; then
            gateway_doctor_ok "forward rule allows $AP_IF -> $AP_UPSTREAM"
        else
            gateway_doctor_warn "forward rule for $AP_IF -> $AP_UPSTREAM not found"
        fi
        if iptables -C "$GATEWAY_FORWARD_CHAIN" -i "$AP_UPSTREAM" -o "$AP_IF" -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1 || \
           iptables -C "$GATEWAY_FORWARD_CHAIN" -i "$AP_UPSTREAM" -o "$AP_IF" -d "$subnet" -m state --state RELATED,ESTABLISHED -j ACCEPT >/dev/null 2>&1; then
            gateway_doctor_ok "return traffic rule allows established flows"
        else
            gateway_doctor_warn "return traffic rule not found"
        fi
    else
        gateway_doctor_fail "iptables missing"
    fi

    gateway_doctor_section "DHCP and DNS"
    if [ -f "$AP_DNSMASQ_CONF" ]; then
        gateway_doctor_ok "dnsmasq config exists: $AP_DNSMASQ_CONF"
        dns_opt="$(sed -n 's/^dhcp-option=6,//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ "$dns_opt" = "$AP_IPADDR" ] && gateway_doctor_ok "DHCP DNS option points to $AP_IPADDR" || gateway_doctor_fail "DHCP DNS option is ${dns_opt:-missing}, expected $AP_IPADDR"
        listen_addr="$(sed -n 's/^listen-address=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ "$listen_addr" = "$AP_IPADDR" ] && gateway_doctor_ok "dnsmasq listens on $AP_IPADDR" || gateway_doctor_warn "dnsmasq listen address is ${listen_addr:-missing}"
        dns_port="$(sed -n 's/^port=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        case "$dns_port" in
            ""|53) gateway_doctor_ok "dnsmasq DNS forwarding enabled on port ${dns_port:-53}" ;;
            0) gateway_doctor_fail "dnsmasq DNS forwarding disabled (port=0)" ;;
            *) gateway_doctor_warn "dnsmasq DNS forwarding uses nonstandard port $dns_port" ;;
        esac
        resolv_file="$(sed -n 's/^resolv-file=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ -n "$resolv_file" ] || resolv_file="/etc/resolv.conf"
        static_servers="$(sed -n 's/^server=//p' "$AP_DNSMASQ_CONF" 2>/dev/null || true)"
        if [ -n "$static_servers" ]; then
            gateway_doctor_ok "dnsmasq has static upstream DNS server entries"
        elif [ -r "$resolv_file" ] && grep -q '^nameserver[[:space:]]' "$resolv_file" 2>/dev/null; then
            gateway_doctor_ok "dnsmasq upstream DNS source has nameservers: $resolv_file"
        else
            gateway_doctor_fail "dnsmasq has no readable upstream DNS source"
        fi
    else
        gateway_doctor_fail "dnsmasq config missing: $AP_DNSMASQ_CONF"
    fi
    gateway_doctor_recent_dhcp_ack && gateway_doctor_ok "recent DHCPACK found for $AP_IF" || gateway_doctor_warn "no recent DHCPACK found; connect a client and rerun if needed"

    gateway_doctor_section "packet counters"
    gateway_doctor_chain_counters

    gateway_doctor_section "transparent proxy baseline"
    gateway_doctor_ok "plain NAT baseline is isolated from transparent proxy"
    gateway_doctor_ok "no TProxy or mangle rules are required for current gateway mode"

    say ""
    say "[INFO] gateway doctor summary: OK=$GATEWAY_DOCTOR_OK WARN=$GATEWAY_DOCTOR_WARN ERROR=$GATEWAY_DOCTOR_FAIL"
    if [ "$GATEWAY_DOCTOR_FAIL" -gt 0 ]; then
        say "[ERROR] gateway baseline is not healthy enough for transparent proxy work"
        return 1
    fi
    if [ "$GATEWAY_DOCTOR_WARN" -gt 0 ]; then
        say "[WARN] gateway baseline works with warnings; review WARN items before TProxy work"
        return 0
    fi
    say "[OK] gateway baseline is healthy"
}
# -----------------------------
# TProxy read-only inspection: no rules are created here
# -----------------------------
tproxy_info() { say "[INFO] $*"; }
tproxy_ok() { say "[OK] $*"; }
tproxy_warn() { say "[WARN] $*"; }

tproxy_is_root() {
    uid="$(id -u 2>/dev/null || echo 1)"
    [ "$uid" = "0" ]
}

tproxy_mihomo_port() {
    [ -f "$CONFIG_FILE" ] || return 1
    port="$(sed -n 's/^[[:space:]]*tproxy-port[[:space:]]*:[[:space:]]*//p' "$CONFIG_FILE" 2>/dev/null | \
        sed 's/[[:space:]]*#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//' | head -n 1)"
    [ -n "$port" ] || return 1
    printf '%s\n' "$port"
}

tproxy_module_hint_one() {
    mod="$1"
    if [ -r /proc/modules ] && grep -q "^$mod[[:space:]]" /proc/modules 2>/dev/null; then
        tproxy_ok "$mod: loaded"
        return 0
    fi
    if have modprobe && modprobe -n -v "$mod" >/dev/null 2>&1; then
        tproxy_info "$mod: available by modprobe dry-run"
        return 0
    fi
    tproxy_warn "$mod: not loaded or unknown"
}

tproxy_mangle_table_available() {
    gateway_have_iptables || return 1
    iptables -t mangle -S >/dev/null 2>&1
}

tproxy_mangle_rules_present() {
    tproxy_mangle_table_available || return 1
    iptables -t mangle -S 2>/dev/null | grep -e "$TPROXY_MANGLE_CHAIN" -e 'TPROXY' >/dev/null 2>&1
}

tproxy_ip_rule_present() {
    have ip || return 1
    ip rule show 2>/dev/null | grep 'fwmark' | grep "$TPROXY_MARK" | grep "lookup $TPROXY_ROUTE_TABLE" >/dev/null 2>&1
}

tproxy_route_table_present() {
    have ip || return 1
    routes="$(ip route show table "$TPROXY_ROUTE_TABLE" 2>/dev/null || true)"
    [ -n "$routes" ]
}

tproxy_gateway_fallback_state() {
    if gateway_rules_active; then
        printf 'yes\n'
    elif gateway_have_iptables; then
        if tproxy_is_root; then
            printf 'no\n'
        else
            printf 'unknown\n'
        fi
    else
        printf 'unknown\n'
    fi
}

tproxy_state_mangle() {
    if ! gateway_have_iptables; then
        printf 'unknown\n'
    elif ! tproxy_mangle_table_available; then
        printf 'unknown\n'
    elif tproxy_mangle_rules_present; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

tproxy_state_ip_rule() {
    if ! have ip; then
        printf 'unknown\n'
    elif ! ip rule show >/dev/null 2>&1; then
        printf 'unknown\n'
    elif tproxy_ip_rule_present; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

tproxy_state_route_table() {
    if ! have ip; then
        printf 'unknown\n'
    elif ! ip route show table all >/dev/null 2>&1; then
        printf 'unknown\n'
    elif tproxy_route_table_present; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

tproxy_enabled_state() {
    mangle_state="$1"
    rule_state="$2"
    route_state="$3"
    port_state="$4"

    if [ "$mangle_state" = "no" ] && [ "$rule_state" = "no" ] && [ "$route_state" = "no" ]; then
        printf 'no\n'
        return 0
    fi
    if [ "$mangle_state" = "yes" ] && [ "$rule_state" = "yes" ] && [ "$route_state" = "yes" ] && [ "$port_state" != "none" ]; then
        printf 'yes\n'
        return 0
    fi
    if [ "$mangle_state" = "yes" ] || [ "$rule_state" = "yes" ] || [ "$route_state" = "yes" ]; then
        printf 'partial\n'
        return 0
    fi
    printf 'unknown\n'
}

cmd_tproxy_check() {
    ap_load_config
    tproxy_info "checking TProxy capabilities..."
    if tproxy_is_root; then
        tproxy_ok "root: yes"
    else
        tproxy_warn "root: no; some iptables/ip checks may be incomplete"
    fi

    if gateway_have_iptables; then
        tproxy_ok "iptables: $(command -v iptables 2>/dev/null)"
        if tproxy_mangle_table_available; then
            tproxy_ok "mangle table: available"
        else
            tproxy_warn "mangle table: unavailable or permission denied"
        fi
        if iptables -j TPROXY -h >/dev/null 2>&1; then
            tproxy_ok "TPROXY target: userspace extension available"
        else
            tproxy_warn "TPROXY target: unknown"
        fi
        if iptables -m socket -h >/dev/null 2>&1; then
            tproxy_ok "socket match: userspace extension available"
        else
            tproxy_warn "socket match: unknown"
        fi
    else
        tproxy_warn "iptables: missing"
        tproxy_warn "mangle table: unknown"
        tproxy_warn "TPROXY target: unknown"
        tproxy_warn "socket match: unknown"
    fi

    if have ip; then
        if ip rule show >/dev/null 2>&1; then
            tproxy_ok "ip rule: available"
        else
            tproxy_warn "ip rule: unavailable or permission denied"
        fi
        if ip route show table all >/dev/null 2>&1; then
            tproxy_ok "ip route: available"
        else
            tproxy_warn "ip route: unavailable or permission denied"
        fi
    else
        tproxy_warn "ip rule: ip command missing"
        tproxy_warn "ip route: ip command missing"
    fi

    tproxy_info "checking kernel module hints..."
    tproxy_module_hint_one xt_TPROXY
    tproxy_module_hint_one nf_tproxy_ipv4
    tproxy_module_hint_one xt_socket
    tproxy_module_hint_one nf_defrag_ipv4

    if [ -x "$CORE_BIN" ]; then
        tproxy_ok "mihomo: $CORE_BIN"
    elif [ -f "$CORE_BIN" ]; then
        tproxy_warn "mihomo: exists but not executable: $CORE_BIN"
    else
        tproxy_warn "mihomo: missing: $CORE_BIN"
    fi

    tproxy_port="$(tproxy_mihomo_port || true)"
    if [ -n "$tproxy_port" ]; then
        tproxy_ok "mihomo tproxy-port: $tproxy_port"
    else
        tproxy_info "mihomo tproxy-port: none"
    fi

    fallback="$(tproxy_gateway_fallback_state)"
    case "$fallback" in
        yes) tproxy_ok "gateway fallback: active" ;;
        no) tproxy_warn "gateway fallback: inactive" ;;
        *) tproxy_warn "gateway fallback: unknown" ;;
    esac

    mangle_state="$(tproxy_state_mangle)"
    rule_state="$(tproxy_state_ip_rule)"
    route_state="$(tproxy_state_route_table)"
    port_state="${tproxy_port:-none}"
    enabled="$(tproxy_enabled_state "$mangle_state" "$rule_state" "$route_state" "$port_state")"
    case "$enabled" in
        yes) tproxy_ok "TProxy appears enabled" ;;
        partial) tproxy_warn "TProxy appears partially configured; possible leftover state" ;;
        no) tproxy_warn "TProxy is not configured yet" ;;
        *) tproxy_warn "TProxy state: unknown" ;;
    esac
}

cmd_tproxy_status() {
    ap_load_config
    tproxy_port="$(tproxy_mihomo_port || true)"
    [ -n "$tproxy_port" ] || tproxy_port="none"
    mangle_state="$(tproxy_state_mangle)"
    rule_state="$(tproxy_state_ip_rule)"
    route_state="$(tproxy_state_route_table)"
    fallback="$(tproxy_gateway_fallback_state)"
    enabled="$(tproxy_enabled_state "$mangle_state" "$rule_state" "$route_state" "$tproxy_port")"

    tproxy_info "tproxy enabled: $enabled"
    tproxy_info "mangle rules present: $mangle_state"
    tproxy_info "ip rule present: $rule_state"
    tproxy_info "route table present: $route_state"
    tproxy_info "mihomo tproxy-port: $tproxy_port"
    tproxy_info "gateway fallback active: $fallback"

    case "$enabled" in
        yes)
            tproxy_info "suggested next step: verify traffic path and keep NAT fallback available"
            ;;
        partial)
            tproxy_warn "suggested next step: inspect possible leftover TProxy state; do not enable more rules yet"
            ;;
        no)
            if [ "$fallback" = "yes" ]; then
                tproxy_info "suggested next step: keep NAT fallback active, then configure mihomo tproxy-port before enabling TProxy"
            else
                tproxy_warn "suggested next step: restore gateway fallback before TProxy work"
            fi
            ;;
        *)
            tproxy_warn "suggested next step: rerun as root and inspect iptables/ip support"
            ;;
    esac
}
tproxy_plan_section() {
    say ""
    say "[$1]"
}

tproxy_planned_port() {
    current="$(tproxy_mihomo_port || true)"
    if [ -n "$current" ]; then
        printf '%s\n' "$current"
    else
        printf '%s\n' "$TPROXY_PORT"
    fi
}

tproxy_capability_summary() {
    if tproxy_is_root; then
        tproxy_ok "root: yes"
    else
        tproxy_warn "root: no; some checks may be incomplete"
    fi
    if gateway_have_iptables; then
        tproxy_ok "iptables: $(command -v iptables 2>/dev/null)"
    else
        tproxy_warn "iptables: missing"
    fi
    if tproxy_mangle_table_available; then
        tproxy_ok "mangle table: available"
    else
        tproxy_warn "mangle table: unavailable or unknown"
    fi
    if gateway_have_iptables && iptables -j TPROXY -h >/dev/null 2>&1; then
        tproxy_ok "TPROXY target: userspace extension available"
    else
        tproxy_warn "TPROXY target: unknown"
    fi
    if gateway_have_iptables && iptables -m socket -h >/dev/null 2>&1; then
        tproxy_ok "socket match: userspace extension available"
    else
        tproxy_warn "socket match: unknown"
    fi
    if have ip && ip rule show >/dev/null 2>&1; then
        tproxy_ok "ip rule: available"
    else
        tproxy_warn "ip rule: unavailable or unknown"
    fi
    if have ip && ip route show table all >/dev/null 2>&1; then
        tproxy_ok "ip route: available"
    else
        tproxy_warn "ip route: unavailable or unknown"
    fi
    if [ -x "$CORE_BIN" ]; then
        tproxy_ok "mihomo: $CORE_BIN"
    elif [ -f "$CORE_BIN" ]; then
        tproxy_warn "mihomo: exists but not executable: $CORE_BIN"
    else
        tproxy_warn "mihomo: missing: $CORE_BIN"
    fi
    tproxy_info "kernel module hints:"
    tproxy_module_hint_one xt_TPROXY
    tproxy_module_hint_one nf_tproxy_ipv4
    tproxy_module_hint_one xt_socket
    tproxy_module_hint_one nf_defrag_ipv4
}

tproxy_current_state() {
    current_port="$(tproxy_mihomo_port || true)"
    [ -n "$current_port" ] || current_port="none"
    mangle_state="$(tproxy_state_mangle)"
    rule_state="$(tproxy_state_ip_rule)"
    route_state="$(tproxy_state_route_table)"
    fallback="$(tproxy_gateway_fallback_state)"
    enabled="$(tproxy_enabled_state "$mangle_state" "$rule_state" "$route_state" "$current_port")"

    tproxy_info "tproxy enabled: $enabled"
    tproxy_info "mangle rules present: $mangle_state"
    tproxy_info "ip rule present: $rule_state"
    tproxy_info "route table present: $route_state"
    tproxy_info "mihomo tproxy-port: $current_port"
    tproxy_info "gateway fallback active: $fallback"
}

tproxy_print_reserved_bypass_plan() {
    say "planned gateway service bypasses:"
    say "  $AP_IPADDR:53 tcp/udp"
    say "  DHCP udp 67/68"
    say "planned reserved-address bypasses:"
    for cidr in $(tproxy_reserved_cidrs); do
        say "  $cidr"
    done
}

tproxy_print_mangle_rule_summary() {
    tproxy_print_reserved_bypass_plan
    if [ "$TPROXY_SOCKET_BYPASS" = "1" ]; then
        say "planned local-socket bypass: enabled by MGATE_TPROXY_SOCKET_BYPASS=1"
    else
        say "planned local-socket bypass: disabled by default to avoid leaking AP traffic back to NAT"
    fi
    say "planned AP client scope: PREROUTING -i $AP_IF only"
    say "planned TCP redirect: TPROXY --on-port $1 --tproxy-mark $TPROXY_MARK"
    say "planned UDP redirect: TPROXY --on-port $1 --tproxy-mark $TPROXY_MARK"
    say "mgate/mihomo self-traffic note: local process OUTPUT traffic is not captured by PREROUTING -i $AP_IF"
}

tproxy_print_rollback_plan() {
    say "rollback plan:"
    say "  remove PREROUTING jump to $TPROXY_MANGLE_CHAIN"
    say "  flush and delete mangle chain $TPROXY_MANGLE_CHAIN"
    say "  delete ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE"
    say "  flush route table $TPROXY_ROUTE_TABLE"
    say "  restore mihomo config from backup if future tproxy-start changes it"
    say "  keep ordinary NAT gateway fallback available"
}

tproxy_print_risks() {
    say "risks:"
    say "  TProxy target availability is only a capability hint until real rules are applied"
    say "  socket bypass is disabled by default because it can leak AP traffic to NAT"
    say "  kernel modules may be built in and not visible in /proc/modules"
    say "  UDP transparent proxy behavior depends on mihomo tproxy support and DNS handling"
    say "  OUTPUT traffic from local mgate/mihomo is not part of this AP PREROUTING plan"
    say "  ordinary NAT fallback must stay available for rollback"
}

cmd_tproxy_plan() {
    ap_load_config
    planned_port="$(tproxy_planned_port)"
    current_port="$(tproxy_mihomo_port || true)"
    [ -n "$current_port" ] || current_port="none"

    tproxy_plan_section "current state"
    tproxy_current_state

    tproxy_plan_section "capability summary"
    tproxy_capability_summary

    tproxy_plan_section "planned changes"
    tproxy_info "tproxy-port $TPROXY_PORT is always enabled when mihomo starts (built into default config)"
    tproxy_info "tproxy-start only requires: mihomo running + port $TPROXY_PORT listening"
    tproxy_info "planned mark: $TPROXY_MARK"
    tproxy_info "planned route table: $TPROXY_ROUTE_TABLE"
    tproxy_info "planned mangle chain: $TPROXY_MANGLE_CHAIN"
    tproxy_info "planned ip rule: fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE"
    tproxy_info "planned route: local 0.0.0.0/0 dev lo table $TPROXY_ROUTE_TABLE"
    tproxy_print_mangle_rule_summary "$planned_port"

    tproxy_plan_section "fallback"
    fallback="$(tproxy_gateway_fallback_state)"
    tproxy_info "ordinary NAT gateway fallback: $fallback"

    tproxy_plan_section "rollback plan"
    tproxy_print_rollback_plan

    tproxy_plan_section "risks"
    tproxy_print_risks

    say ""
    tproxy_info "this command did not modify the system"
}

cmd_tproxy_dry_run() {
    ap_load_config
    planned_port="$(tproxy_planned_port)"
    current_port="$(tproxy_mihomo_port || true)"
    [ -n "$current_port" ] || current_port="none"

    tproxy_plan_section "current state"
    tproxy_current_state

    tproxy_plan_section "dry-run commands not executed"
    say "# tproxy-port $TPROXY_PORT is always in mihomo config; no config modification at runtime"
    say "# prerequisite: mgate start (mihomo must be running and port $TPROXY_PORT listening)"
    say "ip rule add fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE"
    say "ip route add local 0.0.0.0/0 dev lo table $TPROXY_ROUTE_TABLE"
    say "iptables -t mangle -N $TPROXY_MANGLE_CHAIN"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -d $AP_IPADDR/32 -p udp --dport 53 -j RETURN"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -d $AP_IPADDR/32 -p tcp --dport 53 -j RETURN"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -p udp --dport 67:68 -j RETURN"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -p udp --sport 67:68 -j RETURN"
    for cidr in $(tproxy_reserved_cidrs); do
        say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -d $cidr -j RETURN"
    done
    say "# socket bypass is disabled by default; only with MGATE_TPROXY_SOCKET_BYPASS=1:"
    say "# iptables -t mangle -A $TPROXY_MANGLE_CHAIN -p tcp -m socket -j RETURN"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -p tcp -j TPROXY --on-port $planned_port --tproxy-mark $TPROXY_MARK"
    say "iptables -t mangle -A $TPROXY_MANGLE_CHAIN -p udp -j TPROXY --on-port $planned_port --tproxy-mark $TPROXY_MARK"
    say "iptables -t mangle -I PREROUTING 1 -i $AP_IF -j $TPROXY_MANGLE_CHAIN"
    say "# future tproxy-start may restart mihomo only if config changes"

    tproxy_plan_section "rollback commands not executed"
    say "while iptables -t mangle -D PREROUTING -i $AP_IF -j $TPROXY_MANGLE_CHAIN 2>/dev/null; do :; done"
    say "iptables -t mangle -F $TPROXY_MANGLE_CHAIN 2>/dev/null || true"
    say "iptables -t mangle -X $TPROXY_MANGLE_CHAIN 2>/dev/null || true"
    say "ip rule del fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE 2>/dev/null || true"
    say "ip route del local 0.0.0.0/0 dev lo table $TPROXY_ROUTE_TABLE 2>/dev/null || true"
    say "ip route flush table $TPROXY_ROUTE_TABLE 2>/dev/null || true"
    say "# mihomo config is not modified at runtime; no config restore needed"

    tproxy_plan_section "risks"
    tproxy_print_risks

    say ""
    tproxy_info "dry-run only; no commands were executed"
}
tproxy_log() {
    ensure_dirs
    ts="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
    printf '%s %s\n' "$ts" "$*" >> "$TPROXY_LOG_FILE" 2>/dev/null || true
}

tproxy_save_error() {
    ensure_dirs
    say "[ERROR] $*"
    printf '%s\n' "$*" > "$TPROXY_LAST_ERROR_FILE" 2>/dev/null || true
    tproxy_log "ERROR: $*"
}

tproxy_clear_error() {
    rm -f "$TPROXY_LAST_ERROR_FILE" 2>/dev/null || true
}

tproxy_target_available() {
    gateway_have_iptables || return 1
    iptables -j TPROXY -h >/dev/null 2>&1
}

tproxy_socket_match_available() {
    gateway_have_iptables || return 1
    iptables -m socket -h >/dev/null 2>&1
}
tproxy_socket_bypass_rule_present() {
    gateway_have_iptables || return 1
    iptables -t mangle -S "$TPROXY_MANGLE_CHAIN" 2>/dev/null | grep -- '-p tcp' | grep -- '-m socket' | grep -- '-j RETURN' >/dev/null 2>&1
}

tproxy_route_local_present() {
    have ip || return 1
    ip route show table "$TPROXY_ROUTE_TABLE" 2>/dev/null | \
        awk '$1 == "local" && $0 ~ /dev[[:space:]]+lo/ && ($2 == "0.0.0.0/0" || $2 == "default") {found=1} END {exit found ? 0 : 1}'
}

tproxy_mangle_chain_exists() {
    gateway_have_iptables || return 1
    iptables -t mangle -S "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1
}

tproxy_prerouting_hook_exists() {
    gateway_have_iptables || return 1
    iptables -t mangle -C PREROUTING -i "$AP_IF" -j "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1
}

tproxy_chain_has_tproxy_rule() {
    proto="$1"
    gateway_have_iptables || return 1
    iptables -t mangle -S "$TPROXY_MANGLE_CHAIN" 2>/dev/null | \
        grep -- "-p $proto" | grep -- '-j TPROXY' | grep -- "--on-port $TPROXY_PORT" >/dev/null 2>&1
}

ap_network_cidr() {
    prefix="$(ap_netmask_prefix "$AP_NETMASK")"
    old_ifs="$IFS"
    IFS=.
    set -- $AP_IPADDR
    ip1="$1"; ip2="$2"; ip3="$3"; ip4="$4"
    set -- $AP_NETMASK
    nm1="$1"; nm2="$2"; nm3="$3"; nm4="$4"
    IFS="$old_ifs"
    [ -n "$ip1" ] && [ -n "$nm1" ] || { printf '%s/%s\n' "$AP_IPADDR" "$prefix"; return 0; }
    printf '%s.%s.%s.%s/%s\n' "$((ip1 & nm1))" "$((ip2 & nm2))" "$((ip3 & nm3))" "$((ip4 & nm4))" "$prefix"
}

tproxy_reserved_cidrs() {
    printf '%s\n' "$AP_IPADDR/32"
    printf '%s\n' "$(ap_network_cidr)"
    printf '%s\n' \
        127.0.0.0/8 \
        0.0.0.0/8 \
        10.0.0.0/8 \
        100.64.0.0/10 \
        169.254.0.0/16 \
        172.16.0.0/12 \
        192.168.0.0/16 \
        224.0.0.0/4 \
        240.0.0.0/4 \
        255.255.255.255/32
}

tproxy_skip_rules_complete() {
    gateway_have_iptables || return 1
    tproxy_mangle_chain_exists || return 1
    for cidr in $(tproxy_reserved_cidrs); do
        iptables -t mangle -S "$TPROXY_MANGLE_CHAIN" 2>/dev/null | grep -- "-d $cidr" | grep -- '-j RETURN' >/dev/null 2>&1 || return 1
    done
}

tproxy_mihomo_running() {
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if [ -x "$OPENWRT_SERVICE_LINK" ] && "$OPENWRT_SERVICE_LINK" status >/dev/null 2>&1; then
                return 0
            fi
            ;;
        systemd)
            if have systemctl && [ -e "$SYSTEMD_SERVICE_LINK" ] && systemctl is-active --quiet mgate.service >/dev/null 2>&1; then
                return 0
            fi
            ;;
    esac
    fallback_status_quiet
}

tproxy_stop_plain_mihomo() {
    if fallback_status_quiet; then
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ]; then
            kill "$pid" >/dev/null 2>&1 || true
            i=0
            while kill -0 "$pid" >/dev/null 2>&1; do
                i=$((i + 1))
                [ "$i" -ge 10 ] && break
                sleep 1
            done
            kill -0 "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
        fi
    fi
    rm -f "$PID_FILE" 2>/dev/null || true
}

tproxy_start_plain_mihomo() {
    [ -x "$CORE_BIN" ] || return 1
    [ -f "$CONFIG_FILE" ] || return 1
    ensure_dirs
    nohup "$CORE_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE" 2>/dev/null || return 1
}

tproxy_restart_mihomo() {
    ensure_dirs
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if [ -x "$OPENWRT_SERVICE_LINK" ]; then
                "$OPENWRT_SERVICE_LINK" restart >> "$TPROXY_LOG_FILE" 2>&1 || return 1
            else
                tproxy_stop_plain_mihomo
                tproxy_start_plain_mihomo || return 1
            fi
            ;;
        systemd)
            if have systemctl && [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                systemctl restart mgate.service >> "$TPROXY_LOG_FILE" 2>&1 || return 1
            else
                tproxy_stop_plain_mihomo
                tproxy_start_plain_mihomo || return 1
            fi
            ;;
        *)
            tproxy_stop_plain_mihomo
            tproxy_start_plain_mihomo || return 1
            ;;
    esac
    sleep 2
    tproxy_mihomo_running
}

tproxy_port_listening() {
    if have ss; then
        ss -ltnu 2>/dev/null | awk -v p=":$TPROXY_PORT" 'index($0, p) > 0 {found=1} END {exit found ? 0 : 1}'
        return $?
    fi
    if have netstat; then
        netstat -ltnu 2>/dev/null | awk -v p=":$TPROXY_PORT" 'index($0, p) > 0 {found=1} END {exit found ? 0 : 1}'
        return $?
    fi
    return 2
}

tproxy_config_backup_path() {
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)"
    printf '%s/config-before-tproxy-%s.yaml\n' "$BACKUP_DIR" "$ts"
}

tproxy_backup_config() {
    backup_path="$(tproxy_config_backup_path)"
    mkdir -p "$BACKUP_DIR" || return 1
    cp -p "$CONFIG_FILE" "$backup_path" || return 1
    printf '%s\n' "$backup_path" > "$TPROXY_CONFIG_BACKUP_FILE" 2>/dev/null || true
    printf '%s\n' "$backup_path"
}

tproxy_config_value() {
    key="$1"
    [ -f "$CONFIG_FILE" ] || return 1
    sed -n "s/^[[:space:]]*$key[[:space:]]*:[[:space:]]*//p" "$CONFIG_FILE" 2>/dev/null | \
        sed 's/[[:space:]]*#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//; s/^'\''//; s/'\''$//' | head -n 1
}

tproxy_config_bool_true() {
    value="$(tproxy_config_value "$1" || true)"
    [ "$value" = "true" ] || [ "$value" = "True" ] || [ "$value" = "TRUE" ]
}

tproxy_config_bind_ok() {
    value="$(tproxy_config_value bind-address || true)"
    [ -z "$value" ] && return 1
    [ "$value" = "*" ] || [ "$value" = "0.0.0.0" ]
}

tproxy_config_has_out_group() {
    grep -q "^[[:space:]]*-[[:space:]]*name:[[:space:]]*[\"']*$TPROXY_OUT_GROUP[\"']*[[:space:]]*$" "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_out_group_ok() {
    tproxy_config_has_out_group || return 1
    if ! tproxy_config_has_provider; then
        return 0
    fi
    awk -v name="$TPROXY_OUT_GROUP" '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_group=0; in_groups=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            in_group=(line == name)
            next
        }
        in_group && /^[[:space:]]*type:[[:space:]]*url-test[[:space:]]*$/ {found=1}
        END {exit found ? 0 : 1}
    ' "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_has_in_type_rule() {
    grep -q "^[[:space:]]*-[[:space:]]*IN-TYPE,TPROXY,$TPROXY_OUT_GROUP[[:space:]]*$" "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_has_provider() {
    grep -q '^[[:space:]]*mgate-sub:[[:space:]]*$' "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_group_names() {
    awk '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_groups=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            if (line != "" && line != "TPROXY-OUT") print line
        }
    ' "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_set_key() {
    key="$1"
    value="$2"
    tmp="$TMP_DIR/tproxy-config.$$.$key"
    awk -v key="$key" -v value="$value" '
        BEGIN {done=0}
        $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
            print key ": " value
            done=1
            next
        }
        {print}
        END {
            if (!done) print key ": " value
        }
    ' "$CONFIG_FILE" > "$tmp" || return 1
    mv "$tmp" "$CONFIG_FILE" || return 1
}

tproxy_config_remove_out_group() {
    tmp="$TMP_DIR/tproxy-config.$$.remove-group"
    awk -v name="$TPROXY_OUT_GROUP" '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            skip=(line == name)
        }
        in_groups && /^rules:[[:space:]]*$/ {skip=0; in_groups=0}
        skip {next}
        {print}
    ' "$CONFIG_FILE" > "$tmp" || return 1
    mv "$tmp" "$CONFIG_FILE" || return 1
}

tproxy_config_insert_group() {
    tmp="$TMP_DIR/tproxy-config.$$.group"
    groups="$(tproxy_config_group_names | sed 's/^/      - /')"
    [ -n "$groups" ] || groups="      - DIRECT"
    if tproxy_config_has_provider; then
        awk -v name="$TPROXY_OUT_GROUP" '
            BEGIN {inserted=0}
            /^rules:[[:space:]]*$/ && !inserted {
                print "  - name: " name
                print "    type: url-test"
                print "    use:"
                print "      - mgate-sub"
                print "    url: http://www.gstatic.com/generate_204"
                print "    interval: 300"
                print ""
                inserted=1
            }
            {print}
        ' "$CONFIG_FILE" > "$tmp" || return 1
    else
        awk -v name="$TPROXY_OUT_GROUP" -v groups="$groups" '
            BEGIN {inserted=0}
            /^rules:[[:space:]]*$/ && !inserted {
                print "  - name: " name
                print "    type: select"
                print "    proxies:"
                print groups
                print ""
                inserted=1
            }
            {print}
        ' "$CONFIG_FILE" > "$tmp" || return 1
    fi
    mv "$tmp" "$CONFIG_FILE" || return 1
}

tproxy_config_insert_rule() {
    tmp="$TMP_DIR/tproxy-config.$$.rule"
    awk -v group="$TPROXY_OUT_GROUP" '
        BEGIN {inserted=0}
        /^rules:[[:space:]]*$/ && !inserted {
            print
            print "  - IN-TYPE,TPROXY," group
            inserted=1
            next
        }
        {print}
    ' "$CONFIG_FILE" > "$tmp" || return 1
    mv "$tmp" "$CONFIG_FILE" || return 1
}

tproxy_ensure_config_port() {
    current_port="$(tproxy_mihomo_port || true)"
    if [ -n "$current_port" ] && [ "$current_port" != "$TPROXY_PORT" ]; then
        tproxy_save_error "config has tproxy-port $current_port, expected $TPROXY_PORT; not overwriting user config"
        return 1
    fi

    needs_update=0
    [ -n "$current_port" ] || needs_update=1
    tproxy_config_bool_true allow-lan || needs_update=1
    tproxy_config_bind_ok || needs_update=1
    tproxy_config_out_group_ok || needs_update=1
    tproxy_config_has_in_type_rule || needs_update=1

    if [ "$needs_update" -eq 0 ]; then
        tproxy_ok "mihomo transparent config already present"
        return 0
    fi

    backup_path="$(tproxy_backup_config)" || return 1
    TPROXY_START_BACKUP="$backup_path"

    if [ -z "$current_port" ]; then
        {
            printf '\n'
            printf '# Added by mgate tproxy-start\n'
            printf 'tproxy-port: %s\n' "$TPROXY_PORT"
        } >> "$CONFIG_FILE" || { tproxy_restore_config_from_backup "$backup_path" >/dev/null 2>&1 || true; return 1; }
    fi

    tproxy_config_bool_true allow-lan || tproxy_config_set_key allow-lan true || { tproxy_restore_config_from_backup "$backup_path" >/dev/null 2>&1 || true; return 1; }
    tproxy_config_bind_ok || tproxy_config_set_key bind-address "'*'" || { tproxy_restore_config_from_backup "$backup_path" >/dev/null 2>&1 || true; return 1; }
    tproxy_config_out_group_ok || { tproxy_config_remove_out_group && tproxy_config_insert_group; } || { tproxy_restore_config_from_backup "$backup_path" >/dev/null 2>&1 || true; return 1; }
    tproxy_config_has_in_type_rule || tproxy_config_insert_rule || { tproxy_restore_config_from_backup "$backup_path" >/dev/null 2>&1 || true; return 1; }

    printf '%s\n' "$backup_path" > "$TPROXY_CONFIG_OWNED_FILE" 2>/dev/null || true
    TPROXY_START_CONFIG_MODIFIED=1
    tproxy_ok "mihomo config updated for TProxy: port=$TPROXY_PORT group=$TPROXY_OUT_GROUP"
}

tproxy_restore_config_from_backup() {
    backup_path="$1"
    [ -n "$backup_path" ] || return 1
    [ -f "$backup_path" ] || return 1
    cp -p "$backup_path" "$CONFIG_FILE" || return 1
}

tproxy_restore_owned_config() {
    backup_path="$(sed -n '1p' "$TPROXY_CONFIG_OWNED_FILE" 2>/dev/null || true)"
    if [ -z "$backup_path" ]; then
        backup_path="$(sed -n '1p' "$TPROXY_CONFIG_BACKUP_FILE" 2>/dev/null || true)"
    fi
    if [ -z "$backup_path" ]; then
        tproxy_warn "no mgate-owned tproxy config backup marker found; config not changed"
        return 0
    fi
    if tproxy_restore_config_from_backup "$backup_path"; then
        rm -f "$TPROXY_CONFIG_OWNED_FILE" "$TPROXY_CONFIG_BACKUP_FILE" 2>/dev/null || true
        tproxy_ok "mihomo config restored from $backup_path"
        if tproxy_restart_mihomo; then
            tproxy_ok "mihomo restarted after config restore"
            return 0
        fi
        tproxy_warn "mihomo restart failed after config restore"
        return 1
    fi
    tproxy_warn "failed to restore mihomo config from $backup_path"
    return 1
}

tproxy_test_config() {
    ensure_dirs
    out="$TMP_DIR/tproxy-config-test.out"
    [ -x "$CORE_BIN" ] || return 1
    [ -f "$CONFIG_FILE" ] || return 1
    "$CORE_BIN" -t -f "$CONFIG_FILE" > "$out" 2>&1
}

tproxy_delete_prerouting_jumps() {
    gateway_have_iptables || return 0
    while iptables -t mangle -D PREROUTING -i "$AP_IF" -j "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1; do
        :
    done
    while iptables -t mangle -D PREROUTING -j "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1; do
        :
    done
    iptables -t mangle -S PREROUTING 2>/dev/null | grep -- "-j $TPROXY_MANGLE_CHAIN" >/dev/null 2>&1 && return 1
    return 0
}

tproxy_flush_delete_chain() {
    gateway_have_iptables || return 0
    iptables -t mangle -F "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -X "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1 || true
    tproxy_mangle_chain_exists && return 1
    return 0
}

tproxy_remove_ip_rules() {
    have ip || return 0
    while ip rule del fwmark "$TPROXY_MARK" lookup "$TPROXY_ROUTE_TABLE" >/dev/null 2>&1; do
        :
    done
    tproxy_ip_rule_present && return 1
    return 0
}

tproxy_remove_route_table() {
    have ip || return 0
    ip route del local 0.0.0.0/0 dev lo table "$TPROXY_ROUTE_TABLE" >/dev/null 2>&1 || true
    ip route flush table "$TPROXY_ROUTE_TABLE" >/dev/null 2>&1 || true
    tproxy_route_local_present && return 1
    return 0
}

tproxy_remove_rules() {
    failed=0
    tproxy_delete_prerouting_jumps || failed=1
    tproxy_flush_delete_chain || failed=1
    tproxy_remove_ip_rules || failed=1
    tproxy_remove_route_table || failed=1
    [ "$failed" -eq 0 ]
}

tproxy_add_ip_rule() {
    tproxy_ip_rule_present && return 0
    ip rule add fwmark "$TPROXY_MARK" lookup "$TPROXY_ROUTE_TABLE"
}

tproxy_add_route() {
    tproxy_route_local_present && return 0
    ip route add local 0.0.0.0/0 dev lo table "$TPROXY_ROUTE_TABLE"
}

tproxy_build_mangle_chain() {
    tproxy_delete_prerouting_jumps
    tproxy_flush_delete_chain
    iptables -t mangle -N "$TPROXY_MANGLE_CHAIN" || return 1

    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -d "$AP_IPADDR/32" -p udp --dport 53 -j RETURN || return 1
    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -d "$AP_IPADDR/32" -p tcp --dport 53 -j RETURN || return 1
    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -p udp --dport 67:68 -j RETURN || return 1
    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -p udp --sport 67:68 -j RETURN || return 1

    for cidr in $(tproxy_reserved_cidrs); do
        iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -d "$cidr" -j RETURN || return 1
    done

    if [ "$TPROXY_SOCKET_BYPASS" = "1" ]; then
        if tproxy_socket_match_available; then
            iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -p tcp -m socket -j RETURN || return 1
            tproxy_warn "socket match bypass rule installed by MGATE_TPROXY_SOCKET_BYPASS=1; AP traffic may bypass TProxy"
        else
            tproxy_warn "socket match unavailable; continuing without socket bypass rule"
        fi
    else
        tproxy_ok "socket match bypass disabled; AP TCP traffic will not be returned to NAT by socket match"
    fi

    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -p tcp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$TPROXY_MARK" || return 1
    iptables -t mangle -A "$TPROXY_MANGLE_CHAIN" -p udp -j TPROXY --on-port "$TPROXY_PORT" --tproxy-mark "$TPROXY_MARK" || return 1

    iptables -t mangle -C PREROUTING -i "$AP_IF" -j "$TPROXY_MANGLE_CHAIN" >/dev/null 2>&1 || \
        iptables -t mangle -I PREROUTING 1 -i "$AP_IF" -j "$TPROXY_MANGLE_CHAIN" || return 1
}

tproxy_write_enabled() {
    ensure_dirs
    {
        printf 'enabled_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo now)"
        printf 'port=%s\n' "$TPROXY_PORT"
        printf 'mark=%s\n' "$TPROXY_MARK"
        printf 'route_table=%s\n' "$TPROXY_ROUTE_TABLE"
        printf 'mangle_chain=%s\n' "$TPROXY_MANGLE_CHAIN"
        if [ -n "${TPROXY_START_BACKUP:-}" ]; then
            printf 'config_backup=%s\n' "$TPROXY_START_BACKUP"
        fi
    } > "$TPROXY_ENABLED_FILE" || return 1
}

tproxy_core_rules_active() {
    [ "$(tproxy_state_mangle)" = "yes" ] || return 1
    tproxy_ip_rule_present || return 1
    tproxy_route_local_present || return 1
    tproxy_prerouting_hook_exists || return 1
    tproxy_chain_has_tproxy_rule tcp || return 1
    tproxy_chain_has_tproxy_rule udp || return 1
}

tproxy_rollback() {
    reason="$1"
    tproxy_warn "tproxy-start failed; rolling back: $reason"
    tproxy_save_error "$reason"
    rollback_failed=0

    if tproxy_remove_rules; then
        tproxy_ok "TProxy rules removed during rollback"
    else
        tproxy_warn "failed to remove some TProxy rules during rollback"
        rollback_failed=1
    fi

    rm -f "$TPROXY_ENABLED_FILE" 2>/dev/null || true
    if [ "$rollback_failed" -eq 0 ]; then
        tproxy_ok "rollback complete; NAT gateway fallback was preserved"
    else
        tproxy_warn "rollback finished with warnings; inspect mgate tproxy-debug"
    fi
    return 1
}

tproxy_start_preflight() {
    cmd_tproxy_check

    gateway_have_iptables || { tproxy_save_error "iptables is required"; return 1; }
    tproxy_mangle_table_available || { tproxy_save_error "iptables mangle table is unavailable"; return 1; }
    tproxy_target_available || { tproxy_save_error "TPROXY target is unavailable"; return 1; }
    have ip || { tproxy_save_error "ip command is required"; return 1; }
    ip rule show >/dev/null 2>&1 || { tproxy_save_error "ip rule is unavailable"; return 1; }
    ip route show table all >/dev/null 2>&1 || { tproxy_save_error "ip route is unavailable"; return 1; }
    [ -x "$CORE_BIN" ] || { tproxy_save_error "mihomo binary is missing or not executable: $CORE_BIN"; return 1; }
    [ -f "$CONFIG_FILE" ] || { tproxy_save_error "mihomo config missing: $CONFIG_FILE"; return 1; }

    ap_is_running_healthy || { tproxy_save_error "AP is not healthy; run mgate ap-status"; return 1; }
    interface_exists "$AP_UPSTREAM" || { tproxy_save_error "$AP_UPSTREAM does not exist"; return 1; }
    ip route show default 2>/dev/null | grep -q "dev $AP_UPSTREAM" || { tproxy_save_error "default route does not use $AP_UPSTREAM"; return 1; }
    gateway_rules_active || { tproxy_save_error "NAT gateway fallback is not active; run mgate gateway-start"; return 1; }
}

cmd_tproxy_start() {
    need_root
    ensure_dirs
    ap_load_config
    tproxy_clear_error

    tproxy_info "starting TProxy enable sequence"
    tproxy_info "planned port: $TPROXY_PORT"
    tproxy_info "planned mark: $TPROXY_MARK"
    tproxy_info "planned route table: $TPROXY_ROUTE_TABLE"
    tproxy_info "planned mangle chain: $TPROXY_MANGLE_CHAIN"
    tproxy_info "NAT gateway fallback will be preserved"

    tproxy_start_preflight || return 1

    if ! tproxy_mihomo_running; then
        tproxy_save_error "mihomo is not running; run: mgate start"
        return 1
    fi
    tproxy_ok "mihomo running"

    if tproxy_port_listening; then
        tproxy_ok "mihomo tproxy-port listening: $TPROXY_PORT"
    else
        listen_rc=$?
        if [ "$listen_rc" -eq 2 ]; then
            tproxy_warn "ss/netstat missing; cannot verify tproxy-port listener"
        else
            tproxy_save_error "mihomo tproxy-port $TPROXY_PORT is not listening; ensure config.yaml has tproxy-port: $TPROXY_PORT and restart mihomo"
            return 1
        fi
    fi

    tproxy_info "installing TProxy routing and mangle rules"
    if ! tproxy_add_ip_rule; then
        tproxy_rollback "failed to add ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE"
        return 1
    fi
    tproxy_ok "ip rule active: fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE"

    if ! tproxy_add_route; then
        tproxy_rollback "failed to add local route table $TPROXY_ROUTE_TABLE"
        return 1
    fi
    tproxy_ok "route table active: local 0.0.0.0/0 dev lo table $TPROXY_ROUTE_TABLE"

    if ! tproxy_build_mangle_chain; then
        tproxy_rollback "failed to build mangle chain $TPROXY_MANGLE_CHAIN"
        return 1
    fi
    tproxy_ok "mangle rules installed for $AP_IF -> $TPROXY_PORT"

    if ! tproxy_core_rules_active; then
        tproxy_rollback "post-check failed: TProxy core rules are incomplete"
        return 1
    fi

    tproxy_write_enabled || { tproxy_rollback "failed to write $TPROXY_ENABLED_FILE"; return 1; }
    tproxy_log "TProxy enabled on $AP_IF port $TPROXY_PORT mark $TPROXY_MARK table $TPROXY_ROUTE_TABLE"
    tproxy_ok "TProxy enabled; rollback command: mgate tproxy-stop"
    cmd_tproxy_status
}

cmd_tproxy_stop() {
    need_root
    ensure_dirs
    ap_load_config
    tproxy_info "stopping mgate TProxy rules"

    if tproxy_remove_rules; then
        tproxy_ok "TProxy rules removed"
    else
        tproxy_warn "some TProxy rules may remain; inspect mgate tproxy-debug"
    fi
    rm -f "$TPROXY_ENABLED_FILE" 2>/dev/null || true
    tproxy_log "TProxy stopped; NAT gateway fallback preserved"
    cmd_tproxy_status
    cmd_gateway_status
}

config_mihomo_api_addr() {
    addr="$(sed -n 's/^[[:space:]]*external-controller[[:space:]]*:[[:space:]]*//p' "$CONFIG_FILE" 2>/dev/null | head -1 | tr -d ' ')"
    [ -n "$addr" ] && { printf '%s\n' "$addr"; return 0; }
    printf '127.0.0.1:%s\n' "$DEFAULT_MIHOMO_API_PORT"
}

config_mihomo_api_secret() {
    sed -n 's/^[[:space:]]*secret[[:space:]]*:[[:space:]]*//p' "$CONFIG_FILE" 2>/dev/null | head -1 | tr -d "\"' "
}

mihomo_api_call() {
    method="$1"
    path="$2"
    body="${3:-}"
    addr="$(config_mihomo_api_addr)"
    secret="$(config_mihomo_api_secret)"
    if have curl; then
        if [ -n "$secret" ]; then
            curl -sf -X "$method" "http://$addr$path" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $secret" \
                ${body:+-d "$body"} 2>&1
        else
            curl -sf -X "$method" "http://$addr$path" \
                -H "Content-Type: application/json" \
                ${body:+-d "$body"} 2>&1
        fi
    elif have wget; then
        if [ -n "$secret" ]; then
            wget -qO- --method="$method" \
                --header="Content-Type: application/json" \
                --header="Authorization: Bearer $secret" \
                ${body:+--body-data="$body"} \
                "http://$addr$path" 2>&1
        else
            wget -qO- --method="$method" \
                --header="Content-Type: application/json" \
                ${body:+--body-data="$body"} \
                "http://$addr$path" 2>&1
        fi
    else
        err "curl 或 wget 不可用"; return 1
    fi
}

cmd_tproxy_nodes() {
    addr="$(config_mihomo_api_addr)"
    info "查询 $TPROXY_OUT_GROUP 可用节点（mihomo API: $addr）"
    result="$(mihomo_api_call GET "/proxies/$TPROXY_OUT_GROUP" || true)"
    if [ -z "$result" ]; then
        err "无法连接 mihomo API，请确认 mihomo 正在运行且 external-controller 已配置"
        return 1
    fi
    now="$(printf '%s' "$result" | sed -n 's/.*"now"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [ -n "$now" ] && info "当前选中：$now"
    printf '%s' "$result" | tr ',' '\n' | sed -n 's/.*"\([^"]*\)".*/\1/p' | grep -v '^$' | \
        awk 'p&&/^\[/{exit} /^"all"/{p=1;next} p' || true
    nodes="$(printf '%s' "$result" | sed 's/.*"all"[[:space:]]*:[[:space:]]*\[//' | sed 's/\].*//' | tr ',' '\n' | sed 's/[^"]*"\([^"]*\)".*/\1/' | grep -v '^$')"
    if [ -n "$nodes" ]; then
        step "可用节点"
        printf '%s\n' "$nodes" | while IFS= read -r n; do
            [ -n "$n" ] || continue
            if [ "$n" = "$now" ]; then
                info "* $n（当前）"
            else
                info "  $n"
            fi
        done
    else
        warn "未能解析节点列表，原始响应：$result"
    fi
}

cmd_tproxy_select() {
    node="$1"
    [ -n "$node" ] || die "用法：mgate tproxy-select <节点名>  （用 mgate tproxy-nodes 查看可用节点）"
    addr="$(config_mihomo_api_addr)"
    info "切换 $TPROXY_OUT_GROUP 到节点：$node"
    result="$(mihomo_api_call PUT "/proxies/$TPROXY_OUT_GROUP" "{\"name\":\"$node\"}" || true)"
    if [ -z "$result" ] || printf '%s' "$result" | grep -qi '"message"'; then
        err "切换失败：${result:-无法连接 mihomo API}"
        hint "请确认 mihomo 正在运行，且节点名拼写正确（用 mgate tproxy-nodes 查看）"
        return 1
    fi
    ok "已切换 $TPROXY_OUT_GROUP -> $node（即时生效，无需重启）"
}

tproxy_doctor_section() {
    say ""
    say "[$1]"
}

tproxy_doctor_ok() {
    TPROXY_DOCTOR_OK=$((TPROXY_DOCTOR_OK + 1))
    say "[OK] $*"
}

tproxy_doctor_warn() {
    TPROXY_DOCTOR_WARN=$((TPROXY_DOCTOR_WARN + 1))
    say "[WARN] $*"
}

tproxy_doctor_fail() {
    TPROXY_DOCTOR_FAIL=$((TPROXY_DOCTOR_FAIL + 1))
    say "[ERROR] $*"
}

tproxy_health_ok() {
    TPROXY_HEALTH_OK=$((TPROXY_HEALTH_OK + 1))
    say "[OK] $*"
}

tproxy_health_warn() {
    TPROXY_HEALTH_WARN=$((TPROXY_HEALTH_WARN + 1))
    say "[WARN] $*"
}

tproxy_health_fail() {
    TPROXY_HEALTH_FAIL=$((TPROXY_HEALTH_FAIL + 1))
    say "[ERROR] $*"
}

tproxy_config_out_group_type() {
    [ -f "$CONFIG_FILE" ] || return 1
    awk -v name="$TPROXY_OUT_GROUP" '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_group=0; in_groups=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            in_group=(line == name)
            next
        }
        in_group && /^[[:space:]]*type:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*type:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            print line
            found=1
            exit
        }
        END {exit found ? 0 : 1}
    ' "$CONFIG_FILE" 2>/dev/null
}

tproxy_config_out_group_entry_count() {
    [ -f "$CONFIG_FILE" ] || { printf 'unknown\n'; return 0; }
    awk -v name="$TPROXY_OUT_GROUP" '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1; next}
        /^rules:[[:space:]]*$/ {in_group=0; in_groups=0; in_list=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            in_group=(line == name)
            in_list=0
            next
        }
        in_group && /^[[:space:]]*(proxies|use):[[:space:]]*$/ {in_list=1; next}
        in_group && /^[[:space:]]*[A-Za-z0-9_-]+:[[:space:]]*/ {in_list=0}
        in_group && in_list && /^[[:space:]]*-[[:space:]]*/ {count++}
        END {if (count > 0) print count; else print "unknown"}
    ' "$CONFIG_FILE" 2>/dev/null
}

tproxy_print_out_group_snippet() {
    [ -f "$CONFIG_FILE" ] || { say "config missing: $CONFIG_FILE"; return 0; }
    awk -v name="$TPROXY_OUT_GROUP" '
        /^proxy-groups:[[:space:]]*$/ {in_groups=1}
        /^rules:[[:space:]]*$/ {in_groups=0; in_group=0}
        in_groups && /^[[:space:]]*-[[:space:]]*name:[[:space:]]*/ {
            line=$0
            sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "", line)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", line)
            in_group=(line == name)
        }
        in_group {print}
        $0 ~ "^[[:space:]]*-[[:space:]]*IN-TYPE,TPROXY," name "[[:space:]]*$" {print}
    ' "$CONFIG_FILE" 2>/dev/null
}

tproxy_recent_mihomo_logs() {
    lines="${1:-120}"
    mode="$(detect_service_mode)"
    case "$mode" in
        openwrt)
            if have logread; then
                logread 2>/dev/null | grep -i 'mgate\|mihomo' | tail -n "$lines" 2>/dev/null || true
            elif [ -f "$LOG_FILE" ]; then
                tail -n "$lines" "$LOG_FILE" 2>/dev/null || true
            fi
            ;;
        systemd)
            if have journalctl && [ -e "$SYSTEMD_SERVICE_LINK" ]; then
                journalctl -u mgate.service -n "$lines" --no-pager -o cat 2>/dev/null || true
            elif [ -f "$LOG_FILE" ]; then
                tail -n "$lines" "$LOG_FILE" 2>/dev/null || true
            fi
            ;;
        *)
            [ -f "$LOG_FILE" ] && tail -n "$lines" "$LOG_FILE" 2>/dev/null || true
            ;;
    esac
}

tproxy_recent_error_count() {
    tproxy_recent_mihomo_logs 120 | grep -Ei 'dial|connect|timeout|reject|rejected|fail|failed|error' 2>/dev/null | wc -l | awk '{print $1}'
}

tproxy_recent_error_summary() {
    limit="${1:-20}"
    tproxy_recent_mihomo_logs 120 | grep -Ei 'dial|connect|timeout|reject|rejected|fail|failed|error' 2>/dev/null | tail -n "$limit" 2>/dev/null || true
}

tproxy_skip_rule_for() {
    cidr="$1"
    gateway_have_iptables || return 1
    tproxy_mangle_chain_exists || return 1
    iptables -t mangle -S "$TPROXY_MANGLE_CHAIN" 2>/dev/null | grep -- "-d $cidr" | grep -- '-j RETURN' >/dev/null 2>&1
}

tproxy_prerouting_hook_only_ap() {
    gateway_have_iptables || return 1
    refs="$(iptables -t mangle -S PREROUTING 2>/dev/null | grep -- "-j $TPROXY_MANGLE_CHAIN" || true)"
    [ -n "$refs" ] || return 1
    bad_refs="$(printf '%s\n' "$refs" | grep -v -- "-i $AP_IF" || true)"
    [ -z "$bad_refs" ]
}

tproxy_suspicious_mangle_rules() {
    gateway_have_iptables || return 0
    iptables -t mangle -S 2>/dev/null | grep -E 'TPROXY|tproxy' | grep -v "MGATE" || true
}

tproxy_mangle_counter_total() {
    gateway_have_iptables || { printf 'unknown\n'; return 0; }
    iptables -t mangle -L "$TPROXY_MANGLE_CHAIN" -n -v -x 2>/dev/null | awk '
        NR > 2 && $1 ~ /^[0-9]+$/ {pkts += $1; bytes += $2}
        END {print pkts + 0, bytes + 0}
    '
}

tproxy_tproxy_counter_line() {
    proto="$1"
    gateway_have_iptables || { printf 'unknown\n'; return 0; }
    iptables -t mangle -L "$TPROXY_MANGLE_CHAIN" -n -v -x 2>/dev/null | awk -v proto="$proto" '
        $3 == "TPROXY" && $4 == proto {print $1, $2; found=1; exit}
        END {if (!found) print "0 0"}
    '
}

tproxy_counters_growing() {
    before="$(tproxy_mangle_counter_total | awk '{print $1}')"
    case "$before" in ''|unknown) return 2 ;; esac
    sleep 2
    after="$(tproxy_mangle_counter_total | awk '{print $1}')"
    case "$after" in ''|unknown) return 2 ;; esac
    [ "$after" -gt "$before" ] 2>/dev/null
}

tproxy_print_nat_counters() {
    if ! gateway_have_iptables; then
        say "iptables missing"
        return 0
    fi
    say "nat chain $GATEWAY_NAT_CHAIN:"
    iptables -t nat -L "$GATEWAY_NAT_CHAIN" -n -v -x 2>/dev/null | sed -n '1,5p' || say "cannot read $GATEWAY_NAT_CHAIN"
    say "filter chain $GATEWAY_FORWARD_CHAIN:"
    iptables -L "$GATEWAY_FORWARD_CHAIN" -n -v -x 2>/dev/null | sed -n '1,7p' || say "cannot read $GATEWAY_FORWARD_CHAIN"
}

tproxy_dns_safety_check() {
    if [ -f "$AP_DNSMASQ_CONF" ]; then
        listen_addr="$(sed -n 's/^listen-address=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        if [ "$listen_addr" = "$AP_IPADDR" ]; then
            tproxy_doctor_ok "dnsmasq listens on $AP_IPADDR"
        else
            tproxy_doctor_fail "dnsmasq listen-address is ${listen_addr:-missing}, expected $AP_IPADDR"
        fi
        dns_opt="$(sed -n 's/^dhcp-option=6,//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        if [ "$dns_opt" = "$AP_IPADDR" ]; then
            tproxy_doctor_ok "DHCP DNS option points to $AP_IPADDR"
        else
            tproxy_doctor_fail "DHCP DNS option is ${dns_opt:-missing}, expected $AP_IPADDR"
        fi
    else
        tproxy_doctor_fail "dnsmasq config missing: $AP_DNSMASQ_CONF"
    fi
}

cmd_tproxy_health() {
    ap_load_config
    TPROXY_HEALTH_OK=0
    TPROXY_HEALTH_WARN=0
    TPROXY_HEALTH_FAIL=0

    tproxy_port="$(tproxy_mihomo_port || true)"
    [ -n "$tproxy_port" ] || tproxy_port="none"
    mangle_state="$(tproxy_state_mangle)"
    rule_state="$(tproxy_state_ip_rule)"
    route_state="$(tproxy_state_route_table)"
    enabled="$(tproxy_enabled_state "$mangle_state" "$rule_state" "$route_state" "$tproxy_port")"
    fallback="$(tproxy_gateway_fallback_state)"
    ap_health="no"
    ap_is_running_healthy && ap_health="yes"
    mihomo_health="no"
    tproxy_mihomo_running && mihomo_health="yes"

    tproxy_doctor_section "summary"
    say "[INFO] mgate version: $MGATE_VERSION"
    say "[INFO] tproxy enabled: $enabled"
    say "[INFO] gateway fallback active: $fallback"
    say "[INFO] ap healthy: $ap_health"
    say "[INFO] mihomo running: $mihomo_health"
    if tproxy_is_root; then
        say "[INFO] root: yes"
    else
        tproxy_health_warn "root: no; some iptables/ip diagnostics may be incomplete"
    fi
    if [ "$enabled" = "no" ]; then
        tproxy_health_warn "TProxy is disabled; NAT fallback should handle AP clients"
    elif [ "$enabled" = "partial" ]; then
        tproxy_health_fail "TProxy state is partial; possible leftover rules"
    fi

    tproxy_doctor_section "tproxy path"
    if tproxy_mangle_chain_exists; then tproxy_health_ok "$TPROXY_MANGLE_CHAIN chain exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "$TPROXY_MANGLE_CHAIN chain exists: no" || tproxy_health_warn "$TPROXY_MANGLE_CHAIN chain exists: no"; fi
    if tproxy_prerouting_hook_exists; then tproxy_health_ok "PREROUTING hook exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "PREROUTING hook exists: no" || tproxy_health_warn "PREROUTING hook exists: no"; fi
    if tproxy_chain_has_tproxy_rule tcp; then tproxy_health_ok "TCP TPROXY rule exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "TCP TPROXY rule exists: no" || tproxy_health_warn "TCP TPROXY rule exists: no"; fi
    if tproxy_chain_has_tproxy_rule udp; then tproxy_health_ok "UDP TPROXY rule exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "UDP TPROXY rule exists: no" || tproxy_health_warn "UDP TPROXY rule exists: no"; fi
    if tproxy_ip_rule_present; then tproxy_health_ok "ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE exists: no" || tproxy_health_warn "ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE exists: no"; fi
    if tproxy_route_local_present; then tproxy_health_ok "route table $TPROXY_ROUTE_TABLE local route exists: yes"; else [ "$enabled" = "yes" ] && tproxy_health_fail "route table $TPROXY_ROUTE_TABLE local route exists: no" || tproxy_health_warn "route table $TPROXY_ROUTE_TABLE local route exists: no"; fi
    say "[INFO] tproxy-port: $tproxy_port"
    if [ "$tproxy_port" = "$TPROXY_PORT" ]; then
        if tproxy_port_listening; then
            tproxy_health_ok "tproxy-port listening: yes"
        else
            listen_rc=$?
            if [ "$listen_rc" -eq 2 ]; then
                tproxy_health_warn "tproxy-port listening: unknown; ss/netstat missing"
            else
                tproxy_health_fail "tproxy-port listening: no"
            fi
        fi
    else
        [ "$enabled" = "yes" ] && tproxy_health_fail "tproxy-port is $tproxy_port, expected $TPROXY_PORT" || tproxy_health_warn "tproxy-port is $tproxy_port"
    fi

    tproxy_doctor_section "counters"
    total_counter="$(tproxy_mangle_counter_total)"
    tcp_counter="$(tproxy_tproxy_counter_line tcp)"
    udp_counter="$(tproxy_tproxy_counter_line udp)"
    say "[INFO] $TPROXY_MANGLE_CHAIN total packets/bytes: $total_counter"
    say "[INFO] TCP TPROXY packets/bytes: $tcp_counter"
    say "[INFO] UDP TPROXY packets/bytes: $udp_counter"
    tproxy_print_nat_counters
    if [ "$enabled" = "yes" ]; then
        if tproxy_counters_growing; then
            tproxy_health_ok "counters growing: yes"
        else
            grow_rc=$?
            if [ "$grow_rc" -eq 2 ]; then
                tproxy_health_warn "counters growing: unknown"
            else
                tproxy_health_warn "counters growing: no; no recent AP client traffic observed"
            fi
        fi
    else
        say "[INFO] counters growing: not sampled because TProxy is disabled"
    fi

    tproxy_doctor_section "mihomo"
    if [ -f "$CONFIG_FILE" ]; then tproxy_health_ok "config exists: yes"; else [ "$enabled" = "yes" ] || [ "$enabled" = "partial" ] && tproxy_health_fail "config exists: no" || tproxy_health_warn "config exists: no"; fi
    [ "$tproxy_port" = "$TPROXY_PORT" ] && tproxy_health_ok "tproxy-port exists: yes" || tproxy_health_warn "tproxy-port exists: no"
    if tproxy_config_has_out_group; then
        tproxy_health_ok "$TPROXY_OUT_GROUP exists: yes"
        out_type="$(tproxy_config_out_group_type || true)"
        [ -n "$out_type" ] || out_type="unknown"
        case "$out_type" in
            url-test|select|fallback) tproxy_health_ok "$TPROXY_OUT_GROUP type: $out_type" ;;
            *) tproxy_health_warn "$TPROXY_OUT_GROUP type: $out_type" ;;
        esac
        say "[INFO] $TPROXY_OUT_GROUP proxies/use entries: $(tproxy_config_out_group_entry_count)"
    else
        [ "$enabled" = "yes" ] && tproxy_health_fail "$TPROXY_OUT_GROUP exists: no" || tproxy_health_warn "$TPROXY_OUT_GROUP exists: no"
        say "[INFO] $TPROXY_OUT_GROUP type: unknown"
        say "[INFO] $TPROXY_OUT_GROUP proxies/use entries: unknown"
    fi
    err_count="$(tproxy_recent_error_count)"
    say "[INFO] recent mihomo dial/connect/timeout/reject/fail errors: ${err_count:-0}"
    if [ "${err_count:-0}" -gt 0 ] 2>/dev/null; then
        tproxy_health_warn "recent mihomo proxy errors found"
        tproxy_recent_error_summary 20
    elif [ -f "$LOG_FILE" ] || have journalctl || have logread; then
        tproxy_health_ok "recent mihomo proxy errors: none"
    else
        tproxy_health_warn "mihomo log unavailable"
    fi

    tproxy_doctor_section "dns safety"
    if ap_pid_running "$AP_DNSMASQ_PID_FILE"; then tproxy_health_ok "dnsmasq running: yes"; else [ "$enabled" = "yes" ] || [ "$enabled" = "partial" ] && tproxy_health_fail "dnsmasq running: no" || tproxy_health_warn "dnsmasq running: no"; fi
    if [ -f "$AP_DNSMASQ_CONF" ]; then
        listen_addr="$(sed -n 's/^listen-address=//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        dns_opt="$(sed -n 's/^dhcp-option=6,//p' "$AP_DNSMASQ_CONF" 2>/dev/null | tail -n 1)"
        [ "$listen_addr" = "$AP_IPADDR" ] && tproxy_health_ok "dnsmasq listens on $AP_IPADDR:53: yes" || tproxy_health_warn "dnsmasq listens on $AP_IPADDR:53: no"
        [ "$dns_opt" = "$AP_IPADDR" ] && tproxy_health_ok "DHCP DNS option points to $AP_IPADDR: yes" || tproxy_health_warn "DHCP DNS option points to $AP_IPADDR: no"
    else
        tproxy_health_warn "dnsmasq config missing: $AP_DNSMASQ_CONF"
    fi
    tproxy_skip_rule_for "$AP_IPADDR/32" && tproxy_health_ok "TProxy rules skip $AP_IPADDR: yes" || tproxy_health_warn "TProxy rules skip $AP_IPADDR: no"
    ap_cidr="$(ap_network_cidr)"
    tproxy_skip_rule_for "$ap_cidr" && tproxy_health_ok "TProxy rules skip $ap_cidr: yes" || tproxy_health_warn "TProxy rules skip $ap_cidr: no"

    tproxy_doctor_section "leak checks"
    if tproxy_socket_bypass_rule_present; then
        if [ "$TPROXY_SOCKET_BYPASS" = "1" ]; then
            tproxy_health_warn "socket bypass rule present: yes; enabled by MGATE_TPROXY_SOCKET_BYPASS=1"
        else
            tproxy_health_fail "socket bypass rule present: yes; AP TCP traffic may leak to NAT"
        fi
    else
        tproxy_health_ok "socket bypass rule present: no"
    fi
    tproxy_prerouting_hook_only_ap && tproxy_health_ok "TProxy chain only hooked from -i $AP_IF: yes" || tproxy_health_warn "TProxy chain only hooked from -i $AP_IF: no"
    suspicious="$(tproxy_suspicious_mangle_rules)"
    if [ -n "$suspicious" ]; then
        tproxy_health_warn "non-mgate TProxy/mangle rules found"
        printf '%s\n' "$suspicious"
    else
        tproxy_health_ok "non-mgate TProxy/mangle rules found: no"
    fi

    tproxy_doctor_section "fallback"
    gateway_rules_active && tproxy_health_ok "NAT fallback active: yes" || tproxy_health_warn "NAT fallback active: no"
    [ "$(gateway_ip_forward_value)" = "1" ] && tproxy_health_ok "IPv4 forwarding: yes" || tproxy_health_warn "IPv4 forwarding: no"
    subnet="$(gateway_subnet)"
    if gateway_have_iptables; then
        iptables -C "$GATEWAY_FORWARD_CHAIN" -i "$AP_IF" -o "$AP_UPSTREAM" -s "$subnet" -j ACCEPT >/dev/null 2>&1 && tproxy_health_ok "AP -> $AP_UPSTREAM forward rule: yes" || tproxy_health_warn "AP -> $AP_UPSTREAM forward rule: no"
        iptables -t nat -C "$GATEWAY_NAT_CHAIN" -s "$subnet" -o "$AP_UPSTREAM" -j MASQUERADE >/dev/null 2>&1 && tproxy_health_ok "MASQUERADE $subnet -> $AP_UPSTREAM: yes" || tproxy_health_warn "MASQUERADE $subnet -> $AP_UPSTREAM: no"
    else
        tproxy_health_warn "iptables missing; cannot inspect NAT fallback rules"
    fi

    if [ "$enabled" = "no" ]; then
        final_health="disabled"
    elif [ "$enabled" = "unknown" ]; then
        final_health="degraded"
    elif [ "$TPROXY_HEALTH_FAIL" -gt 0 ]; then
        final_health="broken"
    elif [ "$TPROXY_HEALTH_WARN" -gt 0 ]; then
        final_health="degraded"
    else
        final_health="healthy"
    fi
    tproxy_doctor_section "summary counts"
    say "[INFO] final health: $final_health"
    say "[INFO] tproxy health summary: OK=$TPROXY_HEALTH_OK WARN=$TPROXY_HEALTH_WARN ERROR=$TPROXY_HEALTH_FAIL"
}

cmd_tproxy_doctor() {
    ap_load_config
    TPROXY_DOCTOR_OK=0
    TPROXY_DOCTOR_WARN=0
    TPROXY_DOCTOR_FAIL=0

    tproxy_doctor_section "summary"
    say "[INFO] mgate version: $MGATE_VERSION"
    say "[INFO] tproxy enabled: $(tproxy_enabled_state "$(tproxy_state_mangle)" "$(tproxy_state_ip_rule)" "$(tproxy_state_route_table)" "$(tproxy_mihomo_port 2>/dev/null || echo none)")"
    say "[INFO] ap interface: $AP_IF"
    say "[INFO] upstream interface: $AP_UPSTREAM"
    say "[INFO] tproxy port: $TPROXY_PORT"
    say "[INFO] mark: $TPROXY_MARK"
    say "[INFO] route table: $TPROXY_ROUTE_TABLE"

    tproxy_doctor_section "AP baseline"
    interface_exists "$AP_IF" && tproxy_doctor_ok "$AP_IF exists" || tproxy_doctor_fail "$AP_IF does not exist"
    ap_link="$(ap_iface_link_state "$AP_IF")"
    [ "$ap_link" = "up" ] && tproxy_doctor_ok "$AP_IF link is up" || tproxy_doctor_fail "$AP_IF link is $ap_link"
    ap_ip="$(ap_ipv4_addr "$AP_IF" || true)"
    [ -n "$ap_ip" ] && tproxy_doctor_ok "$AP_IF ip: $ap_ip" || tproxy_doctor_fail "$AP_IF has no IPv4 address"
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && tproxy_doctor_ok "hostapd running: $(sed -n '1p' "$AP_HOSTAPD_PID_FILE" 2>/dev/null)" || tproxy_doctor_fail "hostapd is not running"
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && tproxy_doctor_ok "dnsmasq running: $(sed -n '1p' "$AP_DNSMASQ_PID_FILE" 2>/dev/null)" || tproxy_doctor_fail "dnsmasq is not running"

    tproxy_doctor_section "gateway fallback"
    gateway_rules_active && tproxy_doctor_ok "NAT active: yes" || tproxy_doctor_fail "NAT active: no"
    [ "$(gateway_ip_forward_value)" = "1" ] && tproxy_doctor_ok "IPv4 forwarding enabled" || tproxy_doctor_warn "IPv4 forwarding is $(gateway_ip_forward_value)"
    subnet="$(gateway_subnet)"
    if gateway_have_iptables; then
        iptables -t nat -C POSTROUTING -j "$GATEWAY_NAT_CHAIN" >/dev/null 2>&1 && tproxy_doctor_ok "POSTROUTING fallback jump exists" || tproxy_doctor_fail "POSTROUTING fallback jump missing"
        iptables -C FORWARD -j "$GATEWAY_FORWARD_CHAIN" >/dev/null 2>&1 && tproxy_doctor_ok "FORWARD fallback jump exists" || tproxy_doctor_fail "FORWARD fallback jump missing"
        iptables -t nat -C "$GATEWAY_NAT_CHAIN" -s "$subnet" -o "$AP_UPSTREAM" -j MASQUERADE >/dev/null 2>&1 && tproxy_doctor_ok "MASQUERADE $subnet -> $AP_UPSTREAM exists" || tproxy_doctor_fail "MASQUERADE rule missing"
    else
        tproxy_doctor_fail "iptables missing; cannot inspect NAT fallback"
    fi

    tproxy_doctor_section "mihomo"
    [ -x "$CORE_BIN" ] && tproxy_doctor_ok "mihomo binary exists: $CORE_BIN" || tproxy_doctor_fail "mihomo binary missing: $CORE_BIN"
    tproxy_mihomo_running && tproxy_doctor_ok "mihomo running" || tproxy_doctor_fail "mihomo is not running"
    [ -f "$CONFIG_FILE" ] && tproxy_doctor_ok "mihomo config exists: $CONFIG_FILE" || tproxy_doctor_fail "mihomo config missing: $CONFIG_FILE"
    current_port="$(tproxy_mihomo_port || true)"
    [ -n "$current_port" ] && tproxy_doctor_ok "mihomo tproxy-port: $current_port" || tproxy_doctor_fail "mihomo tproxy-port: none"
    tproxy_config_bool_true allow-lan && tproxy_doctor_ok "allow-lan enabled" || tproxy_doctor_fail "allow-lan is not enabled for transparent AP clients"
    bind_addr="$(tproxy_config_value bind-address || true)"
    tproxy_config_bind_ok && tproxy_doctor_ok "bind-address accepts LAN traffic: ${bind_addr:-missing}" || tproxy_doctor_fail "bind-address does not accept LAN traffic: ${bind_addr:-missing}"
    if tproxy_config_has_out_group; then
        tproxy_doctor_ok "transparent selector exists: $TPROXY_OUT_GROUP"
        out_type="$(tproxy_config_out_group_type || true)"
        [ -n "$out_type" ] || out_type="unknown"
        case "$out_type" in
            url-test|select|fallback) tproxy_doctor_ok "$TPROXY_OUT_GROUP type: $out_type" ;;
            *) tproxy_doctor_warn "$TPROXY_OUT_GROUP type: $out_type" ;;
        esac
    else
        tproxy_doctor_fail "transparent selector missing: $TPROXY_OUT_GROUP"
    fi
    tproxy_config_has_in_type_rule && tproxy_doctor_ok "IN-TYPE TPROXY rule routes to $TPROXY_OUT_GROUP" || tproxy_doctor_fail "IN-TYPE TPROXY rule missing; traffic may hit MATCH,REJECT"
    if tproxy_port_listening; then
        tproxy_doctor_ok "tproxy-port listening: $TPROXY_PORT"
    else
        listen_rc=$?
        if [ "$listen_rc" -eq 2 ]; then
            tproxy_doctor_warn "cannot verify tproxy-port listener; ss/netstat missing"
        else
            tproxy_doctor_fail "tproxy-port not listening: $TPROXY_PORT"
        fi
    fi

    tproxy_doctor_section "routing"
    tproxy_ip_rule_present && tproxy_doctor_ok "ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE exists" || tproxy_doctor_fail "ip rule fwmark $TPROXY_MARK lookup $TPROXY_ROUTE_TABLE missing"
    tproxy_route_local_present && tproxy_doctor_ok "route table $TPROXY_ROUTE_TABLE local route exists" || tproxy_doctor_fail "route table $TPROXY_ROUTE_TABLE local route missing"

    tproxy_doctor_section "mangle"
    tproxy_mangle_chain_exists && tproxy_doctor_ok "chain $TPROXY_MANGLE_CHAIN exists" || tproxy_doctor_fail "chain $TPROXY_MANGLE_CHAIN missing"
    tproxy_prerouting_hook_exists && tproxy_doctor_ok "PREROUTING hook exists" || tproxy_doctor_fail "PREROUTING hook missing"
    tproxy_prerouting_hook_only_ap && tproxy_doctor_ok "PREROUTING hook only uses -i $AP_IF" || tproxy_doctor_warn "PREROUTING hook may not be limited to -i $AP_IF"
    tproxy_chain_has_tproxy_rule tcp && tproxy_doctor_ok "TCP TPROXY rule exists" || tproxy_doctor_fail "TCP TPROXY rule missing"
    tproxy_chain_has_tproxy_rule udp && tproxy_doctor_ok "UDP TPROXY rule exists" || tproxy_doctor_fail "UDP TPROXY rule missing"
    tproxy_skip_rules_complete && tproxy_doctor_ok "reserved/local skip rules exist" || tproxy_doctor_fail "reserved/local skip rules incomplete"
    tproxy_skip_rule_for "$AP_IPADDR/32" && tproxy_doctor_ok "skip rule exists for $AP_IPADDR/32" || tproxy_doctor_fail "skip rule missing for $AP_IPADDR/32"
    ap_cidr="$(ap_network_cidr)"
    tproxy_skip_rule_for "$ap_cidr" && tproxy_doctor_ok "skip rule exists for $ap_cidr" || tproxy_doctor_fail "skip rule missing for $ap_cidr"
    if tproxy_socket_bypass_rule_present; then
        if [ "$TPROXY_SOCKET_BYPASS" = "1" ]; then
            tproxy_doctor_warn "socket bypass rule active by MGATE_TPROXY_SOCKET_BYPASS=1"
        else
            tproxy_doctor_fail "socket bypass rule active; AP TCP traffic may leak to NAT instead of TProxy"
        fi
    else
        tproxy_doctor_ok "socket bypass rule absent"
    fi

    tproxy_doctor_section "packet counters"
    if gateway_have_iptables && iptables -t mangle -L "$TPROXY_MANGLE_CHAIN" -n -v >/dev/null 2>&1; then
        tproxy_doctor_ok "can read $TPROXY_MANGLE_CHAIN counters"
        iptables -t mangle -L "$TPROXY_MANGLE_CHAIN" -n -v 2>/dev/null | sed -n '1,30p'
    else
        tproxy_doctor_warn "cannot read $TPROXY_MANGLE_CHAIN counters"
    fi
    gateway_doctor_chain_counters

    tproxy_doctor_section "DNS safety"
    tproxy_dns_safety_check

    tproxy_doctor_section "recent mihomo errors"
    err_count="$(tproxy_recent_error_count)"
    if [ "${err_count:-0}" -gt 0 ] 2>/dev/null; then
        tproxy_doctor_warn "recent dial/connect/timeout/reject/fail errors: $err_count"
        tproxy_recent_error_summary 10
    else
        tproxy_doctor_ok "recent dial/connect/timeout/reject/fail errors: 0"
    fi

    tproxy_doctor_section "next steps"
    if [ "$TPROXY_DOCTOR_FAIL" -gt 0 ]; then
        say "[INFO] run: mgate tproxy-debug"
        say "[INFO] fallback: mgate tproxy-stop"
    elif [ "$TPROXY_DOCTOR_WARN" -gt 0 ]; then
        say "[INFO] run: mgate tproxy-debug if clients cannot browse"
        say "[INFO] check subscription nodes if $TPROXY_OUT_GROUP has no healthy proxy"
    else
        say "[INFO] no action needed; keep NAT fallback available"
    fi

    say ""
    say "[INFO] tproxy doctor summary: OK=$TPROXY_DOCTOR_OK WARN=$TPROXY_DOCTOR_WARN ERROR=$TPROXY_DOCTOR_FAIL"
    if [ "$TPROXY_DOCTOR_FAIL" -gt 0 ]; then
        say "[ERROR] TProxy baseline is not healthy"
        return 1
    fi
    if [ "$TPROXY_DOCTOR_WARN" -gt 0 ]; then
        say "[WARN] TProxy baseline works with warnings"
        return 0
    fi
    say "[OK] TProxy baseline is healthy"
}

cmd_tproxy_debug() {
    ap_load_config
    say ""
    say "[tproxy-health]"
    cmd_tproxy_health
    say ""
    say "[tproxy-status]"
    cmd_tproxy_status
    say ""
    say "[tproxy-check]"
    cmd_tproxy_check
    say ""
    say "[mihomo transparent config]"
    if [ -f "$CONFIG_FILE" ]; then
        grep -n -e '^[[:space:]]*allow-lan[[:space:]]*:' \
            -e '^[[:space:]]*bind-address[[:space:]]*:' \
            -e '^[[:space:]]*tproxy-port[[:space:]]*:' \
            -e "^[[:space:]]*-[[:space:]]*name:[[:space:]]*[\"']*$TPROXY_OUT_GROUP[\"']*[[:space:]]*$" \
            -e "^[[:space:]]*-[[:space:]]*IN-TYPE,TPROXY,$TPROXY_OUT_GROUP[[:space:]]*$" \
            -e '^[[:space:]]*-[[:space:]]*MATCH,REJECT[[:space:]]*$' \
            "$CONFIG_FILE" 2>/dev/null || true
    else
        say "config missing: $CONFIG_FILE"
    fi
    say ""
    say "[$TPROXY_OUT_GROUP config snippet]"
    tproxy_print_out_group_snippet
    say ""
    say "[ip rule]"
    if have ip; then ip rule show 2>/dev/null || true; else say "ip command missing"; fi
    say ""
    say "[route table $TPROXY_ROUTE_TABLE]"
    if have ip; then ip route show table "$TPROXY_ROUTE_TABLE" 2>/dev/null || true; else say "ip command missing"; fi
    say ""
    say "[iptables-save MGATE/TProxy lines]"
    if have iptables-save; then iptables-save 2>/dev/null | grep -E 'MGATE|TPROXY|tproxy' || true; else say "iptables-save missing"; fi
    say ""
    say "[mangle rules]"
    if gateway_have_iptables; then iptables -t mangle -S 2>/dev/null || true; else say "iptables missing"; fi
    say ""
    say "[mangle counters]"
    if gateway_have_iptables; then iptables -t mangle -L "$TPROXY_MANGLE_CHAIN" -n -v --line-numbers 2>/dev/null || true; else say "iptables missing"; fi
    say ""
    say "[nat fallback counters]"
    if gateway_have_iptables; then iptables -t nat -L "$GATEWAY_NAT_CHAIN" -n -v 2>/dev/null || true; else say "iptables missing"; fi
    say ""
    say "[forward fallback counters]"
    if gateway_have_iptables; then iptables -t filter -L "$GATEWAY_FORWARD_CHAIN" -n -v 2>/dev/null || true; else say "iptables missing"; fi
    say ""
    say "[gateway-status]"
    cmd_gateway_status
    say ""
    say "[ap-status]"
    cmd_ap_status
    say ""
    say "[sub-status]"
    cmd_sub_status
    say ""
    say "[sub-nodes first 30 lines]"
    cmd_sub_nodes 2>/dev/null | sed -n '1,30p' || true
    say ""
    say "[sub-unmatched first 30 lines]"
    cmd_sub_unmatched 2>/dev/null | sed -n '1,30p' || true
    say ""
    say "[tproxy log]"
    if [ -f "$TPROXY_LOG_FILE" ]; then tail -120 "$TPROXY_LOG_FILE" 2>/dev/null || sed -n '1,120p' "$TPROXY_LOG_FILE" 2>/dev/null; else say "no tproxy log"; fi
    say ""
    say "[mihomo log]"
    tproxy_recent_mihomo_logs 120 || say "no mihomo log"
    say ""
    say "[last error]"
    if [ -f "$TPROXY_LAST_ERROR_FILE" ]; then sed -n '1,120p' "$TPROXY_LAST_ERROR_FILE" 2>/dev/null; else say "no last error"; fi
}
# -----------------------------
# Machine-readable read-only JSON status
# -----------------------------
json_escape() {
    awk '
        BEGIN {ORS=""}
        {
            if (NR > 1) printf "\\n"
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\t/, "\\t")
            gsub(/\r/, "\\r")
            printf "%s", $0
        }
    '
}

json_string() {
    printf '"'
    printf '%s' "$1" | json_escape
    printf '"'
}

json_string_or_null() {
    if [ -n "${1:-}" ]; then
        json_string "$1"
    else
        printf 'null'
    fi
}

json_bool() {
    case "${1:-}" in
        1|yes|true|on) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

json_tri_bool() {
    case "${1:-}" in
        1|yes|true|on) printf 'true' ;;
        0|no|false|off) printf 'false' ;;
        *) printf 'null' ;;
    esac
}

json_number_or_null() {
    case "${1:-}" in
        ''|*[!0-9]*) printf 'null' ;;
        *) printf '%s' "$1" ;;
    esac
}

json_root_limited() {
    if tproxy_is_root; then printf 'false'; else printf 'true'; fi
}

json_root_warnings() {
    if tproxy_is_root; then
        printf '[]'
    else
        printf '['
        json_string 'some checks require root'
        printf ']'
    fi
}

json_yes_no_lit() {
    if "$@"; then printf 'true'; else printf 'false'; fi
}

json_collect_ap_state() {
    ap_load_config
    JSON_AP_LIMITED="$(json_root_limited)"
    JSON_AP_CONFIG_EXISTS=false
    [ -f "$AP_CONFIG_FILE" ] && JSON_AP_CONFIG_EXISTS=true
    JSON_AP_EXISTS=false
    interface_exists "$AP_IF" && JSON_AP_EXISTS=true
    JSON_AP_LINK="$(ap_iface_link_state "$AP_IF" 2>/dev/null || printf 'unknown')"
    JSON_AP_UP=false
    [ "$JSON_AP_LINK" = "up" ] && JSON_AP_UP=true
    JSON_AP_IP="$(ap_ipv4_addr "$AP_IF" 2>/dev/null || true)"
    JSON_AP_TYPE="$(ap_iface_type "$AP_IF" 2>/dev/null || true)"
    [ -n "$JSON_AP_TYPE" ] || JSON_AP_TYPE="unknown"
    JSON_AP_HOSTAPD_RUNNING=false
    ap_pid_running "$AP_HOSTAPD_PID_FILE" && JSON_AP_HOSTAPD_RUNNING=true
    JSON_AP_DNSMASQ_RUNNING=false
    ap_pid_running "$AP_DNSMASQ_PID_FILE" && JSON_AP_DNSMASQ_RUNNING=true
    JSON_AP_HEALTHY=false
    ap_is_running_healthy >/dev/null 2>&1 && JSON_AP_HEALTHY=true
    if [ "$JSON_AP_HEALTHY" = "true" ]; then
        JSON_AP_RUNNING=true
    else
        JSON_AP_RUNNING=false
    fi
}

json_collect_gateway_state() {
    ap_load_config
    JSON_GATEWAY_LIMITED="$(json_root_limited)"
    JSON_GATEWAY_IPV4_VALUE="$(gateway_ip_forward_value 2>/dev/null || printf 'unknown')"
    case "$JSON_GATEWAY_IPV4_VALUE" in
        1) JSON_GATEWAY_IPV4_FORWARDING=true ;;
        0) JSON_GATEWAY_IPV4_FORWARDING=false ;;
        *) JSON_GATEWAY_IPV4_FORWARDING=null ;;
    esac
    JSON_GATEWAY_NAT_ACTIVE=null
    if gateway_rules_active; then
        JSON_GATEWAY_NAT_ACTIVE=true
    elif gateway_have_iptables && tproxy_is_root; then
        JSON_GATEWAY_NAT_ACTIVE=false
    fi
    JSON_GATEWAY_FALLBACK_ACTIVE="$JSON_GATEWAY_NAT_ACTIVE"
    if gateway_have_iptables; then JSON_GATEWAY_BACKEND="iptables"; else JSON_GATEWAY_BACKEND="unknown"; fi
    JSON_GATEWAY_AP_HEALTHY=false
    ap_is_running_healthy >/dev/null 2>&1 && JSON_GATEWAY_AP_HEALTHY=true
    JSON_GATEWAY_TPROXY_STATE="$(gateway_transparent_proxy_state 2>/dev/null || printf 'unknown')"
    case "$JSON_GATEWAY_TPROXY_STATE" in
        yes|partial) JSON_GATEWAY_MODE="tproxy" ;;
        *)
            if [ "$JSON_GATEWAY_NAT_ACTIVE" = "true" ]; then
                JSON_GATEWAY_MODE="nat"
            else
                JSON_GATEWAY_MODE="unknown"
            fi
            ;;
    esac
    JSON_GATEWAY_HEALTHY=false
    if [ "$JSON_GATEWAY_AP_HEALTHY" = "true" ] && [ "$JSON_GATEWAY_IPV4_FORWARDING" = "true" ] && [ "$JSON_GATEWAY_NAT_ACTIVE" = "true" ]; then
        JSON_GATEWAY_HEALTHY=true
    fi
}

json_collect_tproxy_state() {
    ap_load_config
    JSON_TPROXY_LIMITED="$(json_root_limited)"
    JSON_TPROXY_PORT_CONFIGURED_VALUE="$(tproxy_mihomo_port 2>/dev/null || true)"
    [ -n "$JSON_TPROXY_PORT_CONFIGURED_VALUE" ] || JSON_TPROXY_PORT_CONFIGURED_VALUE="none"
    JSON_TPROXY_MANGLE_STATE="$(tproxy_state_mangle 2>/dev/null || printf 'unknown')"
    JSON_TPROXY_RULE_STATE="$(tproxy_state_ip_rule 2>/dev/null || printf 'unknown')"
    JSON_TPROXY_ROUTE_STATE="$(tproxy_state_route_table 2>/dev/null || printf 'unknown')"
    JSON_TPROXY_ENABLED_RAW="$(tproxy_enabled_state "$JSON_TPROXY_MANGLE_STATE" "$JSON_TPROXY_RULE_STATE" "$JSON_TPROXY_ROUTE_STATE" "$JSON_TPROXY_PORT_CONFIGURED_VALUE")"
    case "$JSON_TPROXY_ENABLED_RAW" in
        yes) JSON_TPROXY_STATE="enabled"; JSON_TPROXY_ENABLED=true ;;
        no) JSON_TPROXY_STATE="disabled"; JSON_TPROXY_ENABLED=false ;;
        partial) JSON_TPROXY_STATE="partial"; JSON_TPROXY_ENABLED=false ;;
        *) JSON_TPROXY_STATE="unknown"; JSON_TPROXY_ENABLED=false ;;
    esac
    JSON_TPROXY_MIHOMO_RUNNING=false
    tproxy_mihomo_running >/dev/null 2>&1 && JSON_TPROXY_MIHOMO_RUNNING=true
    JSON_TPROXY_PORT_CONFIGURED=false
    [ "$JSON_TPROXY_PORT_CONFIGURED_VALUE" = "$TPROXY_PORT" ] && JSON_TPROXY_PORT_CONFIGURED=true
    JSON_TPROXY_PORT_LISTENING=null
    tproxy_port_listening >/dev/null 2>&1
    case "$?" in
        0) JSON_TPROXY_PORT_LISTENING=true ;;
        1) JSON_TPROXY_PORT_LISTENING=false ;;
        *) JSON_TPROXY_PORT_LISTENING=null ;;
    esac
    JSON_TPROXY_OUT_EXISTS=false
    tproxy_config_has_out_group >/dev/null 2>&1 && JSON_TPROXY_OUT_EXISTS=true
    JSON_TPROXY_OUT_TYPE="$(tproxy_config_out_group_type 2>/dev/null || printf 'unknown')"
    [ -n "$JSON_TPROXY_OUT_TYPE" ] || JSON_TPROXY_OUT_TYPE="unknown"
    JSON_TPROXY_MANGLE_CHAIN_EXISTS=false
    tproxy_mangle_chain_exists && JSON_TPROXY_MANGLE_CHAIN_EXISTS=true
    JSON_TPROXY_PREROUTING_HOOK_EXISTS=false
    tproxy_prerouting_hook_exists && JSON_TPROXY_PREROUTING_HOOK_EXISTS=true
    JSON_TPROXY_IP_RULE_EXISTS=false
    tproxy_ip_rule_present && JSON_TPROXY_IP_RULE_EXISTS=true
    JSON_TPROXY_ROUTE_EXISTS=false
    tproxy_route_local_present && JSON_TPROXY_ROUTE_EXISTS=true
    JSON_TPROXY_TCP_RULE_EXISTS=false
    tproxy_chain_has_tproxy_rule tcp && JSON_TPROXY_TCP_RULE_EXISTS=true
    JSON_TPROXY_UDP_RULE_EXISTS=false
    tproxy_chain_has_tproxy_rule udp && JSON_TPROXY_UDP_RULE_EXISTS=true
    JSON_TPROXY_SOCKET_BYPASS_PRESENT=false
    tproxy_socket_bypass_rule_present && JSON_TPROXY_SOCKET_BYPASS_PRESENT=true
    JSON_TPROXY_NAT_FALLBACK_STATE="$(tproxy_gateway_fallback_state 2>/dev/null || printf 'unknown')"
    JSON_TPROXY_NAT_FALLBACK_ACTIVE="$(json_tri_bool "$JSON_TPROXY_NAT_FALLBACK_STATE")"
    case "$JSON_TPROXY_STATE" in
        enabled)
            if [ "$JSON_TPROXY_MIHOMO_RUNNING" = "true" ] && \
               [ "$JSON_TPROXY_PORT_CONFIGURED" = "true" ] && \
               [ "$JSON_TPROXY_PORT_LISTENING" = "true" ] && \
               [ "$JSON_TPROXY_MANGLE_CHAIN_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_PREROUTING_HOOK_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_IP_RULE_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_ROUTE_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_TCP_RULE_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_UDP_RULE_EXISTS" = "true" ] && \
               [ "$JSON_TPROXY_SOCKET_BYPASS_PRESENT" = "false" ] && \
               [ "$JSON_TPROXY_NAT_FALLBACK_ACTIVE" = "true" ]; then
                JSON_TPROXY_FINAL_HEALTH="healthy"
            else
                JSON_TPROXY_FINAL_HEALTH="degraded"
            fi
            ;;
        disabled) JSON_TPROXY_FINAL_HEALTH="disabled" ;;
        partial) JSON_TPROXY_FINAL_HEALTH="broken" ;;
        *) JSON_TPROXY_FINAL_HEALTH="unknown" ;;
    esac
    JSON_TPROXY_HEALTHY=false
    [ "$JSON_TPROXY_FINAL_HEALTH" = "healthy" ] && JSON_TPROXY_HEALTHY=true
}

cmd_ap_json() {
    json_collect_ap_state
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "component": "ap",\n'
    printf '  "limited": %s,\n' "$JSON_AP_LIMITED"
    printf '  "warnings": '; json_root_warnings; printf ',\n'
    printf '  "interface": '; json_string "$AP_IF"; printf ',\n'
    printf '  "upstream": '; json_string "$AP_UPSTREAM"; printf ',\n'
    printf '  "config_exists": %s,\n' "$JSON_AP_CONFIG_EXISTS"
    printf '  "exists": %s,\n' "$JSON_AP_EXISTS"
    printf '  "up": %s,\n' "$JSON_AP_UP"
    printf '  "ip": '; json_string_or_null "$JSON_AP_IP"; printf ',\n'
    printf '  "ssid": '; json_string "$AP_SSID"; printf ',\n'
    printf '  "type": '; json_string "$JSON_AP_TYPE"; printf ',\n'
    printf '  "hostapd_running": %s,\n' "$JSON_AP_HOSTAPD_RUNNING"
    printf '  "dnsmasq_running": %s,\n' "$JSON_AP_DNSMASQ_RUNNING"
    printf '  "healthy": %s\n' "$JSON_AP_HEALTHY"
    printf '}\n'
}

cmd_gateway_json() {
    json_collect_gateway_state
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "component": "gateway",\n'
    printf '  "limited": %s,\n' "$JSON_GATEWAY_LIMITED"
    printf '  "warnings": '; json_root_warnings; printf ',\n'
    printf '  "mode": '; json_string "$JSON_GATEWAY_MODE"; printf ',\n'
    printf '  "ap_interface": '; json_string "$AP_IF"; printf ',\n'
    printf '  "upstream_interface": '; json_string "$AP_UPSTREAM"; printf ',\n'
    printf '  "subnet": '; json_string "$(gateway_subnet)"; printf ',\n'
    printf '  "ipv4_forwarding": %s,\n' "$JSON_GATEWAY_IPV4_FORWARDING"
    printf '  "nat_active": %s,\n' "$JSON_GATEWAY_NAT_ACTIVE"
    printf '  "fallback_active": %s,\n' "$JSON_GATEWAY_FALLBACK_ACTIVE"
    printf '  "backend": '; json_string "$JSON_GATEWAY_BACKEND"; printf ',\n'
    printf '  "ap_healthy": %s,\n' "$JSON_GATEWAY_AP_HEALTHY"
    printf '  "transparent_proxy_state": '; json_string "$JSON_GATEWAY_TPROXY_STATE"; printf ',\n'
    printf '  "healthy": %s\n' "$JSON_GATEWAY_HEALTHY"
    printf '}\n'
}

cmd_tproxy_json() {
    json_collect_tproxy_state
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "component": "tproxy",\n'
    printf '  "limited": %s,\n' "$JSON_TPROXY_LIMITED"
    printf '  "warnings": '; json_root_warnings; printf ',\n'
    printf '  "enabled": %s,\n' "$JSON_TPROXY_ENABLED"
    printf '  "state": '; json_string "$JSON_TPROXY_STATE"; printf ',\n'
    printf '  "final_health": '; json_string "$JSON_TPROXY_FINAL_HEALTH"; printf ',\n'
    printf '  "port": '; json_number_or_null "$TPROXY_PORT"; printf ',\n'
    printf '  "configured_port": '; json_number_or_null "$JSON_TPROXY_PORT_CONFIGURED_VALUE"; printf ',\n'
    printf '  "mark": '; json_string "$TPROXY_MARK"; printf ',\n'
    printf '  "route_table": '; json_number_or_null "$TPROXY_ROUTE_TABLE"; printf ',\n'
    printf '  "chain": '; json_string "$TPROXY_MANGLE_CHAIN"; printf ',\n'
    printf '  "mihomo_running": %s,\n' "$JSON_TPROXY_MIHOMO_RUNNING"
    printf '  "tproxy_port_configured": %s,\n' "$JSON_TPROXY_PORT_CONFIGURED"
    printf '  "tproxy_port_listening": %s,\n' "$JSON_TPROXY_PORT_LISTENING"
    printf '  "tproxy_out_exists": %s,\n' "$JSON_TPROXY_OUT_EXISTS"
    printf '  "tproxy_out_type": '; json_string "$JSON_TPROXY_OUT_TYPE"; printf ',\n'
    printf '  "mangle_chain_exists": %s,\n' "$JSON_TPROXY_MANGLE_CHAIN_EXISTS"
    printf '  "prerouting_hook_exists": %s,\n' "$JSON_TPROXY_PREROUTING_HOOK_EXISTS"
    printf '  "ip_rule_exists": %s,\n' "$JSON_TPROXY_IP_RULE_EXISTS"
    printf '  "route_exists": %s,\n' "$JSON_TPROXY_ROUTE_EXISTS"
    printf '  "tcp_tproxy_rule_exists": %s,\n' "$JSON_TPROXY_TCP_RULE_EXISTS"
    printf '  "udp_tproxy_rule_exists": %s,\n' "$JSON_TPROXY_UDP_RULE_EXISTS"
    printf '  "socket_bypass_present": %s,\n' "$JSON_TPROXY_SOCKET_BYPASS_PRESENT"
    printf '  "nat_fallback_active": %s,\n' "$JSON_TPROXY_NAT_FALLBACK_ACTIVE"
    printf '  "healthy": %s\n' "$JSON_TPROXY_HEALTHY"
    printf '}\n'
}

cmd_status_json() {
    json_collect_ap_state
    json_collect_gateway_state
    json_collect_tproxy_state
    if [ "$JSON_TPROXY_FINAL_HEALTH" = "healthy" ]; then
        JSON_STATUS_FINAL_HEALTH="healthy"
    elif [ "$JSON_TPROXY_FINAL_HEALTH" = "degraded" ] || [ "$JSON_TPROXY_FINAL_HEALTH" = "broken" ]; then
        JSON_STATUS_FINAL_HEALTH="$JSON_TPROXY_FINAL_HEALTH"
    elif [ "$JSON_GATEWAY_HEALTHY" = "true" ] && [ "$JSON_AP_HEALTHY" = "true" ]; then
        JSON_STATUS_FINAL_HEALTH="healthy"
    elif [ "$JSON_TPROXY_FINAL_HEALTH" = "disabled" ]; then
        JSON_STATUS_FINAL_HEALTH="disabled"
        [ "$JSON_GATEWAY_HEALTHY" = "true" ] && JSON_STATUS_FINAL_HEALTH="healthy"
    else
        JSON_STATUS_FINAL_HEALTH="unknown"
    fi
    JSON_STATUS_LIMITED="$(json_root_limited)"
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "version": '; json_string "$MGATE_VERSION"; printf ',\n'
    printf '  "limited": %s,\n' "$JSON_STATUS_LIMITED"
    printf '  "warnings": '; json_root_warnings; printf ',\n'
    printf '  "ap": {\n'
    printf '    "healthy": %s,\n' "$JSON_AP_HEALTHY"
    printf '    "running": %s,\n' "$JSON_AP_RUNNING"
    printf '    "interface": '; json_string "$AP_IF"; printf ',\n'
    printf '    "ip": '; json_string_or_null "$JSON_AP_IP"; printf '\n'
    printf '  },\n'
    printf '  "gateway": {\n'
    printf '    "mode": '; json_string "$JSON_GATEWAY_MODE"; printf ',\n'
    printf '    "fallback_active": %s,\n' "$JSON_GATEWAY_FALLBACK_ACTIVE"
    printf '    "healthy": %s\n' "$JSON_GATEWAY_HEALTHY"
    printf '  },\n'
    printf '  "tproxy": {\n'
    printf '    "enabled": %s,\n' "$JSON_TPROXY_ENABLED"
    printf '    "state": '; json_string "$JSON_TPROXY_STATE"; printf ',\n'
    printf '    "final_health": '; json_string "$JSON_TPROXY_FINAL_HEALTH"; printf '\n'
    printf '  },\n'
    printf '  "summary": {\n'
    printf '    "final_health": '; json_string "$JSON_STATUS_FINAL_HEALTH"; printf '\n'
    printf '  }\n'
    printf '}\n'
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

cmd_preflight() {
    script_file="${1:-$0}"
    [ -f "$script_file" ] || die "script not found: $script_file"

    step "检查脚本行尾"
    check_no_crlf_file "$script_file" || die "发现 CRLF 行尾；请将脚本转换为 LF 后再发布"
    ok "脚本行尾为 LF：$script_file"

    step "检查脚本语法"
    sh -n "$script_file" || die "shell syntax check failed: $script_file"
    ok "脚本语法通过：$script_file"

    if [ -f "$WEB_CGI_FILE" ]; then
        step "检查生成的 Web CGI"
        check_no_crlf_file "$WEB_CGI_FILE" || die "generated CGI contains CRLF line endings; convert it to LF"
        sh -n "$WEB_CGI_FILE" || die "generated CGI syntax check failed: $WEB_CGI_FILE"
        ok "Web CGI 行尾和语法通过：$WEB_CGI_FILE"
    else
        info "Web CGI 不存在，跳过：$WEB_CGI_FILE"
    fi

    ok "preflight checks passed"
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
    if [ -f "$WEB_CGI_FILE" ] && ! grep -q "TPROXY_PORT=\"$TPROXY_PORT\"" "$WEB_CGI_FILE" 2>/dev/null; then
        doctor_warn "Web CGI 可能是旧版本（缺少 TPROXY_PORT 注入），建议执行：mgate migrate"
    fi
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
# Migrate
# -----------------------------
MIGRATE_CONFIG_CHANGED=0

migrate_config_ensure_key() {
    key="$1"
    value="$2"
    grep -q "^[[:space:]]*${key}[[:space:]]*:" "$CONFIG_FILE" 2>/dev/null && return 0
    printf '%s: %s\n' "$key" "$value" >> "$CONFIG_FILE" || return 1
    MIGRATE_CONFIG_CHANGED=1
    ok "migrate: 已添加 $key: $value"
}

migrate_patch_config() {
    [ -f "$CONFIG_FILE" ] || { warn "migrate: config.yaml 不存在，跳过配置迁移"; return 0; }

    step "检查并修补 config.yaml（只追加，不覆盖）"
    backup_file "$CONFIG_FILE"

    migrate_config_ensure_key "allow-lan" "true"
    migrate_config_ensure_key "bind-address" "'*'"
    migrate_config_ensure_key "tproxy-port" "$TPROXY_PORT"
    migrate_config_ensure_key "external-controller" "127.0.0.1:$DEFAULT_MIHOMO_API_PORT"

    if ! grep -q "^profile:" "$CONFIG_FILE" 2>/dev/null; then
        printf '\nprofile:\n  store-selected: true\n' >> "$CONFIG_FILE"
        MIGRATE_CONFIG_CHANGED=1
        ok "migrate: 已添加 profile.store-selected"
    fi

    if ! tproxy_config_has_out_group 2>/dev/null; then
        tproxy_config_insert_group && {
            MIGRATE_CONFIG_CHANGED=1
            ok "migrate: 已添加 $TPROXY_OUT_GROUP 代理组"
        } || warn "migrate: 添加 $TPROXY_OUT_GROUP 代理组失败，请手动检查"
    else
        ok "migrate: $TPROXY_OUT_GROUP 代理组已存在"
    fi

    if ! tproxy_config_has_in_type_rule 2>/dev/null; then
        tproxy_config_insert_rule && {
            MIGRATE_CONFIG_CHANGED=1
            ok "migrate: 已添加 IN-TYPE,TPROXY 规则"
        } || warn "migrate: 添加 IN-TYPE,TPROXY 规则失败，请手动检查"
    else
        ok "migrate: IN-TYPE,TPROXY 规则已存在"
    fi
}

cmd_migrate() {
    need_root
    ensure_dirs
    MIGRATE_CONFIG_CHANGED=0

    migrate_patch_config

    step "刷新 Web 管理文件"
    generate_web_files
    create_web_service_files
    ok "Web 文件已刷新"

    step "刷新系统服务文件"
    create_service_files
    ok "服务文件已刷新"

    if [ "$MIGRATE_CONFIG_CHANGED" -eq 1 ]; then
        step "配置已更新，重启 mihomo 使其生效"
        service_restart || warn "重启 mihomo 失败，请手动执行：mgate restart"
    else
        ok "配置无需变更"
    fi

    ok "migrate 完成"
    hint "如 Web 管理正在运行，请执行：mgate web-restart"
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
        curl -fsSL --connect-timeout "$MGATE_CONNECT_TIMEOUT" --max-time "$MGATE_DOWNLOAD_TIMEOUT" \
            -A "$ua" \
            -H "Accept: application/yaml,text/yaml,text/plain,*/*" \
            -o "$out" "$url"
        return $?
    fi
    if have wget; then
        wget -T "$MGATE_DOWNLOAD_TIMEOUT" \
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

sub_generate_node_observability() {
    names_file="$1"
    nodes_file="$2"
    unmatched_file="$3"
    matches_file="$nodes_file.matches"
    matched_idx_file="$nodes_file.idx"
    : > "$nodes_file"
    : > "$unmatched_file"
    : > "$matches_file"
    : > "$matched_idx_file"

    country_map | while IFS= read -r line; do
        [ -n "$line" ] || continue
        code="${line%%|*}"
        rest="${line#*|}"
        [ "$rest" != "$line" ] || continue
        regex="${rest#*|}"
        [ "$regex" != "$rest" ] || continue
        [ -n "$regex" ] || continue
        grep -Ein "$regex" "$names_file" 2>/dev/null | while IFS=: read -r idx node_name; do
            [ -n "$idx" ] || continue
            printf '%s\t%s\t%s\n' "$idx" "$code" "$node_name" >> "$matches_file"
            printf '%s\n' "$idx" >> "$matched_idx_file"
        done
    done

    awk '
        FNR==NR {line[$1] = line[$1] $0 "\n"; next}
        (FNR in line) {printf "%s", line[FNR]}
    ' "$matches_file" "$names_file" > "$nodes_file"
    awk '
        FNR==NR {matched[$1]=1; next}
        !(FNR in matched) {printf "%s\t%s\n", FNR, $0}
    ' "$matched_idx_file" "$names_file" > "$unmatched_file"
    rm -f "$matches_file" "$matched_idx_file" 2>/dev/null || true
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
allow-lan: true
bind-address: '*'
tproxy-port: $TPROXY_PORT
external-controller: 127.0.0.1:$DEFAULT_MIHOMO_API_PORT

profile:
  store-selected: true

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
  - name: $TPROXY_OUT_GROUP
    type: select
    use:
      - mgate-sub

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
  - IN-TYPE,TPROXY,$TPROXY_OUT_GROUP
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
    tmp_nodes="$work/nodes.txt"
    tmp_unmatched="$work/unmatched.txt"
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
    sub_generate_node_observability "$tmp_names" "$tmp_nodes" "$tmp_unmatched"
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
    cp "$tmp_nodes" "$SUB_NODES_FILE" || die "写入节点识别文件失败"
    cp "$tmp_unmatched" "$SUB_UNMATCHED_FILE" || die "写入未匹配节点文件失败"
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

cmd_sub_nodes() {
    [ -s "$SUB_NODES_FILE" ] || die "no subscription data found; please run mgate sub-update"
    cat "$SUB_NODES_FILE"
}

cmd_sub_unmatched() {
    [ -f "$SUB_UNMATCHED_FILE" ] || die "no subscription data found; please run mgate sub-update"
    if [ -s "$SUB_UNMATCHED_FILE" ]; then
        cat "$SUB_UNMATCHED_FILE"
    else
        say "no unmatched nodes"
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
    rm -f "$SUB_URL_FILE" "$SUB_STATUS_FILE" "$SUB_COUNTRIES_FILE" "$SUB_ACCOUNTS_FILE" "$SUB_LAST_UPDATE_FILE" "$SUB_PROVIDER_FILE" "$SUB_NODES_FILE" "$SUB_UNMATCHED_FILE"
    ok "订阅信息已清除"
    hint "如需重新生成手动模板：FORCE=1 mgate install"
}


cmd_proxy_info() {
    host="设备IP"
    mixed_port="$(config_listener_port mixed-users "$DEFAULT_MIXED_PORT")"
    tproxy_port="$(tproxy_mihomo_port 2>/dev/null || true)"
    [ -n "$tproxy_port" ] || tproxy_port="$TPROXY_PORT"
    info "Mixed 代理端口：$mixed_port（HTTP / SOCKS5 统一端口，需客户端手动配置）"
    info "TProxy 透明代理端口：$tproxy_port（AP 客户端流量由 iptables 自动重定向，无需客户端配置）"
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
    step "TProxy 透明代理端口"
    info "端口：$tproxy_port"
    info "用途：AP 客户端流量由 iptables mangle/TPROXY 规则自动重定向至此端口"
    info "前提：mgate start 后端口即监听；mgate tproxy-start 后流量才实际进入"
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
  mgate tui                 进入 TUI 菜单

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
  mgate preflight [file]    检查脚本 LF 行尾和 POSIX sh 语法

AP 管理：
  mgate ap-check            检查 AP 依赖和 wlan0 信道
  mgate ap-install-deps     安装 AP 所需依赖
  mgate ap-status           查看 ap0 热点状态
  mgate ap-json             输出 AP 只读 JSON 状态
  mgate ap-config           查看/生成 AP 配置
  mgate ap-start            启动 ap0 热点、DHCP 和 DNS
  mgate ap-stop             停止 mgate 管理的 ap0 热点

NAT 网关：
  mgate gateway-check       检查普通 NAT 网关环境
  mgate gateway-start       启动 ap0 -> wlan0 IPv4 NAT 出网
  mgate gateway-stop        停止 mgate NAT 规则并恢复 ip_forward
  mgate gateway-status      查看 NAT 网关状态
  mgate gateway-json        输出 NAT 网关只读 JSON 状态
  mgate gateway-debug       输出 NAT/AP/DHCP/DNS 诊断信息
  mgate gateway-doctor      检查普通 NAT 网关健康基线
  mgate tproxy-check        只读检查 TProxy 能力
  mgate tproxy-status       只读查看 TProxy 状态
  mgate tproxy-json         输出 TProxy 只读 JSON 状态
  mgate tproxy-health       快速检查 TProxy 透明代理健康状态
  mgate tproxy-plan         输出 TProxy 启用计划
  mgate tproxy-dry-run      输出未来启用命令但不执行
  mgate tproxy-start        启用透明代理 TProxy 规则
  mgate tproxy-stop         停止并清理 mgate TProxy 规则
  mgate tproxy-nodes        列出 TPROXY-OUT 可用节点（需 mihomo 运行）
  mgate tproxy-select <节点> 切换 TPROXY-OUT 节点（即时生效，无需重启）
  mgate tproxy-doctor       检查 TProxy 闭环健康状态
  mgate tproxy-debug        输出 TProxy 排障信息

升级与迁移：
  mgate migrate             升级后同步配置和生成文件（self-update 会自动调用）

备份与恢复：
  mgate backup [label]      创建备份
  mgate backups             查看备份列表
  mgate restore [id|latest] 恢复备份

订阅管理：
  mgate sub-set <url>       设置/替换订阅并立即更新配置
  mgate sub-update          拉取已保存订阅并更新配置
  mgate sub-status          查看订阅状态和账号
  mgate sub-nodes           查看节点国家/地区识别结果
  mgate sub-unmatched       查看未识别到国家/地区的节点
  mgate sub-debug           查看最近一次订阅失败详情
  mgate sub-clear           清除订阅设置和缓存

账号与连接：
  mgate account-password    查看/修改代理账号默认密码
  mgate passwd              account-password 的别名
  mgate proxy-info          查看代理连接信息
  mgate status-json         输出 AP/网关/TProxy 摘要 JSON

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
tui_clear() {
    printf '\033[2J\033[H'
}

tui_header() {
    tui_clear
    printf '================================================\n'
    if [ -n "${1:-}" ]; then
        printf '  mgate  /  %s\n' "$1"
        printf '------------------------------------------------\n'
    else
        printf '\n'
        printf '  mgate    %s\n' "$WORKDIR"
        printf '\n'
        printf '================================================\n'
    fi
}

tui_confirm() {
    msg="$1"
    printf '%s [y/N] ' "$msg"
    read -r ans || ans=""
    case "$ans" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) warn "已取消"; return 1 ;;
    esac
}

tui_confirm_yes() {
    msg="$1"
    say "$msg"
    printf '请输入 yes 确认: '
    read -r ans || ans=""
    case "$ans" in
        yes) return 0 ;;
        *) warn "已取消"; return 1 ;;
    esac
}

menu_mihomo() {
    while :; do
        tui_header "Mihomo 管理"
        say ""
        say "   1.  启动"
        say "   2.  停止"
        say "   3.  重启"
        say "   4.  查看状态"
        say "   5.  查看日志"
        say "   6.  测试配置"
        say "   7.  编辑配置"
        say "   8.  查看配置"
        say "   9.  系统诊断"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) service_start; pause_enter ;;
            2) service_stop; pause_enter ;;
            3) service_restart; pause_enter ;;
            4) service_status; pause_enter ;;
            5) cmd_logs; pause_enter ;;
            6) cmd_test; pause_enter ;;
            7) cmd_edit; pause_enter ;;
            8) cmd_config; pause_enter ;;
            9) cmd_doctor; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_ap() {
    while :; do
        tui_header "AP 热点管理"
        say ""
        say "   1.  环境检查"
        say "   2.  安装依赖"
        say "   3.  查看配置"
        say "   4.  查看状态"
        say "   5.  启动 AP"
        say "   6.  停止 AP"
        say "   7.  JSON 状态"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) cmd_ap_check; pause_enter ;;
            2) cmd_ap_install_deps; pause_enter ;;
            3) cmd_ap_config; pause_enter ;;
            4) cmd_ap_status; pause_enter ;;
            5)
                if tui_confirm "将创建/复用 ap0 并启动 mgate 隔离的 hostapd/dnsmasq，继续吗？"; then
                    cmd_ap_start
                fi
                pause_enter
                ;;
            6)
                if tui_confirm "将停止 mgate 管理的 AP 实例并删除 ap0，继续吗？"; then
                    cmd_ap_stop
                fi
                pause_enter
                ;;
            7) cmd_ap_json; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_gateway() {
    while :; do
        tui_header "网关 / NAT 管理"
        say ""
        say "   1.  环境检查"
        say "   2.  启动 NAT Gateway"
        say "   3.  停止 NAT Gateway"
        say "   4.  查看状态"
        say "   5.  Doctor 诊断"
        say "   6.  Debug 调试"
        say "   7.  JSON 状态"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) cmd_gateway_check; pause_enter ;;
            2)
                if tui_confirm "将启用 IPv4 forwarding 和 NAT fallback，继续吗？"; then
                    cmd_gateway_start
                fi
                pause_enter
                ;;
            3)
                if tui_confirm "将停止 NAT gateway，AP 客户端可能无法继续上网，继续吗？"; then
                    cmd_gateway_stop
                fi
                pause_enter
                ;;
            4) cmd_gateway_status; pause_enter ;;
            5) cmd_gateway_doctor; pause_enter ;;
            6) cmd_gateway_debug; pause_enter ;;
            7) cmd_gateway_json; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_tproxy() {
    while :; do
        tui_header "TProxy 透明代理"
        say ""
        say "    1.  能力检查"
        say "    2.  查看状态"
        say "    3.  执行计划"
        say "    4.  Dry-run"
        say "    5.  启动 TProxy"
        say "    6.  停止 TProxy"
        say "    7.  查看可用节点"
        say "    8.  切换代理节点"
        say "    9.  Health 检查"
        say "   10.  Doctor 诊断"
        say "   11.  Debug 调试"
        say "   12.  JSON 状态"
        say ""
        say "    0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) cmd_tproxy_check; pause_enter ;;
            2) cmd_tproxy_status; pause_enter ;;
            3) cmd_tproxy_plan; pause_enter ;;
            4) cmd_tproxy_dry_run; pause_enter ;;
            5)
                if tui_confirm_yes "将写入 ip rule / route table / iptables mangle；失败会自动回滚。"; then
                    cmd_tproxy_start
                fi
                pause_enter
                ;;
            6)
                if tui_confirm "将清理 TProxy 规则并回到 NAT fallback，继续吗？"; then
                    cmd_tproxy_stop
                fi
                pause_enter
                ;;
            7) cmd_tproxy_nodes; pause_enter ;;
            8)
                printf '节点名: '
                read -r _node || _node=""
                [ -n "$_node" ] && cmd_tproxy_select "$_node" || warn "未输入节点名"
                pause_enter
                ;;
            9)  cmd_tproxy_health; pause_enter ;;
            10) cmd_tproxy_doctor; pause_enter ;;
            11) cmd_tproxy_debug; pause_enter ;;
            12) cmd_tproxy_json; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_web() {
    while :; do
        tui_header "Web 管理"
        say ""
        say "   1.  开启 Web 管理"
        say "   2.  关闭 Web 管理"
        say "   3.  启动"
        say "   4.  停止"
        say "   5.  重启"
        say "   6.  查看状态"
        say "   7.  重置 Token"
        say "   8.  刷新 Web 文件"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) web_enable; pause_enter ;;
            2)
                if tui_confirm "将关闭 Web 管理并取消开机自启，继续吗？"; then
                    web_disable
                fi
                pause_enter
                ;;
            3) web_start; pause_enter ;;
            4) web_stop; pause_enter ;;
            5) web_restart; pause_enter ;;
            6) web_status; pause_enter ;;
            7)
                if tui_confirm "将重置 Web Token，当前 Token 立即失效，继续吗？"; then
                    web_token reset
                fi
                pause_enter
                ;;
            8) web_refresh; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_sub() {
    while :; do
        tui_header "订阅管理"
        say ""
        say "   1.  设置订阅"
        say "   2.  更新订阅"
        say "   3.  查看订阅状态"
        say "   4.  查看节点识别结果"
        say "   5.  查看未识别节点"
        say "   6.  调试信息"
        say "   7.  清除订阅"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1)
                printf '订阅 URL: '
                read -r _url || _url=""
                [ -n "$_url" ] && cmd_sub_set "$_url" || warn "未输入 URL"
                pause_enter
                ;;
            2) cmd_sub_update; pause_enter ;;
            3) cmd_sub_status; pause_enter ;;
            4) cmd_sub_nodes; pause_enter ;;
            5) cmd_sub_unmatched; pause_enter ;;
            6) cmd_sub_debug; pause_enter ;;
            7)
                if tui_confirm "将清除订阅链接和缓存，继续吗？"; then
                    cmd_sub_clear
                fi
                pause_enter
                ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_system() {
    while :; do
        tui_header "系统 / 迁移"
        say ""
        say "    1.  初始化/修复工作区"
        say "    2.  更新 mgate 脚本"
        say "    3.  Migrate（升级后同步）"
        say "    4.  安装/更新 Mihomo 内核"
        say "    5.  卸载 Mihomo 内核"
        say "    6.  设置开机自启"
        say "    7.  取消开机自启"
        say "    8.  preflight 检查"
        say "    9.  查看版本"
        say "   10.  创建备份"
        say "   11.  查看备份列表"
        say "   12.  恢复备份"
        say "   13.  完整卸载 mgate"
        say ""
        say "    0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) cmd_install; pause_enter ;;
            2) cmd_self_update; pause_enter ;;
            3) cmd_migrate; pause_enter ;;
            4) install_core; pause_enter ;;
            5) cmd_uninstall_core; pause_enter ;;
            6) service_enable; pause_enter ;;
            7) service_disable; pause_enter ;;
            8) cmd_preflight; pause_enter ;;
            9) cmd_version; pause_enter ;;
            10) cmd_backup; pause_enter ;;
            11) cmd_backups; pause_enter ;;
            12) cmd_restore; pause_enter ;;
            13)
                if tui_confirm "将完整卸载 mgate，此操作不可逆，继续吗？"; then
                    cmd_uninstall; exit 0
                fi
                pause_enter
                ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu_account() {
    while :; do
        tui_header "账号与代理"
        say ""
        say "   1.  查看代理连接信息"
        say "   2.  查看账号默认密码"
        say "   3.  修改账号默认密码"
        say ""
        say "   0.  返回  ( Enter 也可 )"
        say ""
        printf '>>> '
        read -r choice || return 0
        case "$choice" in
            ""|0) return 0 ;;
            1) cmd_proxy_info; pause_enter ;;
            2) cmd_account_password; pause_enter ;;
            3) cmd_account_password set; pause_enter ;;
            *) warn "无效选项"; pause_enter ;;
        esac
    done
}

menu() {
    while :; do
        tui_header
        say ""
        say "   1.  Mihomo 管理"
        say "   2.  AP 热点管理"
        say "   3.  网关 / NAT 管理"
        say "   4.  TProxy 透明代理"
        say "   5.  Web 管理"
        say "   6.  订阅管理"
        say "   7.  系统 / 迁移"
        say "   8.  账号与代理"
        say ""
        say "   0.  退出"
        say ""
        printf '>>> '
        read -r choice || exit 0
        case "$choice" in
            1) menu_mihomo ;;
            2) menu_ap ;;
            3) menu_gateway ;;
            4) menu_tproxy ;;
            5) menu_web ;;
            6) menu_sub ;;
            7) menu_system ;;
            8) menu_account ;;
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
        menu|tui) menu ;;
        install) cmd_install "$@" ;;
        self-update|update) cmd_self_update "$@" ;;
        install-core) install_core "$@" ;;
        uninstall-core) cmd_uninstall_core "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        start) service_start "$@" ;;
        stop) service_stop "$@" ;;
        restart) service_restart "$@" ;;
        status) service_status "$@" ;;
        status-json) cmd_status_json "$@" ;;
        enable) service_enable "$@" ;;
        disable) service_disable "$@" ;;
        config) cmd_config "$@" ;;
        edit) cmd_edit "$@" ;;
        test) cmd_test "$@" ;;
        logs) cmd_logs "$@" ;;
        doctor) cmd_doctor "$@" ;;
        preflight) cmd_preflight "$@" ;;
        ap-check) cmd_ap_check "$@" ;;
        ap-install-deps) cmd_ap_install_deps "$@" ;;
        ap-status) cmd_ap_status "$@" ;;
        ap-json) cmd_ap_json "$@" ;;
        ap-config) cmd_ap_config "$@" ;;
        ap-start) cmd_ap_start "$@" ;;
        ap-stop) cmd_ap_stop "$@" ;;
        gateway-check|nat-check) cmd_gateway_check "$@" ;;
        gateway-start|nat-start) cmd_gateway_start "$@" ;;
        gateway-stop|nat-stop) cmd_gateway_stop "$@" ;;
        gateway-status|nat-status) cmd_gateway_status "$@" ;;
        gateway-json|nat-json) cmd_gateway_json "$@" ;;
        gateway-debug|nat-debug) cmd_gateway_debug "$@" ;;
        gateway-doctor|nat-doctor) cmd_gateway_doctor "$@" ;;
        tproxy-check) cmd_tproxy_check "$@" ;;
        tproxy-status) cmd_tproxy_status "$@" ;;
        tproxy-json) cmd_tproxy_json "$@" ;;
        tproxy-health) cmd_tproxy_health "$@" ;;
        tproxy-plan) cmd_tproxy_plan "$@" ;;
        tproxy-dry-run) cmd_tproxy_dry_run "$@" ;;
        tproxy-start) cmd_tproxy_start "$@" ;;
        tproxy-stop) cmd_tproxy_stop "$@" ;;
        tproxy-nodes) cmd_tproxy_nodes "$@" ;;
        tproxy-select) cmd_tproxy_select "$@" ;;
        tproxy-doctor) cmd_tproxy_doctor "$@" ;;
        tproxy-debug) cmd_tproxy_debug "$@" ;;
        migrate) cmd_migrate "$@" ;;
        backup) cmd_backup "$@" ;;
        backups) cmd_backups "$@" ;;
        restore) cmd_restore "$@" ;;
        sub-set) cmd_sub_set "$@" ;;
        sub-update) cmd_sub_update "$@" ;;
        sub-status) cmd_sub_status "$@" ;;
        sub-nodes) cmd_sub_nodes "$@" ;;
        sub-unmatched) cmd_sub_unmatched "$@" ;;
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
