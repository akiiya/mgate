#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
MGATE_TEST_LIB_ONLY=1
export MGATE_TEST_LIB_ONLY
. "$ROOT/mgate.sh"

test_dir="$ROOT/.tproxy-proxy-dns-bootstrap-test.$$"
mkdir "$test_dir"
trap 'rm -rf "$test_dir"' EXIT
TMP_DIR="$test_dir"
CONFIG_FILE="$test_dir/config.yaml"

cat > "$CONFIG_FILE" <<'EOF'
dns:
  enable: true
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  respect-rules: true
EOF

! tproxy_config_proxy_dns_bootstrap_ok
tproxy_config_set_proxy_dns_bootstrap
tproxy_config_proxy_dns_bootstrap_ok
grep -q '^    - https://1.1.1.1/dns-query#DIRECT$' "$CONFIG_FILE"
grep -q '^    - https://8.8.8.8/dns-query#DIRECT$' "$CONFIG_FILE"
! grep -q '^    - https://1.1.1.1/dns-query$' "$CONFIG_FILE"

cat > "$CONFIG_FILE" <<'EOF'
dns:
  enable: true
  respect-rules: true
EOF

tproxy_config_set_proxy_dns_bootstrap
tproxy_config_proxy_dns_bootstrap_ok
grep -q '^  respect-rules: true$' "$CONFIG_FILE"

printf 'tproxy proxy DNS bootstrap contract: OK\n'
