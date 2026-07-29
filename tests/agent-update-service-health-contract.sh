#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WORK_DIR=/tmp/mgate-test-agent-update-health.$$
mkdir -p "$WORK_DIR/pkg" "$WORK_DIR/tmp"
trap 'rm -rf "$WORK_DIR"' EXIT

MGATE_AGENT_BIN="$WORK_DIR/mgate-agent"
MGATE_AGENT_SERVICE_FILE="$WORK_DIR/mgate-agent.service"
MGATE_AGENT_CONFIG_FILE="$WORK_DIR/agent.yaml"
MGATE_AGENT_CREDS_FILE="$WORK_DIR/credentials.json"
TMP_DIR="$WORK_DIR/tmp"
MGATE_AGENT_HEALTH_RETRIES=1
MGATE_AGENT_HEALTH_INTERVAL=0

need_root() { :; }
agent_detect_arch() { printf 'amd64\n'; }
agent_load_token() { :; }
agent_get_installed_version() { printf 'v1.0.0\n'; }
agent_warn_legacy_config() { :; }
agent_migrate_legacy_config() { :; }
agent_check_if_enrolled() { return 0; }
have() { [ "$1" = systemctl ] || command -v "$1" >/dev/null 2>&1; }

agent_download_and_verify() {
    AGENT_DOWNLOAD_BIN_PATH="$WORK_DIR/pkg/mgate-agent"
    cat > "$AGENT_DOWNLOAD_BIN_PATH" <<'EOF_AGENT'
#!/bin/sh
if [ "${1:-}" = run ]; then
    cfg="${3:-}"
    if ! grep -q '^security:' "$cfg" 2>/dev/null; then
        cat >> "$cfg" <<'EOF_SECURITY'
security:
  allow_actions_mode: managed
  allow_actions:
    - system.selfupdate
EOF_SECURITY
    fi
fi
exit 0
EOF_AGENT
    chmod +x "$AGENT_DOWNLOAD_BIN_PATH"
}

SERVICE_ACTIVE=1
START_RC=0
START_SETS_ACTIVE=1
systemctl() {
    case "$1 ${2:-}" in
        "is-active mgate-agent")
            [ "$SERVICE_ACTIVE" = 1 ]
            ;;
        "stop mgate-agent")
            SERVICE_ACTIVE=0
            ;;
        "start mgate-agent")
            [ "$START_RC" -eq 0 ] || return "$START_RC"
            "$MGATE_AGENT_BIN" run --config "$MGATE_AGENT_CONFIG_FILE"
            # Recovery starts the restored old binary.  The simulated new
            # binary reaches active only when this scenario allows it.
            if grep -q 'old-agent' "$MGATE_AGENT_BIN" || [ "$START_SETS_ACTIVE" = 1 ]; then
                SERVICE_ACTIVE=1
            fi
            ;;
        "daemon-reload ") : ;;
        *) : ;;
    esac
}

write_old_install() {
    printf '#!/bin/sh\necho old-agent\n' > "$MGATE_AGENT_BIN"
    chmod +x "$MGATE_AGENT_BIN"
    printf '[Service]\nExecStart=old-agent\n' > "$MGATE_AGENT_SERVICE_FILE"
    cat > "$MGATE_AGENT_CONFIG_FILE" <<'EOF_CONFIG'
cloud:
  base_url: https://cloud.example.test
agent:
  device_name: preserved-device
EOF_CONFIG
}

run_update() {
    set +e
    output="$(cmd_agent_update --version=v1.2.3 --yes 2>&1)"
    rc=$?
    set -e
}

# start succeeds immediately but the new process never reaches active: this
# must fail and restore the prior running binary/service.
write_old_install
SERVICE_ACTIVE=1
START_RC=0
START_SETS_ACTIVE=0
run_update
[ "$rc" -ne 0 ] || { printf 'expected inactive-after-start failure: %s\n' "$output" >&2; exit 1; }
grep -q 'old-agent' "$MGATE_AGENT_BIN"
[ "$SERVICE_ACTIVE" = 1 ] || { printf 'expected old service recovery\n' >&2; exit 1; }
grep -q 'https://cloud.example.test' "$MGATE_AGENT_CONFIG_FILE"
grep -q 'preserved-device' "$MGATE_AGENT_CONFIG_FILE"
if grep -q '^security:' "$MGATE_AGENT_CONFIG_FILE"; then
    printf 'expected failed update to restore the original agent config\n' >&2
    exit 1
fi

# Normal update starts the downloaded binary. Its simulated startup migration
# proves mgate preserved the old config and actually switched to the new
# process, which supplies managed system.selfupdate for legacy configs.
write_old_install
SERVICE_ACTIVE=1
START_RC=0
START_SETS_ACTIVE=1
run_update
[ "$rc" -eq 0 ] || { printf 'expected successful healthy update: %s\n' "$output" >&2; exit 1; }
[ "$SERVICE_ACTIVE" = 1 ] || { printf 'expected updated service active\n' >&2; exit 1; }
grep -q 'https://cloud.example.test' "$MGATE_AGENT_CONFIG_FILE"
grep -q 'preserved-device' "$MGATE_AGENT_CONFIG_FILE"
grep -q '^security:' "$MGATE_AGENT_CONFIG_FILE"
grep -q 'allow_actions_mode: managed' "$MGATE_AGENT_CONFIG_FILE"
grep -q 'system.selfupdate' "$MGATE_AGENT_CONFIG_FILE"

printf 'agent update service-health contract: OK\n'
