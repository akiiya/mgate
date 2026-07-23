#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

cmd_ap_start() {
    printf 'password=do-not-upload\n'
    return 0
}

cmd_ap_stop() {
    printf 'token=do-not-upload\n' >&2
    return 7
}

expect_eq() {
    [ "$1" = "$2" ] || {
        printf 'expected: %s\nactual:   %s\n' "$2" "$1" >&2
        exit 1
    }
}

json_string() {
    printf '"%s"' "$1"
}

check_no_crlf_file() {
    return 1
}

MGATE_AGENT_CONTEXT=1
export MGATE_AGENT_CONTEXT

agent_preflight=$(main preflight)
expect_eq "$agent_preflight" '{"ok":false,"checks":["POSIX shell","CRLF line endings detected"]}'

agent_success=$(main ap-start)
expect_eq "$agent_success" '{"ok":true,"message":"operation completed"}'

set +e
agent_failure=$(main ap-stop)
agent_rc=$?
set -e
[ "$agent_rc" -eq 7 ] || { printf 'agent failure exit code: %s\n' "$agent_rc" >&2; exit 1; }
expect_eq "$agent_failure" '{"ok":false,"message":"operation failed"}'

MGATE_AGENT_CONTEXT=0
export MGATE_AGENT_CONTEXT
local_output=$(main ap-start)
expect_eq "$local_output" 'password=do-not-upload'

printf 'agent context mutation contract: OK\n'
