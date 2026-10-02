#!/usr/bin/env bash
# The line-user verbs a control plane drives on an adopted node: the guard that
# keeps a socks, http or mixed line from ending up with no users, which upstream
# sing-box serves to anyone. Functions are extracted from src/core.sh, so these
# assertions run against the shipped code.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-user-park.XXXXXX)

PASS=0; FAIL=0
# The functions under test end in `exit`. One called outside $(...) would end
# this script silently with status 0, so a truncated run would read as a pass.
# The trap makes that loud; see design-15-user-meta.sh for why it is one trap
# writing to fd 9.
REACHED_END=0
exec 9>&1
trap '
    rm -rf "$TMP"
    if [ "$REACHED_END" != 1 ]; then
        echo >&9
        echo "ABORTED: the suite exited before its summary, after $PASS assertions." >&9
        exit 70
    fi
' EXIT
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

extract_fn() { awk "/^$1\\(\\) \\{/,/^\\}/" "$CORE"; }

# --- stubs -------------------------------------------------------------------
is_core_dir="$TMP/core"; is_conf_dir="$is_core_dir/conf"; mkdir -p "$is_conf_dir"
is_config_json="$is_core_dir/config.json"; echo '{"log":{},"dns":{}}' >"$is_config_json"
is_core_bin=$(command -v true); is_core=sing-box; is_json_out=1
json_err() { printf '{"ok":false,"error":"%s","message":"%s"}\n' "$1" "$2"; exit "${3:-1}"; }
warn() { echo "warn: $*" >&2; }
RESTARTS="$TMP/restarts"
manage() { echo x >>"$RESTARTS"; }
restarts() { [ -f "$RESTARTS" ] && wc -l <"$RESTARTS" | tr -d ' ' || echo 0; }

for f in json_resolve_config_file json_line_user_obj json_line_user_valid \
    json_write_config_atomically json_stats_allowlist_sync json_line_user_opens_proxy json_line_user_plan cmd_json_user; do
    eval "$(extract_fn $f)"
done
eval "$(awk "/^json_line_user_matches_filter='/,/^'/" "$CORE")"
eval "$(awk "/^json_line_user_select_defs='/,/^'/" "$CORE")"

# line <file> <type> <users-json>
line() {
    printf '{"inbounds":[{"tag":"%s","type":"%s","listen":"::","listen_port":1080,"users":%s}]}\n' "$1" "$2" "$3" >"$is_conf_dir/$1"
}
users_of() { jq -c '.inbounds[0].users' "$is_conf_dir/$1"; }
sb_user() { cmd_json_user "$@" 2>&1; }

# --- 1. the open-proxy guard -------------------------------------------------
line socks-1080.json socks '[{"username":"owner","password":"pw-owner"}]'
before=$(users_of socks-1080.json); : >"$RESTARTS"
out=$(sb_user del socks-1080.json '{"username":"owner","password":"pw-owner"}'); rc=$?
chk "removing the only socks user is refused" "$rc" "2"
chk "with an error that names the hazard" "$(jq -r .error <<<"$out")" "last_user_open_proxy"
chk "the socks line keeps its user" "$(users_of socks-1080.json)" "$before"
chk "and nothing restarted" "$(restarts)" "0"

line socks-1081.json socks '[{"username":"owner","password":"pw-owner"},{"username":"guest","password":"pw-guest"}]'
out=$(sb_user del socks-1081.json '{"username":"guest","password":"pw-guest"}'); rc=$?
chk "removing one of two socks users is allowed" "$rc" "0"
chk "and leaves the other" "$(users_of socks-1081.json)" '[{"username":"owner","password":"pw-owner"}]'

# A vless inbound with no users rejects every connection, so emptying it is
# safe and stays allowed: the guard is about what the protocol does when empty.
line vless-443.json vless '[{"uuid":"11111111-1111-4111-8111-111111111111"}]'
out=$(sb_user del vless-443.json '{"uuid":"11111111-1111-4111-8111-111111111111"}'); rc=$?
chk "a vless line may lose its last user" "$rc" "0"
chk "and is left empty" "$(users_of vless-443.json)" "[]"

# http and mixed are refused as unsupported before the guard is reached; the
# guard still covers them, so widening the protocol list cannot reopen this.
line http-8080.json http '[{"username":"a","password":"b"}]'
line mixed-8081.json mixed '[{"username":"a","password":"b"}]'
json_line_user_opens_proxy "$is_conf_dir/http-8080.json" 1 0; chk "http with no users is open" "$?" "0"
json_line_user_opens_proxy "$is_conf_dir/mixed-8081.json" 1 0; chk "mixed with no users is open" "$?" "0"
json_line_user_opens_proxy "$is_conf_dir/mixed-8081.json" 2 1; chk "mixed with one user left is not" "$?" "1"
json_line_user_opens_proxy "$is_conf_dir/vless-443.json" 1 0; chk "vless with no users is not open" "$?" "1"
# Already empty means already open; refusing a no-op would not close it.
json_line_user_opens_proxy "$is_conf_dir/http-8080.json" 0 0; chk "a line that was already empty is not this guard's case" "$?" "1"

# --- 2. a socks user is written the way the core decodes it ------------------
# sing-box v1.13.14 fails a socks file whose user carries "name"
# (inbounds[0].users[0].name: json: unknown field "name"). Lattice sends a
# name and the same value as the username, so the username carries it.
out=$(sb_user add socks-1081.json '{"name":"u_0123456789abcdef","username":"u_0123456789abcdef","password":"pw-lattice"}'); rc=$?
chk "a socks add with a name succeeds" "$rc" "0"
chk "and writes no name field" "$(jq -c '.inbounds[0].users[-1]' "$is_conf_dir/socks-1081.json")" \
    '{"username":"u_0123456789abcdef","password":"pw-lattice"}'
out=$(sb_user add socks-1081.json '{"name":"u_1111111111111111","password":"pw-only-name"}'); rc=$?
chk "a name with no username becomes the username" "$(jq -r '.inbounds[0].users[-1].username' "$is_conf_dir/socks-1081.json")" "u_1111111111111111"

# --- 3. delete by name alone -------------------------------------------------
# The owner's entry has no name; a hand-added entry reuses Lattice's uuid.
OWNER='{"uuid":"11111111-1111-4111-8111-111111111111","flow":"xtls-rprx-vision"}'
LATT='{"name":"u_aaaaaaaaaaaaaaaa","uuid":"22222222-2222-4222-8222-222222222222"}'
TWIN='{"name":"hand-added","uuid":"22222222-2222-4222-8222-222222222222"}'
line hub-a.json vless "[$OWNER,$LATT,$TWIN]"
: >"$RESTARTS"
out=$(sb_user del hub-a.json '{"name":"u_aaaaaaaaaaaaaaaa"}'); rc=$?
chk "a name alone removes a user" "$rc" "0"
chk "only that user" "$(users_of hub-a.json)" "[$OWNER,$TWIN]"
chk "the result says it matched by name" "$(jq -r .match <<<"$out")" "name"
chk "and counts one match" "$(jq -c '[.user_count_before,.user_count_after,.matched]' <<<"$out")" "[3,2,1]"
chk "one restart" "$(restarts)" "1"

: >"$RESTARTS"
out=$(sb_user del hub-a.json '{"name":"u_bbbbbbbbbbbbbbbb"}'); rc=$?
chk "a name the line does not hold is not an error" "$rc" "0"
chk "it reports no change" "$(jq -c '[.changed,.matched]' <<<"$out")" "[false,0]"
chk "and does not restart the node" "$(restarts)" "0"
chk "the line is untouched" "$(users_of hub-a.json)" "[$OWNER,$TWIN]"

line hub-b.json vless '[{"name":"dup","uuid":"33333333-3333-4333-8333-333333333333"},{"name":"dup","uuid":"44444444-4444-4444-8444-444444444444"}]'
before=$(users_of hub-b.json); : >"$RESTARTS"
out=$(sb_user del hub-b.json '{"name":"dup"}'); rc=$?
chk "a name held by two entries is refused" "$rc" "2"
chk "as ambiguous" "$(jq -r .error <<<"$out")" "ambiguous_user"
chk "with both entries kept" "$(users_of hub-b.json)" "$before"
chk "and no restart" "$(restarts)" "0"

# The credential path is unchanged: it still takes every entry sharing a field,
# and the counts say so.
line hub-c.json vless "[$OWNER,$LATT,$TWIN]"
out=$(sb_user del hub-c.json "$LATT"); rc=$?
chk "a credential delete still removes every match" "$(users_of hub-c.json)" "[$OWNER]"
chk "and reports both" "$(jq -c '[.user_count_before,.user_count_after,.matched]' <<<"$out")" "[3,1,2]"
chk "with no by-name fields" "$(jq -c '[has("match"),has("changed")]' <<<"$out")" "[false,false]"
out=$(sb_user add hub-c.json "$LATT"); rc=$?
chk "an add that matches nothing counts zero" "$(jq -c '[.user_count_before,.user_count_after,.matched]' <<<"$out")" "[1,2,0]"
out=$(sb_user add hub-c.json '{"name":"u_aaaaaaaaaaaaaaaa","uuid":"55555555-5555-4555-8555-555555555555"}'); rc=$?
chk "an add that replaces one counts one" "$(jq -c '[.user_count_before,.user_count_after,.matched]' <<<"$out")" "[2,2,1]"

out=$(sb_user add hub-c.json '{"name":"u_cccccccccccccccc"}'); rc=$?
chk "an add still needs a credential" "$(jq -r .error <<<"$out")" "invalid_user"
out=$(sb_user del hub-c.json '{"flow":"xtls-rprx-vision"}'); rc=$?
chk "a del with neither a name nor a credential is refused" "$(jq -r .error <<<"$out")" "invalid_user"

# On socks the username is the name, and the open-proxy guard still holds.
line socks-1082.json socks '[{"username":"owner","password":"pw-owner"},{"username":"u_0123456789abcdef","password":"pw-l"}]'
out=$(sb_user del socks-1082.json '{"name":"u_0123456789abcdef"}'); rc=$?
chk "a socks user is removed by its name" "$(users_of socks-1082.json)" '[{"username":"owner","password":"pw-owner"}]'
line socks-1083.json socks '[{"username":"u_0123456789abcdef","password":"pw-l"}]'
out=$(sb_user del socks-1083.json '{"name":"u_0123456789abcdef"}'); rc=$?
chk "but not when it is the last one" "$(jq -r .error <<<"$out")" "last_user_open_proxy"

REACHED_END=1
echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
