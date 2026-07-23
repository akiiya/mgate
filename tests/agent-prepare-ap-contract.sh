#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WIFI_IF=wlan0
AP_IF=ap0
AP_UPSTREAM=wlan0
AP_IPADDR=10.88.0.1
AP_SSID=mgate
AP_PASSWORD=mgate12345678

ap_load_config() { :; }
interface_exists() { [ "$1" = "wlan0" ]; }
ip() { return 1; }
tproxy_is_root() { return 0; }
pkg_manager_install_available() { return 0; }

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

run_prepare() {
    set +e
    prepare_output="$(cmd_agent_ap_prepare_json)"
    prepare_rc=$?
    set -e
}

# wifi ready throughout this file unless a case overrides it
agent_module_check_wifi() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- already ready: must not attempt package install ---
have() { case "$1" in hostapd|dnsmasq|iw|ip) return 0 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready (got %s): %s\n' "$prepare_rc" "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'

# --- missing hostapd/dnsmasq: installs, reports exactly what was missing ---
have() { case "$1" in hostapd|dnsmasq) return 1 ;; *) return 0 ;; esac }
pkg_manager_install() { printf 'install: %s\n' "$1" >&2; return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for successful prepare: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"hostapd"'
assert_contains "$prepare_output" '"dnsmasq"'
assert_not_contains "$prepare_output" '"iw"'

# --- wifi module not ready: ap must report blocked, must not attempt install ---
agent_module_check_wifi() { module_check_reset; module_check_add "x" "unsupported" "false" "no manager"; }
have() { command -v "$1" >/dev/null 2>&1; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when blocked on wifi\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"blocked"'

# --- subnet conflict is the sole missing_dependencies driver, but it's not
#     remediable -- must fail, not silently report ok:true with changed:[] ---
agent_module_check_wifi() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
have() { case "$1" in hostapd|dnsmasq|iw|ip) return 0 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
ap_subnet_conflict_detected() { return 0; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when nothing is remediable: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"code":"missing_dependencies"'

printf 'agent ap-prepare contract: OK\n'
