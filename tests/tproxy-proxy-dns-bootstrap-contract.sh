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
  use-hosts: false
  nameserver:
    - https://1.1.1.1/dns-query
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  respect-rules: true
EOF

! tproxy_config_proxy_dns_bootstrap_ok
tproxy_config_native_dns_migratable
tproxy_config_set_proxy_dns_bootstrap
tproxy_config_proxy_dns_bootstrap_ok
tproxy_config_set_native_dns
tproxy_config_native_dns_ok
tproxy_config_dns_use_hosts_ok
grep -q '^    - https://dns.alidns.com/dns-query#DIRECT$' "$CONFIG_FILE"
grep -q '^  dns.alidns.com:$' "$CONFIG_FILE"
grep -q '^    - 223.5.5.5$' "$CONFIG_FILE"
grep -q '^    - 223.6.6.6$' "$CONFIG_FILE"
! grep -q '^    - https://1.1.1.1/dns-query$' "$CONFIG_FILE"
grep -q '^  use-hosts: true$' "$CONFIG_FILE"
grep -q "^    - '1.1.1.1#TPROXY-OUT'$" "$CONFIG_FILE"
grep -q "^    - '8.8.8.8#TPROXY-OUT'$" "$CONFIG_FILE"

cat > "$CONFIG_FILE" <<'EOF'
dns:
  enable: true
  respect-rules: true
EOF

tproxy_config_set_proxy_dns_bootstrap
tproxy_config_proxy_dns_bootstrap_ok
grep -q '^  respect-rules: true$' "$CONFIG_FILE"
grep -q '^  use-hosts: true$' "$CONFIG_FILE"

cat > "$CONFIG_FILE" <<'EOF'
hosts:
  dns.alidns.com:
    - 223.5.5.5
    - 223.6.6.6
dns:
  use-hosts: true
  proxy-server-nameserver:
    - https://dns.example.test/dns-query#DIRECT
other:
  resolvers:
    - https://dns.alidns.com/dns-query#DIRECT
EOF

! tproxy_config_proxy_dns_bootstrap_ok
tproxy_config_set_proxy_dns_bootstrap
tproxy_config_proxy_dns_bootstrap_ok
grep -q '^    - https://dns.alidns.com/dns-query#DIRECT$' "$CONFIG_FILE"

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - https://dns.example.test/dns-query
EOF

! tproxy_config_native_dns_migratable
! tproxy_config_native_dns_ok

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
    - https://dns.example.test/dns-query
EOF

! tproxy_config_native_dns_ok

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  nameserver-policy:
    '+.example.test': 223.5.5.5
EOF

tproxy_config_dns_has_unsafe_overrides

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  'fallback':
    - 223.5.5.5
EOF

tproxy_config_dns_has_unsafe_overrides

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  fallback:
    - 223.5.5.5
EOF

tproxy_config_dns_has_unsafe_overrides

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  direct-nameserver:
    - 223.5.5.5
EOF

tproxy_config_dns_has_unsafe_overrides

cat > "$CONFIG_FILE" <<'EOF'
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
EOF

! tproxy_config_dns_has_unsafe_overrides

cat > "$CONFIG_FILE" <<'EOF'
hosts:
  'dns.alidns.com':
    - 223.5.5.5
    - 223.6.6.6
dns:
  "use-hosts": true
  'nameserver':
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  "proxy-server-nameserver":
    - https://dns.alidns.com/dns-query#DIRECT
EOF

tproxy_config_has_quoted_managed_dns_keys

cat > "$CONFIG_FILE" <<'EOF'
dns-extra: &dns_extra
  fallback:
    - 223.5.5.5
dns:
  <<: *dns_extra
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
EOF

tproxy_config_dns_has_yaml_merge_or_alias

cat > "$CONFIG_FILE" <<'EOF'
dns:
  # legacy &dns_extra is only a comment
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
EOF

! tproxy_config_dns_has_yaml_merge_or_alias

cat > "$CONFIG_FILE" <<'EOF'
dns-common: &dns_common
  fallback:
    - 223.5.5.5
dns: *dns_common
EOF

tproxy_config_dns_has_yaml_merge_or_alias

cat > "$CONFIG_FILE" <<'EOF'
dns-common: &dns.common
  fallback:
    - 223.5.5.5
dns: *dns.common
EOF

tproxy_config_dns_has_yaml_merge_or_alias

ensure_dirs() { :; }
TPROXY_LOG_FILE="$test_dir/tproxy.log"
TPROXY_LAST_ERROR_FILE="$test_dir/tproxy.last_error"
cat > "$CONFIG_FILE" <<EOF
allow-lan: true
bind-address: '*'
tproxy-port: $TPROXY_PORT
hosts:
  dns.alidns.com:
    - 223.5.5.5
    - 223.6.6.6
dns:
  use-hosts: true
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query#DIRECT
  fallback:
    - 223.5.5.5
proxy-groups:
  - name: TPROXY-OUT
    type: select
    proxies:
      - DIRECT
rules:
  - IN-TYPE,TPROXY,TPROXY-OUT
EOF

cp "$CONFIG_FILE" "$test_dir/before-unsafe-override.yaml"
! tproxy_ensure_config_port
cmp "$test_dir/before-unsafe-override.yaml" "$CONFIG_FILE"
grep -q 'dns.nameserver-policy, dns.fallback, or dns.direct-nameserver detected' "$TPROXY_LAST_ERROR_FILE"

need_root() { :; }
ap_load_config() { :; }
tproxy_start_preflight() { :; }
tproxy_info() { :; }
tproxy_clear_error() { rm -f "$TPROXY_LAST_ERROR_FILE"; }
! cmd_tproxy_start
grep -q 'dns.nameserver-policy, dns.fallback, or dns.direct-nameserver detected' "$TPROXY_LAST_ERROR_FILE"
! grep -q 'failed to prepare mihomo transparent-proxy configuration' "$TPROXY_LAST_ERROR_FILE"

cat > "$CONFIG_FILE" <<EOF
allow-lan: true
bind-address: '*'
tproxy-port: $TPROXY_PORT
hosts:
  'dns.alidns.com':
    - 223.5.5.5
    - 223.6.6.6
dns:
  "use-hosts": true
  'nameserver':
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
  "proxy-server-nameserver":
    - https://dns.alidns.com/dns-query#DIRECT
proxy-groups:
  - name: TPROXY-OUT
    type: select
    proxies:
      - DIRECT
rules:
  - IN-TYPE,TPROXY,TPROXY-OUT
EOF

cp "$CONFIG_FILE" "$test_dir/before-quoted-keys.yaml"
! tproxy_ensure_config_port
cmp "$test_dir/before-quoted-keys.yaml" "$CONFIG_FILE"
grep -q 'quoted dns/hosts keys detected' "$TPROXY_LAST_ERROR_FILE"

cat > "$CONFIG_FILE" <<'EOF'
proxy-providers:
  mgate-sub:
    type: file
proxy-groups:
  - name: TPROXY-OUT
    type: select
    use:
      - mgate-sub
rules: []
EOF

tproxy_config_out_group_ok
sed -i 's/type: select/type: url-test/' "$CONFIG_FILE"
! tproxy_config_out_group_ok

printf 'tproxy proxy DNS bootstrap contract: OK\n'
