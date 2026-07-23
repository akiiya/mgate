#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

ap_load_config() { :; }
gateway_rules_active() { return 0; }
tproxy_is_root() { return 0; }
pkg_manager_install_available() { return 0; }

# core/ap/gateway ready throughout unless a case overrides it
agent_module_check_core() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
agent_module_check_ap() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
agent_module_check_gateway() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

run_prepare() {
    set +e
    prepare_output="$(cmd_agent_tproxy_prepare_json)"
    prepare_rc=$?
    set -e
}

# --- not root ---
tproxy_is_root() { return 1; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for not_root\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"not_root"'
tproxy_is_root() { return 0; }

# --- everything ready: no-op success ---
have() { case "$1" in ip|iptables) return 0 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
gateway_have_iptables() { have iptables; }
gateway_ip_forward_value() { printf '1\n'; }
tproxy_target_available() { return 0; }
tproxy_kernel_module_state() { printf 'loaded\n'; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0 for already-ready: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"message":"already ready, nothing to prepare"'

# --- iptables entirely missing: must be missing_dependencies (installable),
#     NOT misclassified as kernel-unsupported ---
have() { [ "$1" != "iptables" ]; }
gateway_have_iptables() { have iptables; }
pkg_manager_install() { printf 'install: %s\n' "$1" >&2; return 0; }
run_prepare
[ "$prepare_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"before":{"state":"missing_dependencies"}'
assert_contains "$prepare_output" '"iptables"'

# --- genuine kernel-level unsupported: must refuse, never attempt anything ---
have() { case "$1" in ip|iptables) return 0 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
gateway_have_iptables() { have iptables; }
tproxy_target_available() { return 1; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc for kernel-unsupported\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"unsupported"'

# --- blocked on an upstream module (e.g. gateway not ready) ---
tproxy_target_available() { return 0; }
agent_module_check_gateway() { module_check_reset; module_check_add "x" "blocked" "false" "not ready"; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when blocked on gateway\n' >&2; exit 1; }
assert_contains "$prepare_output" '"code":"blocked"'

# --- ip_forward disabled is the sole missing_dependencies driver, but it's
#     deliberately never remediable -- must fail, not silently report ok:true
#     with changed:[] (flipping ip_forward would half-start tproxy) ---
have() { case "$1" in ip|iptables) return 0 ;; *) command -v "$1" >/dev/null 2>&1 ;; esac }
gateway_have_iptables() { have iptables; }
tproxy_target_available() { return 0; }
tproxy_kernel_module_state() { printf 'loaded\n'; }
gateway_ip_forward_value() { printf '0\n'; }
agent_module_check_gateway() { module_check_reset; module_check_add "x" "ready" "false" "ok"; }
pkg_manager_install() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_prepare
[ "$prepare_rc" -ne 0 ] || { printf 'expected non-zero rc when nothing is remediable: %s\n' "$prepare_output" >&2; exit 1; }
assert_contains "$prepare_output" '"code":"missing_dependencies"'

printf 'agent tproxy-prepare contract: OK\n'
