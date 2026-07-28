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
grep -q "^    - 'https://cloudflare-dns.com/dns-query#TPROXY-OUT'$" "$CONFIG_FILE"
grep -q "^    - 'https://dns.google/dns-query#TPROXY-OUT'$" "$CONFIG_FILE"
grep -q '^  cloudflare-dns.com:$' "$CONFIG_FILE"
grep -q '^  dns.google:$' "$CONFIG_FILE"
grep -q '^  prefer-h3: false$' "$CONFIG_FILE"

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
hosts:
  cloudflare-dns.com:
    - 10.0.0.1
  dns.google:
    - 10.0.0.2
dns:
  nameserver:
    - '1.1.1.1#TPROXY-OUT'
    - '8.8.8.8#TPROXY-OUT'
EOF

tproxy_config_native_dns_migratable
tproxy_config_set_native_dns
tproxy_config_native_dns_ok
tproxy_config_doh_hosts_ok
! grep -q '^    - 10\.0\.0\.[12]$' "$CONFIG_FILE"
grep -A2 '^  cloudflare-dns.com:$' "$CONFIG_FILE" | grep -q '^    - 1\.1\.1\.1$'
grep -A2 '^  cloudflare-dns.com:$' "$CONFIG_FILE" | grep -q '^    - 1\.0\.0\.1$'
grep -A2 '^  dns.google:$' "$CONFIG_FILE" | grep -q '^    - 8\.8\.8\.8$'
grep -A2 '^  dns.google:$' "$CONFIG_FILE" | grep -q '^    - 8\.8\.4\.4$'

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

cat > "$CONFIG_FILE" <<EOF
allow-lan: true
bind-address: '*'
tproxy-port: $TPROXY_PORT
hosts:
  "cloudflare-dns.com":
    - 1.1.1.1
    - 1.0.0.1
  'dns.google':
    - 8.8.8.8
    - 8.8.4.4
dns:
  prefer-h3: false
  "prefer-h3": true
  nameserver:
    - 'https://cloudflare-dns.com/dns-query#TPROXY-OUT'
    - 'https://dns.google/dns-query#TPROXY-OUT'
proxy-groups:
  - name: TPROXY-OUT
    type: select
    proxies:
      - DIRECT
rules:
  - IN-TYPE,TPROXY,TPROXY-OUT
EOF

cp "$CONFIG_FILE" "$test_dir/before-quoted-doh-keys.yaml"
tproxy_config_has_quoted_managed_dns_keys
! tproxy_ensure_config_port
cmp "$test_dir/before-quoted-doh-keys.yaml" "$CONFIG_FILE"
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

generate_config_content > "$test_dir/generated-config.yaml"
grep -q '^  cloudflare-dns.com:$' "$test_dir/generated-config.yaml"
grep -q "^    - 'https://cloudflare-dns.com/dns-query#TPROXY-OUT'$" "$test_dir/generated-config.yaml"
grep -q '^  prefer-h3: false$' "$test_dir/generated-config.yaml"

: > "$test_dir/accounts.txt"
: > "$test_dir/countries.txt"
generate_sub_config_file "$test_dir/generated-sub-config.yaml" ./providers/sub.yaml \
    "$test_dir/accounts.txt" "$test_dir/countries.txt"
grep -q '^  cloudflare-dns.com:$' "$test_dir/generated-sub-config.yaml"
grep -q "^    - 'https://dns.google/dns-query#TPROXY-OUT'$" "$test_dir/generated-sub-config.yaml"
grep -q '^  prefer-h3: false$' "$test_dir/generated-sub-config.yaml"

mihomo_api_call() {
    case "$2" in
        *cloudflare-dns.com*) printf '{"delay":18}\n' ;;
        *dns.google*) printf '{"delay":21}\n' ;;
        *) return 1 ;;
    esac
}
tproxy_doh_preflight

mihomo_api_call() {
    case "$2" in
        *cloudflare-dns.com*) printf '{"delay":18}\n' ;;
        *) return 1 ;;
    esac
}
! tproxy_doh_preflight
[ "${TPROXY_DOH_PREFLIGHT_FAILED:-}" = "dns.google" ]

tproxy_core_rules_active() { return 0; }
: > "$test_dir/tproxy-select-calls.txt"
mihomo_api_call() {
    method="$1"
    path="$2"
    body="${3:-}"
    case "$method:$path" in
        GET:/proxies/TPROXY-OUT) printf '{"now":"old-node"}\n' ;;
        GET:*cloudflare-dns.com*) printf '{"delay":18}\n' ;;
        GET:*dns.google*) return 1 ;;
        PUT:/proxies/TPROXY-OUT)
            printf '%s\n' "$body" >> "$test_dir/tproxy-select-calls.txt"
            ;;
        *) return 1 ;;
    esac
}
! cmd_tproxy_select new-node
grep -q '"name":"new-node"' "$test_dir/tproxy-select-calls.txt"
grep -q '"name":"old-node"' "$test_dir/tproxy-select-calls.txt"
grep -q "selected node 'new-node' cannot reach required DoH resolver(s): dns.google; restored previous node 'old-node'" "$TPROXY_LAST_ERROR_FILE"

printf 'tproxy proxy DNS bootstrap contract: OK\n'
