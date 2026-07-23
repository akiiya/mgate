#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

DATA_DIR=/tmp/mgate-test-sub-data.$$
CONFIG_DIR=/tmp/mgate-test-sub-config.$$
mkdir -p "$DATA_DIR" "$CONFIG_DIR/providers"
SUB_URL_FILE="$DATA_DIR/sub.url"
SUB_PROVIDER_FILE="$CONFIG_DIR/providers/sub.yaml"
CORE_BIN=/tmp/mgate-test-sub-core.$$
CONFIG_FILE=/tmp/mgate-test-sub-config.$$.yaml
rm -f "$SUB_URL_FILE"

cleanup() { rm -rf "$DATA_DIR" "$CONFIG_DIR" "$CORE_BIN" "$CONFIG_FILE"; }
trap cleanup EXIT

agent_module_check_core() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
tproxy_is_root() { return 0; }
pkg_manager_install_available() { return 0; }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

run_prepare() {
    set +e
    prepare_output="$(cmd_agent_subscription_prepare_json)"
    prepare_rc=$?
    set -e
}

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- no URL configured: not_configured must win, even though curl/CA are
#     independently missing and remediable ---
have() { case "$1" in curl|wget) return 1 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_configured\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_configured"'

# --- URL configured and valid, but curl/CA missing: installable ---
echo "https://example.com/sub" > "$SUB_URL_FILE"
touch "$SUB_PROVIDER_FILE" "$CONFIG_FILE"
printf '#!/bin/sh\nexit 0\n' > "$CORE_BIN"
chmod +x "$CORE_BIN"
pkg_manager_install() { printf 'install: %s\n' "$1" >&2; return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"curl"'
assert_contains "$prepare_output" '"ca-certificates"'

# --- already ready ---
have() { command -v "$1" >/dev/null 2>&1; }
sub_ca_certificates_present() { return 0; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'

# --- blocked on core ---
agent_module_check_core() { module_check_reset; module_check_add "x" "missing_dependencies" "true" "no binary"; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when blocked on core\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"blocked"'

# --- subscription content present but fails validation: sole
#     missing_dependencies driver, but not remediable (user-authored content,
#     not a dependency) -- must fail, not silently report ok:true ---
agent_module_check_core() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
have() { command -v "$1" >/dev/null 2>&1; }
sub_ca_certificates_present() { return 0; }
echo "https://example.com/sub" > "$SUB_URL_FILE"
rm -f "$SUB_PROVIDER_FILE"
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when nothing is remediable: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"code":"missing_dependencies"'

# --- dir_writable is the sole remediable item, and it does NOT need a package
#     manager (ensure_dirs only) -- package_manager_unavailable must not fire
#     just because apt/apt-get happen to be absent ---
touch "$SUB_PROVIDER_FILE"
pkg_manager_install_available() { return 1; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { return 0; }
DATA_DIR=/nonexistent-dir-for-test.$$
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 (ensure_dirs alone needs no package manager): %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"data_dirs"'
DATA_DIR="$(dirname "$SUB_URL_FILE")"
pkg_manager_install_available() { return 0; }

# --- download_tool AND dir_writable both remediable, but no package manager:
#     dir_writable must still be attempted via ensure_dirs (doesn't need a
#     package manager) even though the curl install can't happen -- must not
#     bail out early and skip dir_writable just because curl is also missing ---
have() { case "$1" in curl|wget) return 1 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
sub_ca_certificates_present() { return 0; }
pkg_manager_install_available() { return 1; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
ensure_dirs() { return 0; }
DATA_DIR=/nonexistent-dir-for-test2.$$
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc (curl still uninstallable): %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"data_dirs"'
DATA_DIR="$(dirname "$SUB_URL_FILE")"
pkg_manager_install_available() { return 0; }
have() { command -v "$1" >/dev/null 2>&1; }

printf 'agent subscription-prepare contract: OK\n'
