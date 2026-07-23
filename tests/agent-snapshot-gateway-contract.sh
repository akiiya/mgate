#!/bin/sh
set -eu

PATH=/usr/bin:/bin:$PATH
export PATH

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

AP_IF=ap0
AP_UPSTREAM=wlan0
AP_SSID=mgate
AP_PASSWORD=mgate12345678
ap_load_config() { :; }
gateway_transparent_proxy_state() { printf 'disabled\n'; }
gateway_subnet() { printf '10.88.0.0/24\n'; }
gateway_ip_forward_value() { printf '1\n'; }
cat() {
    if [ "${1:-}" = "/proc/sys/net/ipv4/ip_forward" ]; then
        printf '1\n'
    else
        command cat "$@"
    fi
}
iptables() { return 1; }

gateway_rules_active() {
    [ "${TEST_GATEWAY_ACTIVE:-false}" = "true" ]
}

expect_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'missing JSON fragment: %s\n' "$2" >&2
        exit 1
    }
}

expect_gateway_state() {
    TEST_GATEWAY_ACTIVE="$1"
    export TEST_GATEWAY_ACTIVE
    snapshot="$(cmd_agent_snapshot)"
    printf '%s' "$snapshot" | python -c 'import json, sys; json.load(sys.stdin)'
    expect_contains "$snapshot" '"nat_active": '"$1"
    expect_contains "$snapshot" '"ipv4_forwarding": true'

    status="$(cmd_gateway_status)"
    if [ "$1" = "true" ]; then
        expect_contains "$status" 'nat rules active: yes'
    else
        expect_contains "$status" 'nat rules active: no'
    fi
}

# iptables() deliberately exposes no MASQUERADE output. The snapshot must
# still trust gateway_rules_active(), just like gateway-status does.
expect_gateway_state true
expect_gateway_state false

printf 'agent snapshot gateway contract: OK\n'
