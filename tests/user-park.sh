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
    json_write_config_atomically json_stats_allowlist_sync json_line_user_opens_proxy cmd_json_user; do
    eval "$(extract_fn $f)"
done
eval "$(awk "/^json_line_user_matches_filter='/,/^'/" "$CORE")"

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

REACHED_END=1
echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
