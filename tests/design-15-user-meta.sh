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
eval "$(extract_fn json_write_config_atomically)"
eval "$(extract_fn json_stats_allowlist_sync)"
eval "$(extract_fn cmd_json_user)"
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
manage() { :; }

# --- 9. the stats allowlist names what the core has to count ------------------
# sing-box counts only what these lists name, so "enabled" with empty lists is
# a stats service that measures nothing.
echo '{"log":{},"dns":{},"outbounds":[{"tag":"direct","type":"direct"},{"tag":"warp","type":"wireguard"}]}' >"$is_config_json"
cat >"$is_conf_dir/named-users.json" <<'EOF'
{"inbounds":[{"tag":"named-users.json","type":"vless","listen_port":9443,
"users":[{"name":"u_1111111111111111","uuid":"aaaa"},{"uuid":"bbbb"},{"name":"","uuid":"cccc"}]}],
"outbounds":[{"tag":"direct","type":"direct"}]}
EOF
out=$(cmd_json_stats on 2>/dev/null)
chk "stats on still reports ok" "$(jq -r .stats <<<"$out")" "on"
chk "allowlist carries every inbound tag" \
  "$(jq -r '.experimental.v2ray_api.stats.inbounds | sort | join(",")' "$is_config_json")" \
  "named-users.json,trojan-8443.json,vless-443.json"
chk "allowlist carries every outbound tag, deduplicated" \
  "$(jq -r '.experimental.v2ray_api.stats.outbounds | sort | join(",")' "$is_config_json")" \
  "direct,warp"
chk "allowlist carries named users only" \
  "$(jq -r '.experimental.v2ray_api.stats.users | join(",")' "$is_config_json")" \
  "u_1111111111111111"

# A user added after the fact has to reach the allowlist, or its traffic is
# counted at the line and never against the person.
jq '.inbounds[0].users += [{"name":"u_2222222222222222","uuid":"dddd"}]' "$is_conf_dir/named-users.json" >"$TMP/u" && mv "$TMP/u" "$is_conf_dir/named-users.json"
json_stats_allowlist_sync; rc=$?
chk "sync after a user add succeeds" "$rc" "0"
chk "the new user is counted" \
  "$(jq -r '.experimental.v2ray_api.stats.users | sort | join(",")' "$is_config_json")" \
  "u_1111111111111111,u_2222222222222222"

# Deleting a line drops its tags, so a later line reusing the name cannot
# inherit the old counter.
rm -f "$is_conf_dir/named-users.json"
json_stats_allowlist_sync
chk "a deleted line leaves the allowlist" \
  "$(jq -r '.experimental.v2ray_api.stats.inbounds | index("named-users.json") // "absent"' "$is_config_json")" \
  "absent"
chk "its users leave with it" \
  "$(jq -r '.experimental.v2ray_api.stats.users | length' "$is_config_json")" \
  "0"

# Off means off: the sync never enables the API on its own.
before=$(jq -cS . "$is_config_json")
jq 'del(.experimental)' "$is_config_json" >"$TMP/u" && mv "$TMP/u" "$is_config_json"
json_stats_allowlist_sync; rc=$?
chk "sync is a no-op while stats are off" "$rc" "0"
chk "sync does not enable the API" "$(jq 'has("experimental")' "$is_config_json")" "false"

# A config the core rejects is rolled back, and the caller is told.
jq '.experimental.v2ray_api={listen:"127.0.0.1:8080",stats:{enabled:true}}' "$is_config_json" >"$TMP/u" && mv "$TMP/u" "$is_config_json"
before=$(jq -cS . "$is_config_json")
is_core_bin=$(command -v false)
json_stats_allowlist_sync; rc=$?
chk "a rejected config reports failure" "$rc" "1"
chk "a rejected config is rolled back" "$(jq -cS . "$is_config_json")" "$before"
chk "no backup file is left behind" "$(ls "$TMP" | grep -c 'config.json.backup-')" "0"
is_core_bin=$(command -v true)


# --- 10. a failed allowlist sync must not skip the restart -------------------
#
# The user row is written to disk before the sync runs. On `user del` that row
# is a revoked credential, and it stays live on the running proxy until
# something restarts it. Exiting on a sync failure left the node serving a
# credential the operator had just removed, and reported it as a stats problem.
#
# cmd_json_user runs inside a command substitution, so the restart is counted
# through a file rather than a variable: a subshell's variables do not survive.
echo '{"log":{},"dns":{},"outbounds":[{"tag":"direct","type":"direct"}],"experimental":{"v2ray_api":{"listen":"127.0.0.1:8080","stats":{"enabled":true,"inbounds":["restart-probe.json"],"outbounds":["direct"],"users":["u_9999999999999999"]}}}}' >"$is_config_json"
mkuser() {
  cat >"$is_conf_dir/restart-probe.json" <<EOF
{"inbounds":[{"tag":"restart-probe.json","type":"vless","listen_port":9444,
"users":[{"name":"$1","uuid":"$2"}]}]}
EOF
}
RESTARTS="$TMP/restarts"
manage() { echo x >>"$RESTARTS"; }
restart_count() { [ -f "$RESTARTS" ] && wc -l <"$RESTARTS" | tr -d ' ' || echo 0; }

mkuser u_9999999999999999 99999999-9999-4999-8999-999999999999
: >"$RESTARTS"
out=$(cmd_json_user del restart-probe.json '{"name":"u_9999999999999999","uuid":"99999999-9999-4999-8999-999999999999"}' 2>&1) || true
chk "a healthy user del restarts" "$(restart_count)" "1"
chk "the user is gone from disk" "$(jq '(.inbounds[0].users // []) | length' "$is_conf_dir/restart-probe.json")" "0"
chk "the healthy path reports no staleness" "$(jq 'has("stats_allowlist_stale")' <<<"$out")" "false"

# Fail the sync the way it fails in the field: an unrelated file in the conf
# directory that jq cannot parse. The user write itself still succeeds, which
# is what makes the skipped restart dangerous rather than merely untidy.
mkuser u_8888888888888888 88888888-8888-4888-8888-888888888888
printf 'not json at all\n' >"$is_conf_dir/broken-sidecar.json"
: >"$RESTARTS"
out=$(cmd_json_user del restart-probe.json '{"name":"u_8888888888888888","uuid":"88888888-8888-4888-8888-888888888888"}' 2>&1) || true
chk "the revoked user is gone from disk" "$(jq '(.inbounds[0].users // []) | length' "$is_conf_dir/restart-probe.json")" "0"
if [ "$(restart_count)" -ge 1 ]; then ok "a failed allowlist sync still restarts"; else bad "a failed allowlist sync skipped the restart: the revoked user stays live (out=$out)"; fi
chk "the failure is reported, not hidden" "$(jq 'has("stats_allowlist_stale")' <<<"$out" 2>/dev/null)" "true"
rm -f "$is_conf_dir/broken-sidecar.json" "$is_conf_dir/restart-probe.json"
manage() { :; }

# --- 11. the config is replaced by a rename within its own filesystem --------
#
# mv is atomic only inside one filesystem. With the temp file in $TMPDIR it
# falls back to copy-then-unlink across a boundary, and a crash mid-write
# leaves a truncated config.json with no rollback, on the one file the node
# cannot start without. The agent gives a task its own /tmp, so the boundary is
# the normal case rather than the exotic one.
# TMPDIR is made unwritable rather than merely observed: that is the only way
# to assert the staging file is not put there, since a run that stages in
# TMPDIR and then moves the file away leaves the directory empty either way.
export TMPDIR="$TMP/elsewhere"; mkdir -p "$TMPDIR"; chmod 500 "$TMPDIR"
jq '.experimental.v2ray_api.stats = {enabled:true}' "$is_config_json" >"$TMP/u" && mv "$TMP/u" "$is_config_json"
json_stats_allowlist_sync; rc=$?
chk "the sync does not need a writable TMPDIR" "$rc" "0"
chk "the sync wrote the allowlist" "$(jq '.experimental.v2ray_api.stats | has("inbounds")' "$is_config_json")" "true"
chk "no temp file is left beside the config" "$(ls "$(dirname "$is_config_json")" | grep -c 'config.json.stats-new')" "0"
chmod 700 "$TMPDIR"; unset TMPDIR

# --- 12. a successful write leaves no backup behind ---------------------------
#
# The backup exists so the file can be rolled back if the core rejects the
# result. Once the core has accepted it, the backup has no job left, and for a
# conf file it is a plaintext copy of that line's user credentials sitting next
# to the live one. One was written on every user add and delete and never
# removed, so a node accumulated them without bound.
#
# This also removes a flake. The assertion in section 9 greps the config
# directory for leftovers, and `cmd_json_stats` writes through
# json_edit_config_atomically, so it left one about 70% of the time: the names
# carry one-second granularity, and a second write inside the same second
# happened to delete the first by reusing its name.
manage() { :; }
is_core_bin=$(command -v true)
cat >"$is_conf_dir/backup-probe.json" <<'EOF'
{"inbounds":[{"tag":"backup-probe.json","type":"vless","listen_port":9555,"users":[]}]}
EOF
out=$(cmd_json_user add backup-probe.json '{"name":"u_7777777777777777","uuid":"77777777-7777-4777-8777-777777777777"}' 2>&1) || true
chk "the user was added" "$(jq '(.inbounds[0].users // []) | length' "$is_conf_dir/backup-probe.json")" "1"
chk "no credential-bearing backup survives a successful add" "$(ls "$is_conf_dir" | grep -c 'backup-probe.json.backup-')" "0"

# Repeat across several writes: one leftover per mutation is the shape that
# accumulated in production, and a single-write test would not show it.
for i in 1 2 3; do
  cmd_json_user del backup-probe.json '{"name":"u_7777777777777777","uuid":"77777777-7777-4777-8777-777777777777"}' >/dev/null 2>&1 || true
  cmd_json_user add backup-probe.json '{"name":"u_7777777777777777","uuid":"77777777-7777-4777-8777-777777777777"}' >/dev/null 2>&1 || true
done
chk "nor after several mutations" "$(ls "$is_conf_dir" | grep -c 'backup-probe.json.backup-')" "0"

# A rejected write must still roll back, and must not leave the backup either.
before=$(jq -c . "$is_conf_dir/backup-probe.json")
is_core_bin=$(command -v false)
out=$(cmd_json_user del backup-probe.json '{"name":"u_7777777777777777","uuid":"77777777-7777-4777-8777-777777777777"}' 2>&1) || true
chk "a rejected write rolls the file back" "$(jq -c . "$is_conf_dir/backup-probe.json")" "$before"
chk "and leaves no backup" "$(ls "$is_conf_dir" | grep -c 'backup-probe.json.backup-')" "0"
is_core_bin=$(command -v true)
rm -f "$is_conf_dir/backup-probe.json"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
