#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

# A successful systemctl start is not sufficient: the combined-upgrade worker
# must report failure when the new agent exits before becoming active.
WORK_DIR=/tmp/mgate-test-worker-health.$$
mkdir -p "$WORK_DIR/pkg" "$WORK_DIR/tmp"
trap 'rm -rf "$WORK_DIR"' EXIT

MGATE_AGENT_UPGRADE_STATUS_FILE="$WORK_DIR/combined-upgrade-status.json"
MGATE_AGENT_BIN="$WORK_DIR/mgate-agent"
MGATE_AGENT_SERVICE_FILE="$WORK_DIR/mgate-agent.service"
MGATE_AGENT_CONFIG_FILE="$WORK_DIR/agent.yaml"
TMP_DIR="$WORK_DIR/tmp"
MGATE_AGENT_HEALTH_RETRIES=1
MGATE_AGENT_HEALTH_INTERVAL=0

logger() { :; }
cmd_migrate() { return 0; }
need_root() { :; }
agent_detect_arch() { printf 'amd64\n'; }
agent_load_token() { :; }
agent_get_latest_version() { printf 'v1.2.3\n'; }
agent_get_installed_version() { printf 'v1.0.0\n'; }
agent_warn_legacy_config() { :; }
agent_check_if_enrolled() { return 0; }
have() { [ "$1" = systemctl ] || command -v "$1" >/dev/null 2>&1; }
agent_download_and_verify() {
    AGENT_DOWNLOAD_BIN_PATH="$WORK_DIR/pkg/mgate-agent"
    printf '#!/bin/sh\nexit 0\n' > "$AGENT_DOWNLOAD_BIN_PATH"
    chmod +x "$AGENT_DOWNLOAD_BIN_PATH"
}
agent_install_service() { return 0; }
agent_install_config() { return 0; }

SERVICE_ACTIVE=1
systemctl() {
    case "$1 ${2:-}" in
        "is-active mgate-agent") [ "$SERVICE_ACTIVE" = 1 ] ;;
        "stop mgate-agent") SERVICE_ACTIVE=0 ;;
        "start mgate-agent")
            # The replacement process exits immediately, while recovery of
            # the backed-up process can become active again.
            grep -q 'old-agent' "$MGATE_AGENT_BIN" && SERVICE_ACTIVE=1
            ;;
        "daemon-reload ") : ;;
        *) : ;;
    esac
}

write_old_install() {
    printf '#!/bin/sh\necho old-agent\n' > "$MGATE_AGENT_BIN"
    chmod +x "$MGATE_AGENT_BIN"
    printf '[Service]\nExecStart=old-agent\n' > "$MGATE_AGENT_SERVICE_FILE"
    printf 'cloud:\n  base_url: https://cloud.example.test\n' > "$MGATE_AGENT_CONFIG_FILE"
    SERVICE_ACTIVE=1
}

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

write_old_install
set +e
cmd_agent_combined_upgrade_worker >/dev/null 2>&1
worker_rc=$?
set -e
[ "$worker_rc" -ne 0 ] || { printf 'expected worker health-gate failure\n' >&2; exit 1; }
status_content=$(cat "$MGATE_AGENT_UPGRADE_STATUS_FILE")
assert_contains "$status_content" '"state":"failed"'
assert_contains "$status_content" '"exit_code":1'
[ "$SERVICE_ACTIVE" = 1 ] || { printf 'expected previous service recovery\n' >&2; exit 1; }

printf 'agent worker service-health contract: OK\n'
