#!/bin/sh
set -eu

PATH=/usr/bin:/bin:$PATH
export PATH

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WIFI_IF=wlan0
TEST_WIFI_LIST_MODE=profiles

nmcli() {
    case "${TEST_WIFI_LIST_MODE}:$*" in
        profiles:-t\ -f\ NAME,TYPE,AUTOCONNECT-PRIORITY\ connection\ show)
            printf '%s\n' 'work-wifi-1:wifi:60'
            printf '%s\n' '中文 空格 WiFi:802-11-wireless:80'
            printf '%s\n' 'home-wifi-1:802-11-wireless:100'
            ;;
        empty:-t\ -f\ NAME,TYPE,AUTOCONNECT-PRIORITY\ connection\ show)
            return 0
            ;;
        fail:-t\ -f\ NAME,TYPE,AUTOCONNECT-PRIORITY\ connection\ show)
            return 7
            ;;
        *:-t\ -f\ DEVICE,CONNECTION\ dev\ status)
            printf '%s\n' 'wlan0:中文 空格 WiFi'
            ;;
        *) return 1 ;;
    esac
}

assert_json_profiles() {
    printf '%s' "$1" | python -c '
import json, sys
saved = json.load(sys.stdin)["saved"]
assert [item["priority"] for item in saved] == [100, 80, 60], saved
assert saved[0] == {"ssid": "home-wifi-1", "priority": 100, "connected": False}, saved
assert saved[1]["ssid"].endswith(" WiFi") and " " in saved[1]["ssid"], saved
assert any(ord(ch) > 127 for ch in saved[1]["ssid"]), saved
assert saved[1]["connected"] is True, saved
assert saved[2] == {"ssid": "work-wifi-1", "priority": 60, "connected": False}, saved
'
}

# 802-11-wireless、wifi、优先级排序、中文/空格 SSID 与当前连接状态。
output="$(cmd_agent_wifi_list_json)"
assert_json_profiles "$output"

# nmcli 成功但没有 profile 时，才返回成功空数组。
TEST_WIFI_LIST_MODE=empty
output="$(cmd_agent_wifi_list_json)"
[ "$output" = '{"saved":[]}' ] || { printf 'unexpected empty output: %s\n' "$output" >&2; exit 1; }
printf '%s' "$output" | python -c 'import json, sys; assert json.load(sys.stdin) == {"saved": []}'

# nmcli 采集失败时，不能伪装成成功空数组；Agent 上下文必须保留失败退出码。
TEST_WIFI_LIST_MODE=fail
err_file=$(mktemp)
MGATE_AGENT_CONTEXT=1
export MGATE_AGENT_CONTEXT
set +e
output="$(main wifi-list 2>"$err_file")"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected non-zero result for nmcli failure\n' >&2; exit 1; }
[ -z "$output" ] || { printf 'unexpected failure stdout: %s\n' "$output" >&2; exit 1; }
grep -q 'wifi-list' "$err_file" || { printf 'missing safe failure message\n' >&2; exit 1; }
rm -f "$err_file"

# nmcli 不存在时同样必须失败，且不得返回空数组。
have() { [ "$1" != nmcli ]; }
err_file=$(mktemp)
set +e
output="$(cmd_agent_wifi_list_json 2>"$err_file")"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected non-zero result for missing nmcli\n' >&2; exit 1; }
[ -z "$output" ] || { printf 'unexpected missing-nmcli stdout: %s\n' "$output" >&2; exit 1; }
grep -q 'nmcli' "$err_file" || { printf 'missing nmcli failure message\n' >&2; exit 1; }
rm -f "$err_file"

printf 'agent wifi-list contract: OK\n'
