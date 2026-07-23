#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

# --- module_check_* accumulator: precedence + installable computation ---

assert_module() {
    # $1=json $2=expected_state $3=expected_installable(true/false)
    printf '%s' "$1" | python -c "
import json, sys
d = json.load(sys.stdin)
assert d['state'] == '$2', d
assert d['installable'] == $3, d
assert isinstance(d['checks'], list) and len(d['checks']) > 0, d
for c in d['checks']:
    assert set(c.keys()) == {'id', 'state', 'remediable', 'detail'}, c
    assert c['state'] in ('ready', 'missing_dependencies', 'not_configured', 'unsupported', 'blocked'), c
"
}

module_check_reset
module_check_add "a" "ready" "false" "ok"
module_check_add "b" "ready" "false" "ok"
assert_module "$(module_check_emit)" "ready" "False"

module_check_reset
module_check_add "a" "missing_dependencies" "true" "x"
module_check_add "b" "not_configured" "false" "y"
assert_module "$(module_check_emit)" "not_configured" "False"

module_check_reset
module_check_add "a" "missing_dependencies" "true" "x"
module_check_add "b" "unsupported" "false" "y"
module_check_add "c" "blocked" "false" "z"
assert_module "$(module_check_emit)" "unsupported" "False"

module_check_reset
module_check_add "a" "blocked" "false" "x"
module_check_add "b" "missing_dependencies" "true" "y"
assert_module "$(module_check_emit)" "blocked" "False"

module_check_reset
module_check_add "a" "missing_dependencies" "true" "x"
module_check_add "b" "ready" "false" "y"
assert_module "$(module_check_emit)" "missing_dependencies" "True"

module_check_reset
module_check_add "a" "missing_dependencies" "false" "x"
assert_module "$(module_check_emit)" "missing_dependencies" "False"

# module_check_state_only only exposes {"state": ...}
module_check_reset
module_check_add "a" "ready" "false" "x"
[ "$(module_check_state_only)" = '{"state":"ready"}' ] || {
    printf 'unexpected state_only output: %s\n' "$(module_check_state_only)" >&2
    exit 1
}

# --- agent-snapshot: modules field is present, valid, and doesn't break the
#     existing schema (schema_version stays 1, pre-existing fields untouched) ---

MGATE_AGENT_CONTEXT=1
export MGATE_AGENT_CONTEXT
output="$(cmd_agent_snapshot)"

printf '%s' "$output" | python -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True, d
assert d['schema_version'] == 1, d
assert d['component'] == 'agent_snapshot', d
# pre-existing top-level fields must still be present
for k in ('wifi', 'ap', 'gateway', 'tproxy', 'subscription', 'mihomo', 'agent', 'warnings'):
    assert k in d, 'missing pre-existing field: ' + k
modules = d['modules']
for name in ('core', 'ap', 'tproxy', 'gateway', 'subscription', 'wifi'):
    assert name in modules, 'missing module: ' + name
    m = modules[name]
    assert m['state'] in ('ready', 'missing_dependencies', 'not_configured', 'unsupported', 'blocked'), m
    assert isinstance(m['installable'], bool), m
    assert isinstance(m['checks'], list), m
    for c in m['checks']:
        assert set(c.keys()) == {'id', 'state', 'remediable', 'detail'}, c
        # detail must never look like it leaked a URL/password/token
        detail = c['detail']
        assert 'http://' not in detail and 'https://' not in detail, c
"

printf 'agent modules-snapshot contract: OK\n'
