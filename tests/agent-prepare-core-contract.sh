#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

CORE_BIN=/tmp/mgate-test-core-bin.$$
CONFIG_FILE=/tmp/mgate-test-core-config.$$.yaml
RUN_DIR=/tmp/mgate-test-core-run.$$
DATA_DIR=/tmp/mgate-test-core-data.$$
LOG_DIR=/tmp/mgate-test-core-log.$$
mkdir -p "$RUN_DIR" "$DATA_DIR" "$LOG_DIR"
rm -f "$CORE_BIN" "$CONFIG_FILE"

cleanup() { rm -rf "$RUN_DIR" "$DATA_DIR" "$LOG_DIR" "$CORE_BIN" "$CONFIG_FILE"; }
trap cleanup EXIT

detect_service_mode() { printf 'plain\n'; }
tproxy_is_root() { return 0; }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

run_prepare() {
    # Captures cmd_agent_core_prepare_json's stdout AND exit code without
    # letting a non-zero (expected) return abort this test script under -e.
    set +e
    prepare_output="$(cmd_agent_core_prepare_json)"
    prepare_rc=$?
    set -e
}

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"ok":false'
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- already ready: must not call install_core/generate_config/ensure_dirs ---
printf '#!/bin/sh\nexit 0\n' > "$CORE_BIN"
chmod +x "$CORE_BIN"
: > "$CONFIG_FILE"
install_core() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
generate_config() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready\n' >&2; exit 1; }
assert_contains "$prepare_output" '"ok":true'
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'
assert_contains "$prepare_output" '"changed":\[\]'

# --- missing binary + config: prepare installs them, reports what changed ---
rm -f "$CORE_BIN" "$CONFIG_FILE"
install_core() { printf '#!/bin/sh\nexit 0\n' > "$CORE_BIN"; chmod +x "$CORE_BIN"; }
generate_config() { : > "$CONFIG_FILE"; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for successful prepare\n' >&2; exit 1; }
assert_contains "$prepare_output" '"ok":true'
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"after":{"state":"ready"}'
assert_contains "$prepare_output" '"mihomo_binary"'
assert_contains "$prepare_output" '"config.yaml"'

# --- remediation step fails: reported as ok:false, not a silent success ---
rm -f "$CORE_BIN" "$CONFIG_FILE"
install_core() { return 1; }
generate_config() { : > "$CONFIG_FILE"; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for failed install\n' >&2; exit 1; }
assert_contains "$prepare_output" '"ok":false'
assert_contains "$prepare_output" '"code":"install_failed"'

# --- broken binary + invalid config: both missing_dependencies but neither
#     remediable (present-but-broken is not something prepare should
#     overwrite) -- must fail, not silently report ok:true with changed:[] ---
printf '#!/bin/sh\nexit 1\n' > "$CORE_BIN"
chmod +x "$CORE_BIN"
: > "$CONFIG_FILE"
install_core() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
generate_config() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when nothing is remediable: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"ok":false'
assert_contains "$prepare_output" '"code":"missing_dependencies"'

printf 'agent core-prepare contract: OK\n'
