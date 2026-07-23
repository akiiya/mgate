#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WORK_DIR=/tmp/mgate-test-upgradeworker.$$
mkdir -p "$WORK_DIR"
MGATE_AGENT_UPGRADE_STATUS_FILE="$WORK_DIR/combined-upgrade-status.json"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

logger() { :; }

assert_contains() {
    printf '%s' "$1" | grep -q "$2" || {
        printf 'expected to find: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

status_content() { cat "$MGATE_AGENT_UPGRADE_STATUS_FILE" 2>/dev/null || printf '(no file)\n'; }

ORDER_LOG="$WORK_DIR/order.log"
log_order() { printf '%s\n' "$1" >> "$ORDER_LOG"; }
order_content() { cat "$ORDER_LOG" 2>/dev/null || printf '(no file)\n'; }

run_worker() {
    rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE" "$ORDER_LOG"
    set +e
    worker_output="$( ( cmd_agent_combined_upgrade_worker "$@" ) 2>&1 )"
    worker_rc=$?
    set -e
}

# --- happy path: migrate succeeds, agent update succeeds -> succeeded ---
cmd_migrate() { return 0; }
cmd_agent_update() { return 0; }
run_worker
[ "$worker_rc" -eq 0 ] || { printf 'expected rc=0 for happy path: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"succeeded"'
assert_contains "$(status_content)" '"exit_code":0'

# --- migrate fails -> failed, agent update must NEVER be attempted ---
cmd_migrate() { return 7; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when migrate fails: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"exit_code":7'

# --- migrate succeeds, agent update fails -> failed, with its own exit code ---
cmd_migrate() { return 0; }
cmd_agent_update() { return 3; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when agent update fails: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"exit_code":3'

# --- a die()/exit deep inside either step must not prevent the failure
#     status from being recorded (subshell isolation) ---
cmd_migrate() { exit 42; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when migrate exits hard: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"exit_code":42'

# --- worker rejects any arguments outright (fixed, zero-argument internal
#     command) -- must refuse before ever writing "running", not merely
#     ignore the extra args ---
cmd_migrate() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker unexpected-arg
[ "$worker_rc" -eq 2 ] || { printf 'expected rc=2 for unexpected args, got %s: %s\n' "$worker_rc" "$worker_output" >&2; exit 1; }
[ "$(status_content)" = "(no file)" ] || {
    printf 'status file must be untouched when args are rejected: %s\n' "$(status_content)" >&2
    exit 1
}

# =====================================================================
# Web restart chain: migrate -> conditional web restart -> agent update.
# =====================================================================

# --- regression for the "stop silently fails, start is a no-op" scenario
#     agent_web_restart_strict exists to catch: simulate systemd mode where
#     `systemctl restart` itself reports success (many systemd versions
#     return 0 even when the underlying unit failed to actually restart
#     cleanly) but the service is NOT actually active afterward -- the
#     independent post-restart is-active re-check must catch this and the
#     worker must still fail, never proceeding to agent update. This exercises
#     the REAL agent_web_restart_strict() (must run before any later test in
#     this file mocks it away). ---
cmd_migrate() { return 0; }
web_is_running_quiet() { return 0; }
need_root() { :; }
detect_service_mode() { printf 'systemd\n'; }
WEB_SYSTEMD_SERVICE_LINK="$WORK_DIR/mgate-web.service.link"
: > "$WEB_SYSTEMD_SERVICE_LINK"
systemctl() {
    case "$1" in
        restart) return 0 ;;
        is-active) return 1 ;;
    esac
    return 0
}
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when restart succeeds but service is not actually active: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"message":"web restart step failed"'

# --- Web was running before migrate: strict order migrate -> web restart ->
#     agent update, all three actually invoked. The worker must use the
#     STRICT restart helper (agent_web_restart_strict), never the
#     human-facing web_restart(). ---
cmd_migrate() { log_order migrate; return 0; }
web_is_running_quiet() { return 0; }
agent_web_restart_strict() { log_order web_restart; return 0; }
web_restart() { printf 'MUST NOT BE CALLED (human-facing web_restart)\n' >&2; exit 99; }
cmd_agent_update() { log_order agent_update; return 0; }
run_worker
[ "$worker_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$worker_output" >&2; exit 1; }
[ "$(order_content)" = "$(printf 'migrate\nweb_restart\nagent_update')" ] || {
    printf 'expected strict order migrate,web_restart,agent_update; got:\n%s\n' "$(order_content)" >&2
    exit 1
}
assert_contains "$(status_content)" '"state":"succeeded"'

# --- Web was NOT running before migrate: the restart helper must never be
#     called, agent update still proceeds normally ---
cmd_migrate() { log_order migrate; return 0; }
web_is_running_quiet() { return 1; }
agent_web_restart_strict() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
cmd_agent_update() { log_order agent_update; return 0; }
run_worker
[ "$worker_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$worker_output" >&2; exit 1; }
[ "$(order_content)" = "$(printf 'migrate\nagent_update')" ] || {
    printf 'expected order migrate,agent_update (no web restart); got:\n%s\n' "$(order_content)" >&2
    exit 1
}
assert_contains "$(status_content)" '"state":"succeeded"'

# --- migrate fails: the restart helper and agent update must never be
#     attempted, regardless of whether Web was running before ---
cmd_migrate() { return 5; }
web_is_running_quiet() { return 0; }
agent_web_restart_strict() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when migrate fails: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"message":"migrate step failed"'
assert_contains "$(status_content)" '"exit_code":5'

# --- Web was running, migrate succeeds, but the strict restart itself fails
#     (e.g. stop silently failed to actually kill the old process, so start
#     became a no-op and the post-restart liveness re-check fails): the
#     worker must record the REAL exit code and must never proceed to agent
#     update ---
cmd_migrate() { return 0; }
web_is_running_quiet() { return 0; }
agent_web_restart_strict() { return 9; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
run_worker
[ "$worker_rc" -ne 0 ] || { printf 'expected rc!=0 when web restart fails: %s\n' "$worker_output" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"message":"web restart step failed"'
assert_contains "$(status_content)" '"exit_code":9'

# --- Web was running, migrate succeeds, strict restart succeeds: agent
#     update must still run and the worker must still end up succeeded ---
cmd_migrate() { log_order migrate; return 0; }
web_is_running_quiet() { return 0; }
agent_web_restart_strict() { log_order web_restart; return 0; }
cmd_agent_update() { log_order agent_update; return 0; }
run_worker
[ "$worker_rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$worker_output" >&2; exit 1; }
[ "$(order_content)" = "$(printf 'migrate\nweb_restart\nagent_update')" ] || {
    printf 'expected strict order migrate,web_restart,agent_update; got:\n%s\n' "$(order_content)" >&2
    exit 1
}
assert_contains "$(status_content)" '"state":"succeeded"'

# =====================================================================
# Worker signal handling: must never leave "running" stuck forever if the
# transient unit is stopped by INT/TERM/HUP.
# =====================================================================

# --- worker already reporting "running" (mid-migrate) receives TERM: status
#     must transition to a definitive, retriable "failed" with the real
#     128+signal exit code -- never left stuck at "running" ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
cmd_migrate() { sleep 5; return 0; }
web_is_running_quiet() { return 1; }
cmd_agent_update() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
( cmd_agent_combined_upgrade_worker ) &
worker_bgpid=$!
waited=0
while ! printf '%s' "$(status_content)" | grep -q '"state":"running"' && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
printf '%s' "$(status_content)" | grep -q '"state":"running"' || {
    printf 'worker never reached "running" before sending TERM\n' >&2
    exit 1
}
kill -TERM "$worker_bgpid" 2>/dev/null || true
set +e
wait "$worker_bgpid" 2>/dev/null
worker_term_rc=$?
set -e
[ "$worker_term_rc" -eq 143 ] || { printf 'expected exit 143 after TERM, got: %s\n' "$worker_term_rc" >&2; exit 1; }
assert_contains "$(status_content)" '"state":"failed"'
assert_contains "$(status_content)" '"message":"combined upgrade interrupted"'
assert_contains "$(status_content)" '"exit_code":143'

printf 'agent upgrade worker contract: OK\n'
