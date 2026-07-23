#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

WORK_DIR=/tmp/mgate-test-versionsnapshot.$$
mkdir -p "$WORK_DIR"
MGATE_AGENT_BIN="$WORK_DIR/mgate-agent"
MGATE_AGENT_UPGRADE_STATUS_FILE="$WORK_DIR/combined-upgrade-status.json"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

MGATE_AGENT_CONTEXT=1
export MGATE_AGENT_CONTEXT

# cmd_agent_snapshot() now reconciles a persisted scheduled/running record
# against whether the transient mgate-agent-upgrade unit is actually still
# active (see agent_upgrade_status_reconcile_for_snapshot) -- default to
# "active" here so this file's hand-crafted fixtures (which use small,
# decades-old example timestamps) are reported verbatim, matching what these
# assertions are actually testing (field validation / idle fallback, not the
# reconciliation logic, which has its own dedicated tests further down).
systemctl() {
    case "$1 $2" in
        "is-active ${MGATE_AGENT_UPGRADE_UNIT}.service") return 0 ;;
    esac
    return 0
}

assert_eq() {
    [ "$1" = "$2" ] || {
        printf 'expected: %s\nactual: %s\n' "$2" "$1" >&2
        exit 1
    }
}

snapshot_field() {
    # $1=snapshot json  $2=python expression rooted at d
    printf '%s' "$1" | python -c "
import json, sys
d = json.load(sys.stdin)
print($2)
"
}

# =====================================================================
# Part 1: agent_normalize_release_version() -- direct unit coverage of the
# strict release-version parsing (requirement: only a bare vMAJOR.MINOR.PATCH
# is acceptable; the human-facing 'mgate-agent v0.2.0' form, dev/rc suffixes,
# "unknown", and garbage must all normalize to "unknown").
# =====================================================================

assert_eq "$(agent_normalize_release_version 'mgate-agent v0.2.0')" 'v0.2.0'
assert_eq "$(agent_normalize_release_version 'v0.2.0')" 'v0.2.0'
assert_eq "$(agent_normalize_release_version 'mgate-agent v1.23.456')" 'v1.23.456'
assert_eq "$(agent_normalize_release_version 'mgate-agent v0.2.0-dev')" 'unknown'
assert_eq "$(agent_normalize_release_version 'v0.2.0-rc1')" 'unknown'
assert_eq "$(agent_normalize_release_version 'unknown')" 'unknown'
assert_eq "$(agent_normalize_release_version '')" 'unknown'
assert_eq "$(agent_normalize_release_version 'not a version at all')" 'unknown'
assert_eq "$(agent_normalize_release_version 'mgate-agent')" 'unknown'
assert_eq "$(agent_normalize_release_version '0.2.0')" 'unknown'

# =====================================================================
# Part 2: cmd_agent_snapshot()'s agent.version field, end-to-end through a
# real (fake) MGATE_AGENT_BIN -- must never leak the "mgate-agent " prefix
# into the value cloud's version gate compares.
# =====================================================================

printf '#!/bin/sh\nprintf "mgate-agent v0.2.0\\n"\n' > "$MGATE_AGENT_BIN"
chmod +x "$MGATE_AGENT_BIN"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c 'import json,sys; json.load(sys.stdin)'
assert_eq "$(snapshot_field "$snap" "d['agent']['version']")" 'v0.2.0'

printf '#!/bin/sh\nprintf "v0.2.0-dev\\n"\n' > "$MGATE_AGENT_BIN"
chmod +x "$MGATE_AGENT_BIN"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['version']")" 'unknown'

printf '#!/bin/sh\nprintf "unknown\\n"\n' > "$MGATE_AGENT_BIN"
chmod +x "$MGATE_AGENT_BIN"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['version']")" 'unknown'

printf '#!/bin/sh\nprintf "\\x01\\x02garbage\\n"\n' > "$MGATE_AGENT_BIN"
chmod +x "$MGATE_AGENT_BIN"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c 'import json,sys; json.load(sys.stdin)'
assert_eq "$(snapshot_field "$snap" "d['agent']['version']")" 'unknown'

# =====================================================================
# Part 3: cmd_agent_snapshot()'s agent.upgrade object -- safe idle fallback
# on a missing or corrupted status file; must never splice the raw file
# content into the JSON.
# =====================================================================

printf '#!/bin/sh\nprintf "mgate-agent v0.2.0\\n"\n' > "$MGATE_AGENT_BIN"
chmod +x "$MGATE_AGENT_BIN"

# --- no status file at all -> idle, all nested fields null-equivalent ---
rm -f "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'idle', u
assert u['message'] is None, u
assert u['exit_code'] is None, u
assert u['updated_at'] is None, u
"

# --- corrupted / non-JSON file content -> safe idle fallback, not a crash,
#     and the garbage text must not appear anywhere in the emitted JSON ---
printf 'not even close to json {{{ "state": ' > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c 'import json,sys; json.load(sys.stdin)'
assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'idle'
case "$snap" in
    *"not even close"*) printf 'raw corrupt file content leaked into JSON: %s\n' "$snap" >&2; exit 1 ;;
esac

# --- invalid/unrecognized state value -> safe idle fallback (enum guard) ---
printf '{"state":"bogus","message":"x","exit_code":1,"updated_at":123}' > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'idle'

# --- valid status file -> faithfully reflected ---
printf '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":null,"updated_at":1234567890}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'scheduled', u
assert u['message'] == 'combined upgrade scheduled', u
assert u['exit_code'] is None, u
assert u['updated_at'] == 1234567890, u
"

# =====================================================================
# Part 4: strict per-state field validation. Each state has an EXACT
# required message/exit_code shape; any mismatch (wrong message, wrong
# exit_code, missing field) must fall back to idle as a whole -- never a
# partially-trusted mix of one valid field and one corrupted one.
# =====================================================================

assert_idle_fallback() {
    # $1 = raw status file content to test
    printf '%s' "$1" > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
    snap="$(cmd_agent_snapshot)"
    printf '%s' "$snap" | python -c 'import json,sys; json.load(sys.stdin)'
    assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'idle'
}

# scheduled/running: wrong (non-fixed) message must not be trusted
assert_idle_fallback '{"state":"scheduled","message":"totally different text","exit_code":null,"updated_at":123}'
assert_idle_fallback '{"state":"running","message":"wrong message","exit_code":null,"updated_at":123}'
# scheduled/running: a non-null exit_code contradicts "still in progress"
assert_idle_fallback '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":0,"updated_at":123}'
assert_idle_fallback '{"state":"running","message":"combined upgrade running","exit_code":1,"updated_at":123}'
# succeeded: exit_code must be exactly 0
assert_idle_fallback '{"state":"succeeded","message":"combined upgrade succeeded","exit_code":1,"updated_at":123}'
assert_idle_fallback '{"state":"succeeded","message":"combined upgrade succeeded","exit_code":null,"updated_at":123}'
# succeeded: wrong message
assert_idle_fallback '{"state":"succeeded","message":"something else","exit_code":0,"updated_at":123}'
# failed: message must be one of the fixed failure literals actually written
assert_idle_fallback '{"state":"failed","message":"some other failure text","exit_code":1,"updated_at":123}'
# failed: exit_code:0 contradicts "failed"
assert_idle_fallback '{"state":"failed","message":"migrate step failed","exit_code":0,"updated_at":123}'
# any state: missing exit_code entirely
assert_idle_fallback '{"state":"scheduled","message":"combined upgrade scheduled","updated_at":123}'
# any state: missing updated_at entirely
assert_idle_fallback '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":null}'
# any state: updated_at is zero (treated as an implausible/invalid timestamp)
assert_idle_fallback '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":null,"updated_at":0}'

# --- the full set of legitimate combinations must each be trusted verbatim ---
printf '{"state":"running","message":"combined upgrade running","exit_code":null,"updated_at":111}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'running'

printf '{"state":"succeeded","message":"combined upgrade succeeded","exit_code":0,"updated_at":222}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'succeeded', u
assert u['exit_code'] == 0, u
"

printf '{"state":"failed","message":"agent update step failed","exit_code":3,"updated_at":333}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'failed', u
assert u['message'] == 'agent update step failed', u
assert u['exit_code'] == 3, u
"

# --- failed with exit_code:null (e.g. systemd-run scheduling failed before
#     any real command ran) is a legitimate combination, not a fallback ---
printf '{"state":"failed","message":"systemd-run scheduling failed","exit_code":null,"updated_at":444}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'failed', u
assert u['exit_code'] is None, u
"

# =====================================================================
# Part 5: SIGKILL/power-loss stale-state recovery. Neither the scheduler nor
# the worker can update the status file if killed uncatchably, so
# cmd_agent_snapshot() must reconcile an abandoned scheduled/running record
# rather than let Cloud stay locked out of retrying forever -- but only when
# BOTH the transient unit is confirmed not active AND the record is older
# than the generous grace period; neither signal alone is sufficient.
# =====================================================================

# --- unit not active + well past the grace period -> reconciled to a
#     definitive, retriable failure ---
systemctl() { return 1; }
printf '{"state":"running","message":"combined upgrade running","exit_code":null,"updated_at":123}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
printf '%s' "$snap" | python -c "
import json, sys
d = json.load(sys.stdin)
u = d['agent']['upgrade']
assert u['state'] == 'failed', u
assert u['message'] == 'combined upgrade interrupted', u
"

# --- unit not active but the record is FRESH (within the grace period) --
#     do not reconcile: this is also the normal, brief window right after
#     "scheduled" is written and before systemd-run's own registration makes
#     the unit active yet ---
systemctl() { return 1; }
fresh_ts="$(date +%s 2>/dev/null || printf '0')"
printf '{"state":"scheduled","message":"combined upgrade scheduled","exit_code":null,"updated_at":%s}' \
    "$fresh_ts" > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'scheduled'

# --- unit CONFIRMED active, even though the record is old -- never
#     reconcile: a genuinely long-running (e.g. slow download) worker must
#     never be misjudged as abandoned just because it's been a while ---
systemctl() { return 0; }
printf '{"state":"running","message":"combined upgrade running","exit_code":null,"updated_at":123}' \
    > "$MGATE_AGENT_UPGRADE_STATUS_FILE"
snap="$(cmd_agent_snapshot)"
assert_eq "$(snapshot_field "$snap" "d['agent']['upgrade']['state']")" 'running'

# =====================================================================
# Part 6: agent_upgrade_status_write() must return non-zero when the write
# itself fails, not just because a trailing best-effort cleanup succeeds.
# =====================================================================

BLOCKER_FILE="$WORK_DIR/blocker-not-a-directory"
: > "$BLOCKER_FILE"
MGATE_AGENT_DATA_DIR="$BLOCKER_FILE/nested"
MGATE_AGENT_UPGRADE_STATUS_FILE="$MGATE_AGENT_DATA_DIR/combined-upgrade-status.json"
set +e
agent_upgrade_status_write "scheduled" "combined upgrade scheduled" "" ""
write_rc=$?
set -e
[ "$write_rc" -ne 0 ] || { printf 'expected agent_upgrade_status_write to fail when its directory cannot be created\n' >&2; exit 1; }

printf 'agent version/upgrade snapshot contract: OK\n'
