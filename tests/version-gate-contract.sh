#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

# Regression guard for a real incident: cloud hard-requires mgate.sh >= the
# minimum version below before it will unlock devices out of the combined
# self-update gate (agent_schedule_combined_upgrade / cmd_agent_update).
# Shipping a MGATE_VERSION below this floor means the feature works but the
# device stays permanently gated on the cloud side -- a version-contract
# mismatch, not a code bug, so it won't be caught by any functional test.
# Bump this floor only when cloud's own minimum is raised; never lower it.
MIN_VERSION="0.6.0"

version_ge() {
    # $1 >= $2 ? for dotted major.minor.patch versions, compared numerically
    # per component (not lexicographically -- "0.10.0" must beat "0.6.0").
    _v1_major="${1%%.*}"; _v1_rest="${1#*.}"
    _v1_minor="${_v1_rest%%.*}"; _v1_patch="${_v1_rest#*.}"
    _v2_major="${2%%.*}"; _v2_rest="${2#*.}"
    _v2_minor="${_v2_rest%%.*}"; _v2_patch="${_v2_rest#*.}"

    [ "$_v1_major" -gt "$_v2_major" ] && return 0
    [ "$_v1_major" -lt "$_v2_major" ] && return 1
    [ "$_v1_minor" -gt "$_v2_minor" ] && return 0
    [ "$_v1_minor" -lt "$_v2_minor" ] && return 1
    [ "$_v1_patch" -ge "$_v2_patch" ]
}

case "$MGATE_VERSION" in
    [0-9]*.[0-9]*.[0-9]*) : ;;
    *) printf 'MGATE_VERSION is not a plain major.minor.patch string: %s\n' "$MGATE_VERSION" >&2; exit 1 ;;
esac

version_ge "$MGATE_VERSION" "$MIN_VERSION" || {
    printf 'MGATE_VERSION %s is below the cloud-required minimum %s -- the combined self-update gate would stay permanently locked\n' \
        "$MGATE_VERSION" "$MIN_VERSION" >&2
    exit 1
}

printf 'version gate contract: OK (MGATE_VERSION=%s >= %s)\n' "$MGATE_VERSION" "$MIN_VERSION"
