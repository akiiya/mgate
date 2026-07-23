#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

# Integration coverage: the combined-upgrade worker calling the REAL (not
# mocked) cmd_agent_update, whose final "restart mgate-agent" step fails.
# The worker must end up "failed" with the real, propagated exit code --
# never "succeeded" just because migrate + the bulk of the update worked.

WORK_DIR=/tmp/mgate-test-workerrestart.$$
mkdir -p "$WORK_DIR/pkg"
MGATE_AGENT_UPGRADE_STATUS_FILE="$WORK_DIR/combined-upgrade-status.json"
MGATE_AGENT_BIN="$WORK_DIR/mgate-agent"
TMP_DIR="$WORK_DIR/tmp"
MGATE_AGENT_CONFIG_FILE="$WORK_DIR/agent.yaml"
mkdir -p "$TMP_DIR"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

logger() { :; }
cmd_migrate() { return 0; }

# cmd_agent_update's own low-level dependencies -- everything succeeds
# except the final "systemctl start mgate-agent" restart.
need_root() { :; }
agent_detect_arch() { printf 'amd64\n'; }
agent_load_token() { :; }
agent_get_latest_version() { printf 'v1.2.3\n'; }
agent_get_installed_version() { printf 'v1.0.0\n'; }
agent_download_and_verify() {
    AGENT_DOWNLOAD_BIN_PATH="$WORK_DIR/pkg/mgate-agent"
    printf '#!/bin/sh\nexit 0\n' > "$AGENT_DOWNLOAD_BIN_PATH"
    chmod +x "$AGENT_DOWNLOAD_BIN_PATH"
    return 0
}
agent_install_service() { return 0; }
agent_install_config() { return 0; }
agent_warn_legacy_config() { :; }
agent_check_if_enrolled() { return 0; }
have() { [ "$1" = "systemctl" ] || command -v "$1" >/dev/null 2>&1; }
systemctl() {
    case "$1 ${2:-}" in
        "is-active mgate-agent") return 0 ;;   # was running before update
        "start mgate-agent") return 5 ;;       # final restart fails
    esac
    return 0
}

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

status_content() { cat "$MGATE_AGENT_UPGRADE_STATUS_FILE" 2>/dev/null || printf '(no file)\n'; }

# --- sanity check: cmd_agent_update itself must surface the real failure ---
set +e
cmd_agent_update --version=1.2.3 --yes >/dev/null 2>&1
au_rc=$?
set -e
[ "$au_rc" -eq 5 ] || { printf 'expected cmd_agent_update rc=5 (propagated systemctl start failure), got %s\n' "$au_rc" >&2; exit 1; }

# --- the worker must end up "failed" with that same real exit code, never
#     "succeeded" ---
set +e
worker_output="$( ( cmd_agent_combined_upgrade_worker ) 2>&1 )"
worker_rc=$?
set -e
[ "$worker_rc" -ne 0 ] || { printf 'expected worker rc!=0 when the restart step fails: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"exit_code":5'

printf 'agent worker restart-failure contract: OK\n'
