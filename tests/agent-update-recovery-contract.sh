#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

# Regression coverage for: cmd_agent_update() must attempt to restart
# mgate-agent on EVERY failure path after it has been stopped, not just the
# first one (binary-copy failure) -- a service left stopped with no recovery
# attempt is worse than the update simply failing.

WORK_DIR=/tmp/mgate-test-agentupdate.$$
mkdir -p "$WORK_DIR/pkg"
MGATE_AGENT_BIN="$WORK_DIR/mgate-agent"
TMP_DIR="$WORK_DIR/tmp"
MGATE_AGENT_CONFIG_FILE="$WORK_DIR/agent.yaml"
SYSTEMCTL_LOG="$WORK_DIR/systemctl.log"
mkdir -p "$TMP_DIR"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

need_root() { :; }
agent_detect_arch() { printf 'amd64\n'; }
agent_load_token() { :; }
agent_download_and_verify() {
    AGENT_DOWNLOAD_BIN_PATH="$WORK_DIR/pkg/mgate-agent"
    printf '#!/bin/sh\nexit 0\n' > "$AGENT_DOWNLOAD_BIN_PATH"
    chmod +x "$AGENT_DOWNLOAD_BIN_PATH"
    return 0
}
agent_warn_legacy_config() { :; }
have() { [ "$1" = "systemctl" ] || command -v "$1" >/dev/null 2>&1; }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

assert_not_contains() {
    if printf '%s' "$1" | grep -q "$2"; then
        printf 'expected NOT to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    fi
}

run_update() {
    rm -f "$SYSTEMCTL_LOG"
    set +e
    update_output="$(cmd_agent_update --version=1.2.3 --yes 2>&1)"
    update_rc=$?
    set -e
}

# --- was running, agent_install_service fails: must still attempt restart ---
IS_ACTIVE_RC=0
START_RC=0
systemctl() {
    printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
    case "$1 ${2:-}" in
        "is-active mgate-agent") return "$IS_ACTIVE_RC" ;;
        "start mgate-agent") return "$START_RC" ;;
    esac
    return 0
}
agent_install_service() { return 1; }
agent_install_config() { return 0; }
agent_check_if_enrolled() { return 0; }
run_update
[ "$update_rc" -ne 0 ] || { printf 'expected rc!=0 when agent_install_service fails: %s\n' "$update_output" >&2; exit 1; }
assert_contains "$(cat "$SYSTEMCTL_LOG")" 'start mgate-agent'

# --- was running, agent_install_config fails: must still attempt restart ---
agent_install_service() { return 0; }
agent_install_config() { return 1; }
run_update
[ "$update_rc" -ne 0 ] || { printf 'expected rc!=0 when agent_install_config fails: %s\n' "$update_output" >&2; exit 1; }
assert_contains "$(cat "$SYSTEMCTL_LOG")" 'start mgate-agent'

# --- was running, agent_check_if_enrolled fails: must still attempt restart ---
agent_install_config() { return 0; }
agent_check_if_enrolled() { return 1; }
run_update
[ "$update_rc" -ne 0 ] || { printf 'expected rc!=0 when agent_check_if_enrolled fails: %s\n' "$update_output" >&2; exit 1; }
assert_contains "$(cat "$SYSTEMCTL_LOG")" 'start mgate-agent'

# --- was NOT running beforehand: a failure must NOT spuriously start it ---
IS_ACTIVE_RC=1
agent_install_service() { return 1; }
agent_check_if_enrolled() { return 0; }
run_update
[ "$update_rc" -ne 0 ] || { printf 'expected rc!=0: %s\n' "$update_output" >&2; exit 1; }
assert_not_contains "$(cat "$SYSTEMCTL_LOG")" 'start mgate-agent'

# --- happy path: was running, everything succeeds -> restarted, rc=0 ---
IS_ACTIVE_RC=0
START_RC=0
agent_install_service() { return 0; }
agent_install_config() { return 0; }
agent_check_if_enrolled() { return 0; }
run_update
[ "$update_rc" -eq 0 ] || { printf 'expected rc=0 for happy path: %s\n' "$update_output" >&2; exit 1; }
assert_contains "$(cat "$SYSTEMCTL_LOG")" 'start mgate-agent'

# --- was running, everything up to and including the final restart step
#     itself fails: must return non-zero (the real systemctl exit code),
#     never warn-and-still-report-success ---
IS_ACTIVE_RC=0
START_RC=9
agent_install_service() { return 0; }
agent_install_config() { return 0; }
agent_check_if_enrolled() { return 0; }
run_update
[ "$update_rc" -eq 9 ] || { printf 'expected rc=9 (propagated systemctl start failure), got %s: %s\n' "$update_rc" "$update_output" >&2; exit 1; }

printf 'agent update recovery contract: OK\n'
