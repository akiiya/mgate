#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WORK_DIR=/tmp/mgate-test-web-tproxy.$$
mkdir -p "$WORK_DIR/jobs"
trap 'rm -rf "$WORK_DIR"' EXIT

SCRIPT_PATH="$WORK_DIR/fake-mgate"
WEB_CGI_FILE="$WORK_DIR/mgate.cgi"
WEB_TOKEN_FILE="$WORK_DIR/web.token"
WEB_JOB_DIR="$WORK_DIR/jobs"
CONFIG_FILE="$WORK_DIR/config.yaml"
DATA_DIR="$WORK_DIR/data"
GROUPS_DIR="$WORK_DIR/groups"
SUB_URL_FILE="$WORK_DIR/sub.url"
CUSTOM_PROVIDER_FILE="$WORK_DIR/custom.yaml"
SUB_LAST_UPDATE_FILE="$WORK_DIR/sub.last"
TPROXY_HEALTH_MARKER="$WORK_DIR/tproxy-health-ran"
export TPROXY_HEALTH_MARKER

printf 'test-token\n' > "$WEB_TOKEN_FILE"
: > "$CONFIG_FILE"
cat > "$SCRIPT_PATH" <<'EOF_MGATE'
#!/bin/sh
case "${1:-}" in
    tproxy-json) printf '{"enabled":false,"state":"inactive","healthy":false}\n' ;;
    tproxy-nodes)
        if [ "${TPROXY_TEST_NODES:-present}" = absent; then
            exit 0
        fi
        printf '[INFO] 当前选中：node-a\n'
        printf '[INFO] 1) * node-a\n'
        printf '[INFO] 2)   node-b\n'
        ;;
    tproxy-health) printf 'health requested\n' >> "$TPROXY_HEALTH_MARKER" ;;
esac
EOF_MGATE
chmod +x "$SCRIPT_PATH"

generate_mgate_cgi

# Rendering the disabled page must still expose node selection, but must not
# run diagnostics before the user expands the details element.
QUERY_STRING='action=tproxy-page' HTTP_COOKIE='mgate_token=test-token' "$WEB_CGI_FILE" > "$WORK_DIR/page.out"
_page_content="$(cat "$WORK_DIR/page.out")"
case "$_page_content" in *'value="tproxy-select-do"'*) : ;; *) printf 'node selection missing while disabled\n' >&2; exit 1 ;; esac
case "$_page_content" in *'id="tproxy-diagnostics"'*) : ;; *) printf 'collapsed diagnostics missing\n' >&2; exit 1 ;; esac
case "$_page_content" in *'action=tproxy-health-text'*) : ;; *) printf 'lazy diagnostics endpoint missing\n' >&2; exit 1 ;; esac
[ ! -e "$TPROXY_HEALTH_MARKER" ] || { printf 'diagnostics ran during page render\n' >&2; exit 1; }

# The lazy endpoint invokes the backend only when it is explicitly requested.
QUERY_STRING='action=tproxy-health-text' HTTP_COOKIE='mgate_token=test-token' "$WEB_CGI_FILE" > "$WORK_DIR/health.out"
grep -q 'health requested' "$TPROXY_HEALTH_MARKER"

# Mihomo may be stopped or lack a selectable TPROXY-OUT group. Keep that
# limitation explicit instead of rendering an empty page without guidance.
grep -Fq '当前无法从 Mihomo 获取可选节点' "$ROOT/mgate.sh"

printf 'web tproxy page contract: OK\n'
