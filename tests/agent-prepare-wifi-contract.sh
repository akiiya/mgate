#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WIFI_IF=wlan0
tproxy_is_root() { return 0; }

# ready baseline throughout this file unless a case overrides it
wifi_if_exists() { return 0; }
wifi_detect_manager() { printf 'NetworkManager\n'; }
wifi_rfkill_state() { printf 'unblocked\n'; }
wifi_list_profiles() { printf 'home-network\n'; }

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
    prepare_output="$(cmd_agent_wifi_prepare_json)"
    prepare_rc=$?
    set -e
}

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- already ready: must not attempt rfkill unblock ---
wifi_prepare_rfkill_unblock() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready (got %s): %s\n' "$prepare_rc" "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'

# --- rfkill soft-blocked: auto-unblock, reports exactly what changed ---
wifi_rfkill_state() { printf 'soft\n'; }
wifi_prepare_rfkill_unblock() { return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for soft-block prepare: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"rfkill_unblock"'
wifi_rfkill_state() { printf 'unblocked\n'; }

# --- no supported wifi manager: unsupported, must never install/enable one ---
wifi_detect_manager() { printf 'unknown\n'; }
wifi_prepare_rfkill_unblock() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for no-manager\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"unsupported"'
wifi_detect_manager() { printf 'NetworkManager\n'; }

# --- rfkill hard-blocked: unsupported, no fix attempted ---
wifi_rfkill_state() { printf 'hard\n'; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for hard-block\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"unsupported"'
wifi_rfkill_state() { printf 'unblocked\n'; }

# --- no wireless interface at all: unsupported, failure JSON has no changed[] ---
wifi_if_exists() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for no-interface\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"unsupported"'
assert_not_contains "$prepare_output" '"changed"'

wifi_if_exists() { return 0; }

# --- profile_configured must recognize wpa_supplicant-saved networks, not
#     only NetworkManager ones (a permanently not_configured wifi module would
#     cap ap/gateway/tproxy below ready on any wpa_supplicant-based device) ---
wifi_detect_manager() { printf 'wpa_supplicant\n'; }
have() { [ "$1" = "wpa_cli" ] || command -v "$1" >/dev/null 2>&1; }
wpa_cli() {
    case "$3" in
        list_networks) printf 'network id / ssid / bssid / flags\n0\thome-network\tany\t[CURRENT]\n' ;;
    esac
}
agent_module_check_wifi
assert_contains "$(module_check_emit)" '"id":"profile_configured","state":"ready"'

wpa_cli() { printf 'network id / ssid / bssid / flags\n'; }
agent_module_check_wifi
assert_contains "$(module_check_emit)" '"id":"profile_configured","state":"not_configured"'
wifi_detect_manager() { printf 'NetworkManager\n'; }

printf 'agent wifi-prepare contract: OK\n'
