#!/usr/bin/env bash
# Local harness for the design-15 sb changes. Extracts the functions under test
# from src/core.sh (no Linux box needed) and asserts behavior with temp dirs.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-meta-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

extract_fn() { awk "/^$1\\(\\) \\{/,/^\\}/" "$CORE"; }

# --- stubs -----------------------------------------------------------------
is_conf_dir="$TMP/conf"; is_lattice_meta="$TMP/lattice-metadata.json"
mkdir -p "$is_conf_dir"
get_uuid() { tmp_uuid=$(uuidgen | tr 'A-F' 'a-f'); }
json_err() { printf '{"ok":false,"error":"%s","message":"%s"}\n' "$1" "$2" >&2; exit "${3:-1}"; }
warn() { echo "warn: $*" >&2; }
is_json_out=1

eval "$(extract_fn json_line_user_obj)"
eval "$(extract_fn json_line_user_valid)"
eval "$(awk "/^json_line_user_matches_filter='/,/^'/" "$CORE")"
eval "$(extract_fn lattice_meta_validate)"
eval "$(extract_fn json_resolve_config_file)"
eval "$(extract_fn cmd_json_meta)"
eval "$(extract_fn json_edit_config_atomically)"
eval "$(extract_fn cmd_json_stats)"
is_config_json="$TMP/config.json"; is_core_bin=$(command -v true); is_core=sing-box
manage() { :; }
echo '{"log":{},"dns":{}}' >"$is_config_json"

# --- fixtures ----------------------------------------------------------------
cat >"$is_conf_dir/vless-443.json" <<'EOF'
{"inbounds":[{"tag":"vless-443.json","type":"vless","listen":"::","listen_port":443,
"users":[{"uuid":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"}]}]}
EOF
cat >"$is_conf_dir/trojan-8443.json" <<'EOF'
{"inbounds":[{"tag":"trojan-8443.json","type":"trojan","listen":"::","listen_port":8443,
"users":[{"password":"pw1"}]}]}
EOF

# --- 1. user obj carries name -------------------------------------------------
out=$(json_line_user_obj "$is_conf_dir/vless-443.json" '{"name":"u_abc","uuid":"22222222-2222-4222-8222-222222222222","flow":"xtls-rprx-vision"}')
chk "vless user obj has name" "$(jq -r .name <<<"$out")" "u_abc"
chk "vless user obj has uuid" "$(jq -r .uuid <<<"$out")" "22222222-2222-4222-8222-222222222222"
out=$(json_line_user_obj "$is_conf_dir/vless-443.json" '{"uuid":"22222222-2222-4222-8222-222222222222"}')
chk "vless user obj without name omits key" "$(jq 'has("name")' <<<"$out")" "false"
out=$(json_line_user_obj "$is_conf_dir/trojan-8443.json" '{"name":"u_def","password":"pw2"}')
chk "trojan user obj has name+password" "$(jq -r '.name+"/"+.password' <<<"$out")" "u_def/pw2"

# --- 2. match filter matches by name ------------------------------------------
users='[{"name":"u_abc","uuid":"aaaa"},{"name":"u_bbb","uuid":"bbbb"}]'
kept=$(jq --argjson user '{"name":"u_abc"}' "map(select(($json_line_user_matches_filter) | not))" <<<"$users")
chk "del by name removes entry" "$(jq length <<<"$kept")" "1"
kept=$(jq --argjson user '{"uuid":"bbbb"}' "map(select(($json_line_user_matches_filter) | not))" <<<"$users")
chk "del by uuid still works" "$(jq -r '.[0].name' <<<"$kept")" "u_abc"

# --- 3. meta: fresh node ------------------------------------------------------
LATTICE_NODE_ID="test-node"; LATTICE_IDENTITY_UUID=""
out=$(cmd_json_meta 2>/dev/null)
chk "meta exit ok" "$?" "0"
chk "meta schema" "$(jq -r .schema <<<"$out")" "lattice.singbox-metadata.v2"
chk "meta writer" "$(jq -r .writer <<<"$out")" "sb"
chk "meta node_id" "$(jq -r .node_id <<<"$out")" "test-node"
chk "meta inbounds count" "$(jq '.inbounds | length' <<<"$out")" "2"
chk "meta inbound tag keeps .json" "$(jq -r '.inbounds[0].tag' <<<"$out")" "trojan-8443.json"
u1=$(jq -r '.inbounds[] | select(.tag=="vless-443.json") | .line_uuid' <<<"$out")
case "$u1" in *-*) ok "fresh line_uuid allocated";; *) bad "fresh line_uuid allocated: $u1";; esac
chk "v1 lines mirror present" "$(jq -r '.lines["vless-443.json"].line_id' <<<"$out")" "$u1"
chk "reserved block" "$(jq -r '.reserved.in_config_key' <<<"$out")" "_lattice"
[ -f "$is_lattice_meta" ] && ok "sidecar written to disk" || bad "sidecar written to disk"

# --- 4. meta: rerun preserves uuids (idempotent) ------------------------------
out2=$(cmd_json_meta 2>/dev/null)
u2=$(jq -r '.inbounds[] | select(.tag=="vless-443.json") | .line_uuid' <<<"$out2")
chk "rerun preserves line_uuid" "$u2" "$u1"

# --- 5. meta: v1 legacy sidecar upgrades preserving identity ------------------
rm -f "$is_lattice_meta"
cat >"$is_lattice_meta" <<'EOF'
{"version":1,"node":{"node_uuid":"55555555-5555-4555-8555-555555555555","node_id":"legacy-node"},
 "lines":{"vless-443.json":{"line_id":"33333333-3333-4333-8333-333333333333"}}}
EOF
LATTICE_NODE_ID=""
out3=$(cmd_json_meta 2>/dev/null)
chk "v1 line_id adopted as line_uuid" \
  "$(jq -r '.inbounds[] | select(.tag=="vless-443.json") | .line_uuid' <<<"$out3")" \
  "33333333-3333-4333-8333-333333333333"
chk "node_id adopted from v1" "$(jq -r .node_id <<<"$out3")" "legacy-node"
chk "node_uuid adopted from v1" "$(jq -r .node_uuid <<<"$out3")" "55555555-5555-4555-8555-555555555555"

# --- 6. meta: missing node id fails loud --------------------------------------
rm -f "$is_lattice_meta"; LATTICE_NODE_ID=""
out4=$(cmd_json_meta 2>&1); rc=$?
[ $rc -ne 0 ] && ok "missing node_id errors" || bad "missing node_id errors: rc=$rc out=$out4"

# --- 7. chain block preserved on rerun ----------------------------------------
cat >"$is_lattice_meta" <<EOF
{"schema":"lattice.singbox-metadata.v2","node_id":"test-node","updated_at":"2026-07-17T00:00:00Z","writer":"lattice-server",
 "future_top":{"keep":true},
 "inbounds":[{"tag":"vless-443.json","line_uuid":"$u1","future_line":"keep","chain":{"downstream_line_uuid":"44444444-4444-4444-8444-444444444444","downstream_node":"qqpw"}}],
 "reserved":{"in_config_key":"_lattice","fields":{"line_uuid":"string","node_uuid":"string","line_hash_id":"string"}}}
EOF
LATTICE_NODE_ID="test-node"
out5=$(cmd_json_meta 2>/dev/null)
chk "chain preserved" "$(jq -c '.inbounds[] | select(.tag=="vless-443.json") | .chain' <<<"$out5")" \
  '{"downstream_line_uuid":"44444444-4444-4444-8444-444444444444","downstream_node":"qqpw"}'
chk "unknown top-level field preserved" "$(jq -r .future_top.keep <<<"$out5")" "true"
chk "unknown inbound field preserved" "$(jq -r '.inbounds[] | select(.tag=="vless-443.json") | .future_line' <<<"$out5")" "keep"

# --- 7b. meta: corrupt/invalid v2 fails closed -------------------------------
printf '%s\n' '{"schema":"lattice.singbox-metadata.v2","inbounds":[{"tag":"vless-443.json","line_uuid":"bad"}]}' >"$is_lattice_meta"
before=$(cat "$is_lattice_meta")
invalid_out=$(cmd_json_meta 2>&1); invalid_rc=$?
[ $invalid_rc -ne 0 ] && ok "invalid v2 sidecar rejected" || bad "invalid v2 sidecar rejected: $invalid_out"
chk "invalid v2 sidecar not overwritten" "$(cat "$is_lattice_meta")" "$before"
rm -f "$is_lattice_meta"
LATTICE_NODE_ID="test-node"; LATTICE_IDENTITY_UUID="not-a-uuid"
invalid_out=$(cmd_json_meta 2>&1); invalid_rc=$?
[ $invalid_rc -ne 0 ] && ok "invalid environment node UUID rejected" || bad "invalid environment node UUID rejected: $invalid_out"
LATTICE_IDENTITY_UUID=""

# --- 7c. exact lookup, ambiguity, and traversal ------------------------------
cp "$is_conf_dir/vless-443.json" "$is_conf_dir/vless-443-copy.json"
chk "exact filename wins over fuzzy matches" "$(json_resolve_config_file vless-443.json)" "vless-443.json"
lookup_out=$(json_resolve_config_file vless 2>&1); lookup_rc=$?
[ $lookup_rc -ne 0 ] && ok "legacy fuzzy lookup rejects ambiguity" || bad "legacy fuzzy lookup rejects ambiguity: $lookup_out"
lookup_out=$(json_resolve_config_file ../vless-443.json 2>&1); lookup_rc=$?
[ $lookup_rc -ne 0 ] && ok "config traversal rejected" || bad "config traversal rejected: $lookup_out"
rm -f "$is_conf_dir/vless-443-copy.json"

# --- 8. stats on/off toggles the experimental API (loopback only) ----------------
out=$(cmd_json_stats on 2>/dev/null)
chk "stats on ok" "$(jq -r .stats <<<"$out")" "on"
chk "stats listen default" "$(jq -r .experimental.v2ray_api.listen "$is_config_json")" "127.0.0.1:8080"
chk "stats enabled" "$(jq -r .experimental.v2ray_api.stats.enabled "$is_config_json")" "true"
out=$(cmd_json_stats on 127.0.0.1:9090 2>/dev/null)
chk "stats custom listen" "$(jq -r .experimental.v2ray_api.listen "$is_config_json")" "127.0.0.1:9090"
out=$(cmd_json_stats on 0.0.0.0:8080 2>&1); rc=$?
[ $rc -ne 0 ] && ok "routable listen rejected" || bad "routable listen rejected: $out"
out=$(cmd_json_stats on 127.evil:8080 2>&1); rc=$?
[ $rc -ne 0 ] && ok "non-literal 127 host rejected" || bad "non-literal 127 host rejected: $out"
out=$(cmd_json_stats on 127.0.0.1:notaport 2>&1); rc=$?
[ $rc -ne 0 ] && ok "bad port rejected" || bad "bad port rejected: $out"
out=$(cmd_json_stats off 2>/dev/null)
chk "stats off ok" "$(jq -r .stats <<<"$out")" "off"
chk "experimental block removed" "$(jq 'has("experimental")' "$is_config_json")" "false"
chk "other keys intact" "$(jq 'has("log") and has("dns")' "$is_config_json")" "true"

manage() { return 1; }
out=$(cmd_json_stats on 2>&1); rc=$?
[ $rc -ne 0 ] && [[ $out == *restart_failed* ]] && ok "restart failure cannot report ok" || bad "restart failure cannot report ok: rc=$rc out=$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
