#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

AP_UPSTREAM=wlan0
ap_load_config() { :; }
tproxy_is_root() { return 0; }
pkg_manager_install_available() { return 0; }

agent_module_check_ap() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
agent_module_check_wifi() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
ip() { case "$1" in route) printf 'default via 1.2.3.4 dev wlan0\n' ;; *) return 1 ;; esac }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

run_prepare() {
    set +e
    prepare_output="$(cmd_agent_gateway_prepare_json)"
    prepare_rc=$?
    set -e
}

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- already ready: no-op ---
have() { [ "$1" = "iptables" ] || command -v "$1" >/dev/null 2>&1; }
gateway_have_iptables() { have iptables; }
gateway_ip_forward_value() { printf '1\n'; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'

# --- iptables missing: installable, ip_forward never touched even if it's
#     ALSO not ready (must not be attempted / included as an install target) ---
have() { [ "$1" != "iptables" ]; }
gateway_have_iptables() { have iptables; }
gateway_ip_forward_value() { printf '0\n'; }
pkg_manager_install() { printf 'install: %s\n' "$1" >&2; return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"iptables"'

# --- blocked on ap ---
have() { [ "$1" = "iptables" ] || command -v "$1" >/dev/null 2>&1; }
gateway_have_iptables() { have iptables; }
agent_module_check_ap() { module_check_reset; module_check_add "x" "not_configured" "false" "no ssid"; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when blocked on ap\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"blocked"'

# --- ip_forward disabled is the sole missing_dependencies driver, but it's
#     deliberately never remediable -- must fail, not silently report ok:true
#     with changed:[] (flipping ip_forward would half-start gateway) ---
have() { [ "$1" = "iptables" ] || command -v "$1" >/dev/null 2>&1; }
gateway_have_iptables() { have iptables; }
gateway_ip_forward_value() { printf '0\n'; }
agent_module_check_ap() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when nothing is remediable: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"code":"missing_dependencies"'

# --- iptables present but ip (iproute2) missing: nat_iptables_backend must
#     still report missing_dependencies, not a false "ready" that would leave
#     iproute2 uninstalled ---
have() { [ "$1" != "ip" ]; }
gateway_have_iptables() { have iptables; }
gateway_ip_forward_value() { printf '1\n'; }
pkg_manager_install() { printf 'install: %s\n' "$1" >&2; return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"iptables"'

printf 'agent gateway-prepare contract: OK\n'
