#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WORK_DIR=/tmp/mgate-test-selfupdate.$$
FAKE_BIN_DIR="$WORK_DIR/fakebin"
mkdir -p "$WORK_DIR" "$FAKE_BIN_DIR"
SCRIPT_PATH="$WORK_DIR/mgate.sh"
GLOBAL_BIN="$WORK_DIR/bin/mgate"
SELF_URL_FILE="$WORK_DIR/self-url"
TMP_DIR="$WORK_DIR/tmp"
mkdir -p "$TMP_DIR"
SYSTEMD_RUN_LOG="$WORK_DIR/systemd-run.log"
MGATE_AGENT_UPGRADE_STATUS_FILE="$WORK_DIR/combined-upgrade-status.json"
MGATE_AGENT_UPGRADE_LOCK_DIR="$WORK_DIR/agent-upgrade-schedule.lock"

# `systemd-run` (and other hyphenated commands) cannot be mocked as shell
# functions -- POSIX function names must be valid identifiers, and dash/
# BusyBox ash reject a hyphen ("not a valid identifier"). Mocking via a fake
# executable on PATH works under every POSIX shell instead.
PATH="$FAKE_BIN_DIR:$PATH"
export PATH

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

logger() { :; }

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

status_state() {
    [ -f "$MGATE_AGENT_UPGRADE_STATUS_FILE" ] || { printf '(no file)\n'; return; }
    cat "$MGATE_AGENT_UPGRADE_STATUS_FILE"
}

# =====================================================================
# Part 1: agent_schedule_combined_upgrade()'s own behavior, tested via the
# REAL function -- must run before anything below shadows it with a mock.
# =====================================================================

# --- systemd-run unavailable -> refuse, must not fall back to any
#     in-cgroup background execution, and must record "failed" ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
have() { [ "$1" != "systemd-run" ]; }
set +e
output="$(agent_schedule_combined_upgrade 2>&1)"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when systemd-run missing: %s\n' "$output" >&2; exit 1; }
assert_contains "$(status_state)" '"state":"failed"'
have() { command -v "$1" >/dev/null 2>&1; }

# --- concurrent schedule refused: must never invoke systemd-run when a
#     prior upgrade unit is still active, and must NOT clobber the existing
#     status (a genuinely running upgrade's own status stays authoritative) ---
before_refuse="$(status_state)"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
printf 'MUST NOT BE CALLED\n' >&2
exit 99
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 0 ;;
    esac
    return 1
}
set +e
agent_schedule_combined_upgrade
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when upgrade unit already active\n' >&2; exit 1; }
[ "$(status_state)" = "$before_refuse" ] || {
    printf 'status file must be untouched by a refused duplicate schedule\nbefore: %s\nafter: %s\n' \
        "$before_refuse" "$(status_state)" >&2
    exit 1
}

# --- normal success path -- fixed, zero-argument internal worker command
#     only; no cloud-supplied version/URL/shell text reaches the scheduled
#     command line; status file records "scheduled" ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
cat > "$FAKE_BIN_DIR/systemd-run" <<EOF
#!/bin/sh
printf '%s\n' "\$*" > "$SYSTEMD_RUN_LOG"
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
agent_schedule_combined_upgrade
rc=$?
[ "$rc" -eq 0 ] || { printf 'expected rc=0 for successful schedule\n' >&2; exit 1; }
scheduled="$(cat "$SYSTEMD_RUN_LOG")"
assert_contains "$scheduled" "unit=${MGATE_AGENT_UPGRADE_UNIT}"
assert_contains "$scheduled" '_agent-combined-upgrade-worker'
assert_contains "$scheduled" "$SCRIPT_PATH"
assert_not_contains "$scheduled" 'migrate'
assert_not_contains "$scheduled" '/bin/sh -c'
assert_contains "$(status_state)" '"state":"scheduled"'

# --- race regression: if the worker runs (and even finishes) faster than
#     systemd-run itself returns, "scheduled" must NOT be written afterward
#     and clobber a newer, more accurate status. Simulate this by having the
#     fake systemd-run itself write "succeeded" (as if the real worker had
#     already run to completion) before returning success. ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
cat > "$FAKE_BIN_DIR/systemd-run" <<EOF
#!/bin/sh
printf '{"state":"succeeded","message":"combined upgrade succeeded","exit_code":0,"updated_at":1234567890}' \\
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
agent_schedule_combined_upgrade
rc=$?
[ "$rc" -eq 0 ] || { printf 'expected rc=0: %s\n' "$rc" >&2; exit 1; }
assert_contains "$(status_state)" '"state":"succeeded"'
assert_not_contains "$(status_state)" '"state":"scheduled"'

# --- atomic lock rejects a genuinely concurrent scheduling attempt: a
#     pre-existing lock dir (simulating another in-flight call) must cause
#     an immediate refusal without ever touching the status file or
#     invoking systemd-run at all ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
mkdir -p "$MGATE_AGENT_UPGRADE_LOCK_DIR"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
printf 'MUST NOT BE CALLED\n' >&2
exit 99
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
set +e
agent_schedule_combined_upgrade
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when the schedule lock is already held\n' >&2; exit 1; }
[ "$(status_state)" = "(no file)" ] || {
    printf 'status file must be untouched when the lock is already held: %s\n' "$(status_state)" >&2
    exit 1
}
rmdir "$MGATE_AGENT_UPGRADE_LOCK_DIR"

# --- systemd-run reports failure, but a re-check shows the unit IS active
#     (e.g. a genuine race or a stale leftover unit) -- must NOT overwrite
#     the status with "failed" when something is genuinely running; the
#     first (pre-schedule) is-active check must still see "not active" so
#     scheduling is actually attempted ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
IS_ACTIVE_CALLS_FILE="$WORK_DIR/is-active-calls"
rm -f "$IS_ACTIVE_CALLS_FILE"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service")
            _calls="$(cat "$IS_ACTIVE_CALLS_FILE" 2>/dev/null || printf '0')"
            _calls=$((_calls + 1))
            printf '%s' "$_calls" > "$IS_ACTIVE_CALLS_FILE"
            [ "$_calls" -eq 1 ] && return 1
            return 0
            ;;
    esac
    return 1
}
set +e
agent_schedule_combined_upgrade
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when systemd-run itself failed\n' >&2; exit 1; }
assert_not_contains "$(status_state)" '"state":"failed"'

# --- a lock dir left behind with NO pid marker (the tiny window right after
#     mkdir but before the marker is written, or an old-format leftover) is
#     ambiguous and must be treated as busy, never reclaimed -- covered
#     above by the "genuinely concurrent" test already asserting this; a
#     lock whose recorded holder pid is PROVABLY dead is a different,
#     unambiguous case and must be safely reclaimed (SIGKILL/power-loss
#     recovery), not left blocking self-update forever ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
mkdir -p "$MGATE_AGENT_UPGRADE_LOCK_DIR"
sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
printf '%s\n' "$dead_pid" > "$MGATE_AGENT_UPGRADE_LOCK_DIR/pid"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
agent_schedule_combined_upgrade
rc=$?
[ "$rc" -eq 0 ] || { printf 'expected rc=0 after reclaiming a stale lock with a dead holder pid\n' >&2; exit 1; }
assert_contains "$(status_state)" '"state":"scheduled"'
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir should be released after a successful schedule\n' >&2; exit 1; }

# --- a pid marker that isn't a clean positive integer (corrupt/garbage/
#     negative/zero) must be treated as busy, never auto-reclaimed, and must
#     never be deleted -- only a well-formed, confirmed-dead pid is
#     unambiguous enough to act on ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
for bogus_pid in "not-a-pid" "" "-5" "0" "12abc" "1 2"; do
    rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
    mkdir -p "$MGATE_AGENT_UPGRADE_LOCK_DIR"
    printf '%s\n' "$bogus_pid" > "$MGATE_AGENT_UPGRADE_LOCK_DIR/pid"
    systemctl() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
    cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
printf 'MUST NOT BE CALLED\n' >&2
exit 99
EOF
    chmod +x "$FAKE_BIN_DIR/systemd-run"
    set +e
    agent_schedule_combined_upgrade
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || { printf 'expected rc!=0 for bogus pid marker %s\n' "$bogus_pid" >&2; exit 1; }
    [ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || {
        printf 'lock dir must NOT be deleted for a bogus pid marker %s\n' "$bogus_pid" >&2
        exit 1
    }
    [ "$(status_state)" = "(no file)" ] || {
        printf 'status must be untouched for a bogus pid marker %s: %s\n' "$bogus_pid" "$(status_state)" >&2
        exit 1
    }
done
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"

# --- pid marker write failure after a successful mkdir must NOT report
#     success: the freshly-created lock dir must be released, "scheduled"
#     must never be written, and systemd-run must never be called -- a
#     tolerated write failure here would create a permanent, unrecoverable
#     ambiguous (no-pid-marker) lock ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
agent_upgrade_lock_finish_acquire() {
    printf 'MUST NOT SUCCEED\n' >&2
    rm -rf "$1" 2>/dev/null
    return 1
}
systemctl() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
printf 'MUST NOT BE CALLED\n' >&2
exit 99
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
set +e
agent_schedule_combined_upgrade
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when the pid marker write fails\n' >&2; exit 1; }
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir must be released when the pid marker write fails\n' >&2; exit 1; }
[ "$(status_state)" = "(no file)" ] || {
    printf 'status must be untouched when the pid marker write fails: %s\n' "$(status_state)" >&2
    exit 1
}
# restore the real behavior for subsequent tests -- MUST mirror
# agent_upgrade_lock_finish_acquire() in mgate.sh exactly, including the
# _aslu_acquired ownership-flag handling, or later tests in this file that
# rely on the EXIT trap (e.g. the TERM-mid-schedule test) silently break
# since _aslu_acquired would never be set to "1" by this stand-in.
agent_upgrade_lock_finish_acquire() {
    _aslu_acquired=1
    if printf '%s\n' "$$" > "$1/pid" 2>/dev/null; then
        return 0
    fi
    rm -rf "$1" 2>/dev/null
    _aslu_acquired=0
    return 1
}

# --- two callers racing to reclaim the SAME dead-pid stale lock: at most one
#     may win (acquire + go on to call systemd-run); the other must back off
#     as busy without ever destroying the winner's fresh lock. This is the
#     exact scenario the atomic-rename reclaim (instead of rm -rf + mkdir)
#     exists to make safe. ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
mkdir -p "$MGATE_AGENT_UPGRADE_LOCK_DIR"
sh -c 'exit 0' &
dead_pid2=$!
wait "$dead_pid2" 2>/dev/null || true
printf '%s\n' "$dead_pid2" > "$MGATE_AGENT_UPGRADE_LOCK_DIR/pid"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
RACE_A="$WORK_DIR/race-a.result"
RACE_B="$WORK_DIR/race-b.result"
rm -f "$RACE_A" "$RACE_B"
( if agent_upgrade_lock_try_acquire; then printf 'won\n' > "$RACE_A"; else printf 'lost\n' > "$RACE_A"; fi ) &
race_pid_a=$!
( if agent_upgrade_lock_try_acquire; then printf 'won\n' > "$RACE_B"; else printf 'lost\n' > "$RACE_B"; fi ) &
race_pid_b=$!
wait "$race_pid_a" 2>/dev/null || true
wait "$race_pid_b" 2>/dev/null || true
race_result_a="$(cat "$RACE_A" 2>/dev/null || printf 'missing')"
race_result_b="$(cat "$RACE_B" 2>/dev/null || printf 'missing')"
case "$race_result_a $race_result_b" in
    "won lost"|"lost won") : ;;
    *)
        printf 'expected exactly one winner and one loser, got: A=%s B=%s\n' "$race_result_a" "$race_result_b" >&2
        exit 1
        ;;
esac
[ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'winner lock dir must still exist after the race\n' >&2; exit 1; }
winner_pid="$(cat "$MGATE_AGENT_UPGRADE_LOCK_DIR/pid" 2>/dev/null || true)"
[ -n "$winner_pid" ] || { printf 'winner lock dir has no pid marker after the race\n' >&2; exit 1; }
kill -0 "$winner_pid" 2>/dev/null || { printf 'winner lock pid %s is not actually alive\n' "$winner_pid" >&2; exit 1; }
for q in "$MGATE_AGENT_UPGRADE_LOCK_DIR".stale.*; do
    [ -e "$q" ] && { printf 'leftover quarantine directory after the race: %s\n' "$q" >&2; exit 1; }
    break
done
agent_upgrade_lock_release

# --- TERM delivered to the scheduling critical section while it's blocked
#     in systemd-run must: release the lock (trap is scoped to the dedicated
#     subshell agent_schedule_combined_upgrade_locked, not the calling
#     process -- nothing in THIS test script itself traps TERM); make this
#     schedule attempt return a conventional 128+signal failure code, NOT
#     fall through and continue running (which could log "scheduled
#     successfully", overwrite status again, or even attempt a second
#     systemd-run call after the lock was already released) ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
sleep 5
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
( agent_schedule_combined_upgrade_locked ) &
bgpid=$!
waited=0
while [ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock never appeared before sending TERM\n' >&2; exit 1; }
# status is "scheduled" at this point (written before the systemd-run call)
assert_contains "$(status_state)" '"state":"scheduled"'
kill -TERM "$bgpid" 2>/dev/null || true
set +e
wait "$bgpid" 2>/dev/null
term_rc=$?
set -e
[ "$term_rc" -eq 143 ] || { printf 'expected exit 143 (128+SIGTERM) after TERM, got: %s\n' "$term_rc" >&2; exit 1; }
waited=0
while [ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir was not released after TERM\n' >&2; exit 1; }
# must not have fallen through to log a spurious success or leave Cloud
# stuck seeing "scheduled" forever (the unit was never confirmed active, so
# the fixed, whitelisted "interrupted" failure must have been written) --
# and it must be a definitive, retriable failure, not a lingering in-progress
# state
assert_contains "$(status_state)" '"state":"failed"'
assert_contains "$(status_state)" '"message":"combined upgrade interrupted"'
assert_contains "$(status_state)" '"exit_code":143'
assert_not_contains "$(status_state)" '"state":"scheduled"'
assert_not_contains "$(status_state)" '"state":"succeeded"'

# --- TERM delivered AFTER the transient unit is confirmed active: a
#     genuinely running upgrade's status is authoritative and must never be
#     overwritten with a false "interrupted" failure just because this
#     scheduling call itself got signaled on its way out. The initial
#     pre-schedule is-active check must still see "not active" (so
#     scheduling actually proceeds to write "scheduled" and call the slow
#     fake systemd-run); only the LATER re-check made by the signal handler
#     itself, once TERM has arrived, sees "active" -- simulating the unit
#     having genuinely started by the time the signal lands. ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
sleep 5
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
IS_ACTIVE_CALLS_FILE2="$WORK_DIR/is-active-calls-2"
rm -f "$IS_ACTIVE_CALLS_FILE2"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service")
            _calls="$(cat "$IS_ACTIVE_CALLS_FILE2" 2>/dev/null || printf '0')"
            _calls=$((_calls + 1))
            printf '%s' "$_calls" > "$IS_ACTIVE_CALLS_FILE2"
            [ "$_calls" -eq 1 ] && return 1
            return 0
            ;;
    esac
    return 0
}
( agent_schedule_combined_upgrade_locked ) &
bgpid=$!
waited=0
while [ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock never appeared before sending TERM\n' >&2; exit 1; }
# simulate the worker having already taken over and reported real progress
printf '{"state":"running","message":"combined upgrade running","exit_code":null,"updated_at":555}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
kill -TERM "$bgpid" 2>/dev/null || true
set +e
wait "$bgpid" 2>/dev/null
term_rc2=$?
set -e
[ "$term_rc2" -eq 143 ] || { printf 'expected exit 143, got: %s\n' "$term_rc2" >&2; exit 1; }
waited=0
while [ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir was not released after TERM (unit active case)\n' >&2; exit 1; }
assert_contains "$(status_state)" '"state":"running"'
assert_not_contains "$(status_state)" '"state":"failed"'

# --- deterministic status-clobber regression: Caller A holds the lock
#     (alive) and has already written its own "scheduled" status. Caller B's
#     own lock attempt is busy throughout (A is alive) and gets signaled
#     WHILE still inside its busy-check (kill -0), before B has acquired
#     anything or written anything of its own -- B must return 143 without
#     ever touching A's "scheduled" status. `kill` (a regular POSIX utility,
#     unlike the special builtin `exit`) can be shadowed by a function, so
#     the REAL agent_upgrade_lock_try_acquire runs unmodified; only its
#     internal `kill -0` call is slowed down here, giving TERM a reliable
#     window to land before B's busy-check even returns. ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
mkdir -p "$MGATE_AGENT_UPGRADE_LOCK_DIR"
printf '%s\n' "$$" > "$MGATE_AGENT_UPGRADE_LOCK_DIR/pid"
printf '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":null,"updated_at":777}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
kill() {
    case "$1" in
        -0) sleep 3; command kill "$@" ;;
        *) command kill "$@" ;;
    esac
}
( agent_schedule_combined_upgrade_locked ) &
busy_bgpid=$!
sleep 1
kill -TERM "$busy_bgpid" 2>/dev/null || true
set +e
wait "$busy_bgpid" 2>/dev/null
busy_rc=$?
set -e
[ "$busy_rc" -eq 143 ] || { printf 'expected busy-caller rc=143, got: %s\n' "$busy_rc" >&2; exit 1; }
assert_contains "$(status_state)" '"state":"scheduled"'
assert_not_contains "$(status_state)" '"state":"failed"'
[ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || {
    printf "A's lock dir must remain untouched -- B never owned it\n" >&2
    exit 1
}
kill() { command kill "$@"; }
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"

# --- deterministic status-clobber regression: this invocation genuinely
#     acquires the lock, but is signaled BEFORE it ever manages to write its
#     own "scheduled" status (during the pre-schedule is-active check) -- a
#     pre-existing succeeded status must remain untouched, since this
#     invocation has no legitimate claim on it yet ---
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
printf '{"state":"succeeded","message":"combined upgrade succeeded","exit_code":0,"updated_at":888}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") sleep 3; return 1 ;;
    esac
    return 0
}
( agent_schedule_combined_upgrade_locked ) &
prewrite_bgpid=$!
waited=0
while [ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock never appeared before sending TERM\n' >&2; exit 1; }
kill -TERM "$prewrite_bgpid" 2>/dev/null || true
set +e
wait "$prewrite_bgpid" 2>/dev/null
prewrite_rc=$?
set -e
[ "$prewrite_rc" -eq 143 ] || { printf 'expected rc=143, got: %s\n' "$prewrite_rc" >&2; exit 1; }
assert_contains "$(status_state)" '"state":"succeeded"'
assert_not_contains "$(status_state)" '"state":"failed"'
waited=0
while [ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir leaked (acquired but not yet scheduled when signaled)\n' >&2; exit 1; }

# --- signal lands between the "scheduled" write actually landing on disk
#     and the in-memory _aslu_scheduled_written flag being set (that
#     assignment is the very next statement after
#     agent_upgrade_status_write returns, but a signal can still land in
#     that gap) -- the persisted status is ALREADY "scheduled" at this point
#     even though this process's own flag still reads "0"; the handler must
#     re-read the real, validated on-disk state rather than trust the flag
#     alone, recognize it as "scheduled", and convert it to a definitive,
#     retriable failure -- never leave it stuck at "scheduled" forever. `mv`
#     (a regular utility, not a special builtin) is shadowed here to run the
#     REAL rename agent_upgrade_status_write depends on and only inject a
#     delay AFTER it lands successfully, so the actual write logic is
#     exercised unmodified -- no hand-duplicated copy to drift out of sync. ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
sleep 5
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
mv() {
    command mv "$@"
    _mv_rc=$?
    [ "$_mv_rc" -eq 0 ] && sleep 3
    return "$_mv_rc"
}
( agent_schedule_combined_upgrade_locked ) &
flagwindow_bgpid=$!
waited=0
while [ ! -f "$MGATE_AGENT_UPGRADE_STATUS_FILE" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ -f "$MGATE_AGENT_UPGRADE_STATUS_FILE" ] || { printf 'status file never appeared before sending TERM\n' >&2; exit 1; }
# the write has landed on disk, but this process is still inside the mocked
# mv's post-success sleep -- _aslu_scheduled_written has NOT been set yet
assert_contains "$(status_state)" '"state":"scheduled"'
kill -TERM "$flagwindow_bgpid" 2>/dev/null || true
set +e
wait "$flagwindow_bgpid" 2>/dev/null
flagwindow_rc=$?
set -e
[ "$flagwindow_rc" -eq 143 ] || { printf 'expected rc=143, got: %s\n' "$flagwindow_rc" >&2; exit 1; }
waited=0
while [ -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] && [ "$waited" -lt 20 ]; do
    sleep 1
    waited=$((waited + 1))
done
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir leaked (signal in write-vs-flag window)\n' >&2; exit 1; }
assert_contains "$(status_state)" '"state":"failed"'
assert_contains "$(status_state)" '"message":"combined upgrade interrupted"'
assert_contains "$(status_state)" '"exit_code":143'
assert_not_contains "$(status_state)" '"state":"scheduled"'
mv() { command mv "$@"; }

# --- calling agent_schedule_combined_upgrade twice back-to-back in the SAME
#     shell process must not be polluted by a leftover trap or lock from the
#     first call -- the second call must succeed exactly as if it were the
#     first, and this test script's OWN outer trap (cleanup, set at the top
#     of this file) must remain the one governing this process's exit ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
rm -rf "$MGATE_AGENT_UPGRADE_LOCK_DIR"
cat > "$FAKE_BIN_DIR/systemd-run" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN_DIR/systemd-run"
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 1 ;;
    esac
    return 0
}
agent_schedule_combined_upgrade
rc1=$?
[ "$rc1" -eq 0 ] || { printf 'expected rc=0 on first of two back-to-back calls\n' >&2; exit 1; }
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir leaked after first of two back-to-back calls\n' >&2; exit 1; }
agent_schedule_combined_upgrade
rc2=$?
[ "$rc2" -eq 0 ] || { printf 'expected rc=0 on second of two back-to-back calls (leftover trap/lock pollution?)\n' >&2; exit 1; }
[ ! -d "$MGATE_AGENT_UPGRADE_LOCK_DIR" ] || { printf 'lock dir leaked after second of two back-to-back calls\n' >&2; exit 1; }

# =====================================================================
# Part 2: cmd_self_update()'s dispatch branching. agent_schedule_combined_
# upgrade is mocked from here on to isolate the branching logic itself.
# =====================================================================

need_root() { :; }
ensure_dirs() { :; }
MGATE_SELF_URL="https://raw.githubusercontent.com/akiiya/mgate/main/mgate.sh"
export MGATE_SELF_URL
# `exec` is a POSIX special builtin -- dash refuses to let a function
# override it ("is a special builtin"), so the real cmd_self_update()'s
# `exec "$SCRIPT_PATH" migrate` cannot be intercepted. Instead, make the
# downloaded/copied file a real, minimal, controlled script: the real exec
# then genuinely replaces the ( cmd_self_update ) subshell with THIS script,
# which is observable and harmless (only the subshell is replaced).
download_file() {
    cat > "$2" <<'INNER'
#!/bin/sh
printf 'EXEC_CALLED %s\n' "$*"
exit 0
INNER
}
validate_mgate_script() { :; }
extract_mgate_version() { printf '9.9.9\n'; }
backup_file() { :; }

# --- plain human CLI (no MGATE_AGENT_CONTEXT): must still exec into migrate,
#     must NEVER touch the combined-upgrade path ---
unset MGATE_AGENT_CONTEXT 2>/dev/null || true
agent_schedule_combined_upgrade() { printf 'MUST NOT BE CALLED\n' >&2; exit 99; }
output="$( ( cmd_self_update ) 2>&1 )"
rc=$?
[ "$rc" -eq 0 ] || { printf 'expected rc=0 for human-path exec: %s\n' "$output" >&2; exit 1; }
assert_contains "$output" 'EXEC_CALLED'
assert_contains "$output" 'migrate'

# --- agent context: must schedule the combined upgrade, must NEVER exec
#     migrate inline in this process (no EXEC_CALLED marker reachable) ---
MGATE_AGENT_CONTEXT=1
export MGATE_AGENT_CONTEXT
agent_schedule_combined_upgrade() { return 0; }
output="$( ( cmd_self_update ) 2>&1 )"
rc=$?
[ "$rc" -eq 0 ] || { printf 'expected rc=0 for agent-context schedule: %s\n' "$output" >&2; exit 1; }
assert_not_contains "$output" 'EXEC_CALLED'
assert_not_contains "$output" 'MUST NOT BE CALLED'

# --- agent context + scheduling failure: cmd_self_update must surface the
#     failure, not silently succeed ---
agent_schedule_combined_upgrade() { return 1; }
set +e
output="$( ( cmd_self_update ) 2>&1 )"
rc=$?
set -e
[ "$rc" -ne 0 ] || { printf 'expected rc!=0 when scheduling fails: %s\n' "$output" >&2; exit 1; }
assert_not_contains "$output" 'EXEC_CALLED'

printf 'agent self-update contract: OK\n'
