#!/usr/bin/env bash
# `sb --json list` names each line by its conf file name. That equals the
# sing-box inbound tag only because create() writes it that way, and the two are
# not the same thing: a hand-written file, and any file holding a relay pair,
# carries tags of its own. The core keys its stats counters and its connection
# log by the real tags, so a control plane that only ever receives the file name
# cannot attribute either back to a line.
#
# json_node_obj is extracted from src/core.sh so these assertions cannot drift
# from the shipped implementation.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-inbound-tags.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

extract_fn() { awk "/^$1\\(\\) \\{/,/^\\}/" "$CORE"; }
eval "$(extract_fn json_node_obj)"

# --- stubs: json_node_obj reads vars that `info <file>` would have filled -----
is_conf_dir="$TMP/conf"; mkdir -p "$is_conf_dir"
is_protocol=vless; net=reality; is_addr=203.0.113.7; port=7899
is_https_port=""; host=""; path=""; uuid=""; password=""; ss_password=""
ss_method=""; is_servername=""; is_public_key=""; is_url=""
lattice_meta_obj_for() { printf '{}\n'; }
route_maps_json() { printf '{"routes":{},"types":{}}'; }

tags_of() { jq -r '.metadata.inbound_tags // "<none>"'; }

# --- 1. the convention case: one inbound, tag == file name -------------------
is_config_name=Hysteria2-17892.json
cat >"$is_conf_dir/$is_config_name" <<'EOF'
{"inbounds":[{"tag":"Hysteria2-17892.json","type":"hysteria2","listen":"::","listen_port":17892,
"users":[{"password":"pw1"}]}]}
EOF
out=$(json_node_obj)
chk "single conventional inbound reports its tag" \
    "$(tags_of <<<"$out")" '["Hysteria2-17892.json"]'
chk "name still is the conf file name" "$(jq -r .name <<<"$out")" "Hysteria2-17892.json"

# --- 2. the relay pair: two inbounds, neither tag is the file name -----------
# The shape read off dmit-eb-wee: one file, a vless and a hysteria2 inbound
# forwarding to another node, plus the outbound they route to.
is_config_name=VLESS-REALITY-17893.json
cat >"$is_conf_dir/$is_config_name" <<'EOF'
{"inbounds":[
  {"tag":"inbound-for-aaitr-frontier-nat-vless-7899","type":"vless","listen":"::","listen_port":7899,
   "users":[{"uuid":"11111111-1111-4111-8111-111111111111"}]},
  {"tag":"inbound-for-aaitr-frontier-nat-hy2-7898","type":"hysteria2","listen":"::","listen_port":7898,
   "users":[{"password":"pw2"}]}],
 "outbounds":[{"tag":"out-to-aaitr-frontier-nat-vless-7899","type":"vless",
   "server":"nat-us-28tz.aproxy.top","server_port":25499}]}
EOF
out=$(json_node_obj)
chk "a relay pair reports both inbound tags" \
    "$(tags_of <<<"$out")" \
    '["inbound-for-aaitr-frontier-nat-hy2-7898","inbound-for-aaitr-frontier-nat-vless-7899"]'
chk "the file name is not among them" \
    "$(jq -r '.metadata.inbound_tags | fromjson | index("VLESS-REALITY-17893.json") // "absent"' <<<"$out")" \
    "absent"
chk "name is still the conf file name, so the line identity does not move" \
    "$(jq -r .name <<<"$out")" "VLESS-REALITY-17893.json"
chk "user_count still comes from the first inbound only" \
    "$(jq -r '.user_count' <<<"$out")" "1"

# --- 3. determinism: the same file renders byte-identical output -------------
chk "re-render is byte-identical" "$(json_node_obj)" "$out"

# --- 4. a file with no taggable inbound emits no key ------------------------
is_config_name=fragment.json
printf '%s\n' '{"outbounds":[{"tag":"direct","type":"direct"}]}' >"$is_conf_dir/$is_config_name"
chk "a file with no inbounds omits inbound_tags" \
    "$(json_node_obj | tags_of)" "<none>"
is_config_name=untagged.json
printf '%s\n' '{"inbounds":[{"type":"vless","listen_port":1}]}' >"$is_conf_dir/$is_config_name"
chk "an inbound with no tag omits inbound_tags" \
    "$(json_node_obj | tags_of)" "<none>"

# --- 5. the sidecar identity keys still come through untouched --------------
lattice_meta_obj_for() { printf '{"line_id":"abc","node_uuid":"n-1"}\n'; }
is_config_name=Hysteria2-17892.json
out=$(json_node_obj)
chk "line_id survives alongside the new key" "$(jq -r '.metadata.line_id' <<<"$out")" "abc"
chk "node_uuid survives alongside the new key" "$(jq -r '.metadata.node_uuid' <<<"$out")" "n-1"
chk "inbound_tags is present with them" \
    "$(tags_of <<<"$out")" '["Hysteria2-17892.json"]'

echo "---"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
