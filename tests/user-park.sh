#!/usr/bin/env bash
# The line-user verbs a control plane drives on an adopted node: the guard that
# keeps a socks, http or mixed line from ending up with no users (upstream
# sing-box serves such a line to anyone), the socks user shape, delete by name,
# park and unpark, what the node reports about parked users, and caps.
# Functions are extracted from src/core.sh, so these assertions run against the
# shipped code.
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
# Each restart also records whether the user lock's descriptor reached it.
manage() {
    if { true >&8; } 2>/dev/null; then echo fd8-open; else echo fd8-closed; fi >>"$RESTARTS.fd"
    echo x >>"$RESTARTS"
}
restarts() { [ -f "$RESTARTS" ] && wc -l <"$RESTARTS" | tr -d ' ' || echo 0; }

# flock(1) is util-linux and macOS has none. Stand in with perl's flock(2) on
# the inherited descriptor: the lock belongs to the open file, so it outlives
# perl and lasts while the shell holds fd 8, exactly as with the real command.
if ! command -v flock >/dev/null 2>&1; then
    flock() {
        [ "$1" = -w ] || return 2
        perl -MFcntl=:flock -e '
            my ($wait, $fd) = @ARGV;
            open(my $fh, ">>&=", $fd) or exit 2;
            my $end = time + $wait;
            until (flock($fh, LOCK_EX | LOCK_NB)) { exit 1 if time >= $end; select(undef, undef, undef, 0.05); }
            exit 0;' "$2" "$3"
    }
fi

for f in json_resolve_config_file json_line_user_obj json_line_user_valid \
    json_write_config_atomically json_stats_allowlist_sync json_line_user_opens_proxy json_line_user_plan \
    json_parked_file json_parked_read json_parked_write json_parked_rename json_parked_summary \
    json_user_lock_available json_user_lock \
    cmd_json_user cmd_json_user_park cmd_json_user_parked json_node_obj cmd_json_caps; do
    eval "$(extract_fn $f)"
done
eval "$(awk "/^json_line_user_matches_filter='/,/^'/" "$CORE")"
eval "$(awk "/^json_line_user_select_defs='/,/^'/" "$CORE")"

# line <file> <type> <users-json>
line() {
    printf '{"inbounds":[{"tag":"%s","type":"%s","listen":"::","listen_port":1080,"users":%s}]}\n' "$1" "$2" "$3" >"$is_conf_dir/$1"
}
users_of() { jq -c '.inbounds[0].users' "$is_conf_dir/$1"; }
PARKED="$is_core_dir/lattice-parked"
parked_of() { if [ -f "$PARKED/$1" ]; then jq -c '[.users[].user]' "$PARKED/$1"; else echo none; fi; }
perm() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
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

# A copy of the command missing a helper refuses instead of skipping the guard.
out=$(unset -f json_line_user_opens_proxy; sb_user del socks-1081.json '{"username":"owner","password":"pw-owner"}'); rc=$?
chk "a copy without the guard refuses" "$rc/$(jq -r .error <<<"$out")" "2/script_incomplete"
chk "and leaves the line alone" "$(users_of socks-1081.json)" '[{"username":"owner","password":"pw-owner"}]'
out=$(unset json_line_user_select_defs; sb_user park socks-1081.json '{"name":"owner"}'); rc=$?
chk "so does one without the selector rule" "$rc/$(jq -r .error <<<"$out")" "2/script_incomplete"

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

# --- 4. park and unpark ------------------------------------------------------
U1='{"name":"u_1111111111111111","uuid":"66666666-6666-4666-8666-666666666661","flow":"xtls-rprx-vision"}'
U2='{"name":"u_2222222222222222","uuid":"66666666-6666-4666-8666-666666666662"}'
U3='{"name":"u_3333333333333333","uuid":"66666666-6666-4666-8666-666666666663"}'
line park-a.json vless "[$OWNER,$U1,$U2,$U3]"
# Stats on, so the allowlist shows whether a parked user stops being counted.
echo '{"log":{},"dns":{},"experimental":{"v2ray_api":{"listen":"127.0.0.1:8080","stats":{"enabled":true}}}}' >"$is_config_json"
: >"$RESTARTS"
out=$(sb_user park park-a.json '{"name":"u_1111111111111111"}'); rc=$?
chk "park by name succeeds" "$rc" "0"
chk "the user leaves the line" "$(users_of park-a.json)" "[$OWNER,$U2,$U3]"
chk "and is parked byte for byte" "$(parked_of park-a.json)" "[$U1]"
chk "with the time it was parked" "$(jq -r '.users[0].parked_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")' "$PARKED/park-a.json")" "true"
chk "the parked file is outside conf" "$(ls "$is_conf_dir" | grep -c '^park-a.json')" "1"
chk "the parked file is 0600" "$(perm "$PARKED/park-a.json")" "600"
chk "its directory is 0700" "$(perm "$PARKED")" "700"
chk "one restart" "$(restarts)" "1"
chk "the counts" "$(jq -c '[.user_count_before,.user_count_after,.matched,.parked_count_before,.parked_count_after]' <<<"$out")" "[4,3,1,0,1]"
chk "the result per selector" "$(jq -c .results <<<"$out")" '[{"selector":0,"name":"u_1111111111111111","state":"parked"}]'
chk "changed and restarted" "$(jq -c '[.changed,.restarted]' <<<"$out")" "[true,true]"
chk "a parked user is no longer counted" \
    "$(jq -r '.experimental.v2ray_api.stats.users | index("u_1111111111111111") // "absent"' "$is_config_json")" "absent"
chk "the others still are" \
    "$(jq -c '.experimental.v2ray_api.stats.users | map(select(startswith("u_2") or startswith("u_3")))' "$is_config_json")" \
    '["u_2222222222222222","u_3333333333333333"]'

: >"$RESTARTS"
before=$(cat "$is_conf_dir/park-a.json")
out=$(sb_user park park-a.json '{"name":"u_1111111111111111"}'); rc=$?
chk "parking a parked user is not an error" "$rc" "0"
chk "it says so" "$(jq -r '.results[0].state' <<<"$out")" "already_parked"
chk "and changes nothing" "$(jq -c '[.changed,.restarted]' <<<"$out")" "[false,false]"
chk "no restart for a no-op" "$(restarts)" "0"
chk "the conf file is byte-identical" "$(cat "$is_conf_dir/park-a.json")" "$before"

# A batch: one active, one parked, one the line never held. One restart.
: >"$RESTARTS"
out=$(sb_user park park-a.json '[{"name":"u_2222222222222222"},{"name":"u_1111111111111111"},{"name":"u_9999999999999999"}]'); rc=$?
chk "a batch park succeeds" "$rc" "0"
chk "with one result each" "$(jq -c '[.results[].state]' <<<"$out")" '["parked","already_parked","absent"]'
chk "and one restart for the batch" "$(restarts)" "1"
chk "both parked users are held" "$(parked_of park-a.json)" "[$U1,$U2]"
chk "the line keeps the rest" "$(users_of park-a.json)" "[$OWNER,$U3]"

: >"$RESTARTS"
out=$(sb_user unpark park-a.json '[{"name":"u_1111111111111111"},{"name":"u_2222222222222222"}]'); rc=$?
chk "a batch unpark succeeds" "$rc" "0"
chk "both are restored" "$(jq -c '[.results[].state]' <<<"$out")" '["restored","restored"]'
chk "exactly as they were" "$(users_of park-a.json)" "[$OWNER,$U3,$U1,$U2]"
chk "the empty parked file is removed" "$(parked_of park-a.json)" "none"
chk "one restart" "$(restarts)" "1"
chk "unpark counts" "$(jq -c '[.user_count_before,.user_count_after,.matched,.parked_count_before,.parked_count_after]' <<<"$out")" "[2,4,2,2,0]"
chk "restored users are counted again" \
    "$(jq -r '.experimental.v2ray_api.stats.users | index("u_1111111111111111") != null' "$is_config_json")" "true"

: >"$RESTARTS"
out=$(sb_user unpark park-a.json '[{"name":"u_1111111111111111"},{"name":"u_9999999999999999"}]'); rc=$?
chk "unparking an active user is not an error" "$(jq -c '[.results[].state]' <<<"$out")" '["already_active","absent"]'
chk "and does not restart" "$(restarts)" "0"
echo '{"log":{},"dns":{}}' >"$is_config_json"

# Ambiguity and conflicts refuse the whole call and write nothing.
line park-b.json vless '[{"name":"dup","uuid":"77777777-7777-4777-8777-777777777771"},{"name":"dup","uuid":"77777777-7777-4777-8777-777777777772"},{"name":"u_4444444444444444","uuid":"77777777-7777-4777-8777-777777777773"}]'
before=$(users_of park-b.json); : >"$RESTARTS"
out=$(sb_user park park-b.json '[{"name":"u_4444444444444444"},{"name":"dup"}]'); rc=$?
chk "a batch with an ambiguous selector is refused" "$(jq -r .error <<<"$out")" "ambiguous_user"
chk "nothing in the batch is applied" "$(users_of park-b.json)" "$before"
chk "no parked file appears" "$(parked_of park-b.json)" "none"
chk "and nothing restarts" "$(restarts)" "0"
out=$(sb_user park park-b.json '{"uuid":"77777777-7777-4777-8777-777777777773"}'); rc=$?
chk "a selector without a name parks by credential" "$(jq -r '.results[0].state' <<<"$out")" "parked"
chk "the parked entry is that one" "$(parked_of park-b.json)" '[{"name":"u_4444444444444444","uuid":"77777777-7777-4777-8777-777777777773"}]'

line park-c.json vless '[{"uuid":"88888888-8888-4888-8888-888888888881"},{"name":"u_5555555555555555","uuid":"88888888-8888-4888-8888-888888888882"}]'
mkdir -p "$PARKED"
printf '%s\n' '{"schema":"lattice.singbox-parked.v1","users":[{"user":{"name":"u_5555555555555555","uuid":"88888888-8888-4888-8888-000000000000"},"parked_at":"2026-10-01T00:00:00Z"}]}' >"$PARKED/park-c.json"
pbefore=$(cat "$PARKED/park-c.json"); before=$(users_of park-c.json)
out=$(sb_user park park-c.json '{"name":"u_5555555555555555"}'); rc=$?
chk "parking over a different parked copy is a conflict" "$(jq -r .error <<<"$out")" "conflict"
out=$(sb_user unpark park-c.json '{"name":"u_5555555555555555"}'); rc=$?
chk "so is unparking onto a different active entry" "$(jq -r .error <<<"$out")" "conflict"
chk "neither touches the line" "$(users_of park-c.json)" "$before"
chk "nor the parked copy" "$(cat "$PARKED/park-c.json")" "$pbefore"

# An identical pair is what a half-finished unpark leaves; the next one heals it.
printf '%s\n' '{"schema":"lattice.singbox-parked.v1","users":[{"user":{"name":"u_5555555555555555","uuid":"88888888-8888-4888-8888-888888888882"},"parked_at":"2026-10-01T00:00:00Z"}]}' >"$PARKED/park-c.json"
: >"$RESTARTS"
out=$(sb_user unpark park-c.json '{"name":"u_5555555555555555"}'); rc=$?
chk "an identical parked copy is dropped" "$(jq -r '.results[0].state' <<<"$out")" "already_active"
chk "the parked file goes" "$(parked_of park-c.json)" "none"
chk "without a restart, since the line did not change" "$(restarts)" "0"

# The open-proxy guard holds for park as well.
line socks-1090.json socks '[{"username":"u_6666666666666666","password":"pw"}]'
out=$(sb_user park socks-1090.json '{"name":"u_6666666666666666"}'); rc=$?
chk "parking the last socks user is refused" "$(jq -r .error <<<"$out")" "last_user_open_proxy"
chk "and nothing is parked" "$(parked_of socks-1090.json)" "none"
line socks-1091.json socks '[{"username":"owner","password":"pw-o"},{"username":"u_6666666666666666","password":"pw"}]'
out=$(sb_user park socks-1091.json '{"name":"u_6666666666666666"}'); rc=$?
chk "a socks user with company is parked by its username" "$(parked_of socks-1091.json)" '[{"username":"u_6666666666666666","password":"pw"}]'

# A core that rejects the result: park puts the parked file back.
line park-d.json vless "[$OWNER,$U1]"
before=$(users_of park-d.json)
is_core_bin=$(command -v false)
out=$(sb_user park park-d.json '{"name":"u_1111111111111111"}'); rc=$?
chk "a rejected park fails" "$(jq -r .error <<<"$out")" "config_invalid"
chk "the line is rolled back" "$(users_of park-d.json)" "$before"
chk "and the parked copy is withdrawn" "$(parked_of park-d.json)" "none"
is_core_bin=$(command -v true)
out=$(sb_user park park-d.json '{"name":"u_1111111111111111"}')
is_core_bin=$(command -v false)
out=$(sb_user unpark park-d.json '{"name":"u_1111111111111111"}'); rc=$?
chk "a rejected unpark fails" "$(jq -r .error <<<"$out")" "config_invalid"
chk "the user stays parked" "$(parked_of park-d.json)" "[$U1]"
chk "and off the line" "$(users_of park-d.json)" "[$OWNER]"
is_core_bin=$(command -v true)

# A damaged parked file is never overwritten.
printf 'not json\n' >"$PARKED/park-d.json"
out=$(sb_user park park-d.json '{"name":"u_1111111111111111"}'); rc=$?
chk "park refuses a damaged parked file" "$(jq -r .error <<<"$out")" "parked_invalid"
chk "and leaves it as it was" "$(cat "$PARKED/park-d.json")" "not json"
line park-d.json vless "[$OWNER,$U2]"
out=$(sb_user del park-d.json "$U2"); rc=$?
chk "del still revokes on the line" "$(users_of park-d.json)" "[$OWNER]"
chk "and reports the damaged file" "$(jq -r .parked_invalid <<<"$out")" "true"
chk "without touching it" "$(cat "$PARKED/park-d.json")" "not json"
rm -f "$PARKED/park-d.json"

# Deleting a parked user takes the parked copy, so unpark cannot bring it back.
line park-e.json vless "[$OWNER,$U1,$U2]"
out=$(sb_user park park-e.json "[{\"name\":\"u_1111111111111111\"},{\"name\":\"u_2222222222222222\"}]")
: >"$RESTARTS"
out=$(sb_user del park-e.json '{"name":"u_1111111111111111"}'); rc=$?
chk "a by-name delete of a parked user succeeds" "$rc" "0"
chk "the parked copy is gone" "$(parked_of park-e.json)" "[$U2]"
chk "it reports the change" "$(jq -c '[.changed,.parked_count_before,.parked_count_after]' <<<"$out")" "[true,2,1]"
chk "without restarting, since the line did not change" "$(restarts)" "0"
out=$(sb_user del park-e.json "$U2"); rc=$?
chk "a credential delete takes the parked copy too" "$(parked_of park-e.json)" "none"
line park-e.json vless "[$OWNER,$U1]"
out=$(sb_user park park-e.json '{"name":"u_1111111111111111"}')
out=$(sb_user add park-e.json '{"name":"u_1111111111111111","uuid":"66666666-6666-4666-8666-0000000000aa"}'); rc=$?
chk "an add supersedes the parked copy of that name" "$(parked_of park-e.json)" "none"
chk "and reports it" "$(jq -c '[.parked_count_before,.parked_count_after]' <<<"$out")" "[1,0]"

# A del whose parked copy cannot be removed is not done: that copy is the
# revoked credential waiting for an unpark. The call fails so the caller
# repeats it, and the repeat finishes the job.
line park-f.json vless "[$OWNER,$U1]"
out=$(sb_user park park-f.json '{"name":"u_1111111111111111"}')
out=$(json_parked_write() { return 1; }; sb_user del park-f.json '{"name":"u_1111111111111111"}'); rc=$?
chk "a by-name del that leaves the parked copy fails" "$rc/$(jq -c '[.ok,.error,.parked_stale]' <<<"$out")" '1/[false,"parked_stale",true]'
chk "the copy is still there" "$(parked_of park-f.json)" "[$U1]"
out=$(sb_user del park-f.json '{"name":"u_1111111111111111"}'); rc=$?
chk "repeating the del removes it" "$rc/$(parked_of park-f.json)" "0/none"
# The same with the user active as well, which a half-finished unpark leaves.
line park-f.json vless "[$OWNER,$U1]"
mkdir -p "$PARKED"
printf '{"schema":"lattice.singbox-parked.v1","users":[{"user":%s,"parked_at":"2026-10-01T00:00:00Z"}]}\n' "$U1" >"$PARKED/park-f.json"
: >"$RESTARTS"
out=$(json_parked_write() { return 1; }; sb_user del park-f.json "$U1"); rc=$?
chk "a credential del that leaves the parked copy fails too" "$rc/$(jq -r .error <<<"$out")" "1/parked_stale"
chk "after revoking on the line and restarting" "$(users_of park-f.json)/$(restarts)" "[$OWNER]/1"
out=$(sb_user del park-f.json "$U1"); rc=$?
chk "and a repeat removes the copy" "$rc/$(parked_of park-f.json)" "0/none"
# An add that cannot drop a superseded copy still succeeds: unpark refuses that
# copy as a conflict, so it cannot bring the old credential back.
line park-f.json vless "[$OWNER,$U1]"
out=$(sb_user park park-f.json '{"name":"u_1111111111111111"}')
out=$(json_parked_write() { return 1; }; sb_user add park-f.json '{"name":"u_1111111111111111","uuid":"66666666-6666-4666-8666-0000000000bb"}'); rc=$?
chk "an add that leaves a stale copy still succeeds" "$rc/$(jq -c '[.ok,.parked_stale]' <<<"$out")" "0/[true,true]"
out=$(sb_user unpark park-f.json '{"name":"u_1111111111111111"}'); rc=$?
chk "and unpark refuses that copy" "$(jq -r .error <<<"$out")" "conflict"
rm -f "$PARKED/park-f.json"

# Payload shapes.
out=$(sb_user park park-e.json '[]'); chk "an empty batch is refused" "$(jq -r .error <<<"$out")" "invalid_payload"
out=$(sb_user park park-e.json '["u_1"]'); chk "a batch of strings is refused" "$(jq -r .error <<<"$out")" "invalid_payload"
out=$(sb_user park park-e.json '{"flow":"xtls-rprx-vision"}'); chk "a selector with nothing to match is refused" "$(jq -r .error <<<"$out")" "invalid_user"
out=$(sb_user park http-8080.json '{"username":"a"}'); chk "an unsupported protocol is refused" "$(jq -r .error <<<"$out")" "unsupported_protocol"

# A renamed line keeps its parked users, and a rename never overwrites another
# line's parked file.
printf '%s\n' '{"schema":"lattice.singbox-parked.v1","users":[{"user":{"name":"u_7","uuid":"x"},"parked_at":"t"}]}' >"$PARKED/old-name.json"
json_parked_rename old-name.json new-name.json
chk "a rename moves the parked file" "$( [ -f "$PARKED/new-name.json" ] && [ ! -f "$PARKED/old-name.json" ] && echo moved)" "moved"
printf '%s\n' '{"schema":"lattice.singbox-parked.v1","users":[{"user":{"name":"u_8","uuid":"y"},"parked_at":"t"}]}' >"$PARKED/old-name.json"
json_parked_rename old-name.json new-name.json 2>/dev/null
chk "but not over another line's" "$(jq -r '.users[0].user.name' "$PARKED/new-name.json")/$( [ -f "$PARKED/old-name.json" ] && echo kept)" "u_7/kept"
rm -f "$PARKED/old-name.json" "$PARKED/new-name.json"

# --- 5. what the node reports about parked users -----------------------------
rm -rf "$PARKED"
line rep-a.json vless "[$OWNER,$U1,$U2]"
line rep-b.json trojan '[{"password":"owner-pw"},{"name":"alice","password":"alice-pw"},{"name":"u_aaaaaaaaaaaaaaab","password":"l-pw"}]'
out=$(sb_user park rep-a.json "[{\"name\":\"u_1111111111111111\"},{\"name\":\"u_2222222222222222\"}]")
out=$(sb_user park rep-b.json '[{"name":"alice"},{"name":"u_aaaaaaaaaaaaaaab"}]')
# main passes three arguments, empty when absent; so does every call here.
out=$(sb_user parked "" ""); rc=$?
chk "user parked lists every line with parked users" "$(jq -c '[.count, [.lines[].line]]' <<<"$out")" '[2,["rep-a.json","rep-b.json"]]'
chk "with a count and Lattice's names" "$(jq -c '.lines[0] | [.parked_users, .parked_names]' <<<"$out")" '[2,["u_1111111111111111","u_2222222222222222"]]'
chk "a hand-made name is counted but not listed" "$(jq -c '.lines[1] | [.parked_users, .parked_names]' <<<"$out")" '[2,["u_aaaaaaaaaaaaaaab"]]'
chk "and no credential leaves the node" "$(grep -c 'pw\|6666-' <<<"$out")" "0"
out=$(sb_user parked hub-a.json "")
chk "one line with nothing parked reports zero" "$(jq -c '.lines[0] | [.line, .parked_users, .parked_names]' <<<"$out")" '["hub-a.json",0,[]]'
cp "$PARKED/rep-a.json" "$PARKED/gone.json"; printf 'junk\n' >"$PARKED/broken.json"
out=$(sb_user parked "" "")
chk "a parked file whose line is gone is marked orphaned" "$(jq -c '[.lines[] | select(.line == "gone.json") | .orphaned]' <<<"$out")" '[true]'
chk "a damaged one is marked, not skipped" "$(jq -c '[.lines[] | select(.line == "broken.json") | .error]' <<<"$out")" '["parked_invalid"]'
rm -f "$PARKED/gone.json" "$PARKED/broken.json"
rm -rf "$PARKED"; out=$(sb_user parked "" "")
chk "no parked directory is an empty list" "$out" '{"ok":true,"count":0,"lines":[]}'
line rep-a.json vless "[$OWNER,$U1,$U2]"
out=$(sb_user park rep-a.json '{"name":"u_1111111111111111"}')

# `sb --json list` carries the same summary in the line metadata, which the
# agent forwards as map[string]string: every value must be a string.
node_obj() (
    is_config_name=$1; is_protocol=vless; net=tcp; is_addr=203.0.113.7; port=443
    is_https_port=""; host=""; path=""; uuid=""; password=""; ss_password=""
    ss_method=""; is_servername=""; is_public_key=""; is_url=""
    lattice_meta_obj_for() { printf '{}\n'; }
    route_maps_json() { printf '{"routes":{},"types":{}}'; }
    json_node_obj
)
out=$(node_obj rep-a.json)
chk "list metadata counts parked users" "$(jq -r .metadata.parked_users <<<"$out")" "1"
chk "and names them as a JSON string" "$(jq -r .metadata.parked_names <<<"$out")" '["u_1111111111111111"]'
chk "every metadata value is a string" "$(jq '[.metadata[] | type] | unique' -c <<<"$out")" '["string"]'
chk "user_count is the active users only" "$(jq -r .user_count <<<"$out")" "2"
out=$(node_obj hub-a.json)
chk "a line with nothing parked has no parked keys" "$(jq -c '.metadata | [has("parked_users"), has("parked_names")]' <<<"$out")" "[false,false]"
mkdir -p "$PARKED"; printf 'junk\n' >"$PARKED/hub-a.json"
out=$(node_obj hub-a.json)
chk "a damaged parked file is reported in the metadata" "$(jq -r .metadata.parked_error <<<"$out")" "parked_invalid"
rm -f "$PARKED/hub-a.json"

# --- 6. capabilities ---------------------------------------------------------
out=$(is_sh_ver=v1.24.3-alpha.8; cmd_json_caps); rc=$?
chk "caps answers" "$(jq -c '[.ok, .script]' <<<"$out")" '[true,"v1.24.3-alpha.8"]'
chk "and names what this script does" "$(jq -c '.caps | sort' <<<"$out")" \
    '["user-del-by-name","user-lock","user-match-counts","user-open-proxy-guard","user-park","user-parked-list","user-socks-add"]'
out=$(json_user_lock_available() { return 1; }; cmd_json_caps)
chk "a node without flock does not claim the lock" "$(jq -c '.caps | index("user-lock")' <<<"$out")" "null"
chk "the entry point routes caps" "$(awk '/^main\(\) \{/,/^\}/' "$CORE" | grep -A1 '^    caps)' | tail -1 | tr -d ' ')" "cmd_json_caps"

# --- 7. one user change at a time --------------------------------------------
# Two parks of different users on one line, each with a parked-file read slow
# enough for the other call to read the same state meanwhile. Unlocked, the
# later write is built from a list that still holds the other user, so that
# user comes back on the line and drops out of the parked file.
eval "slow_$(declare -f json_parked_read)"
json_parked_read() { slow_json_parked_read "$@"; local rc=$?; sleep 1; return $rc; }
line race-a.json vless "[$OWNER,$U1,$U2]"
: >"$RESTARTS"
sb_user park race-a.json '{"name":"u_1111111111111111"}' >"$TMP/race-1" &
r1=$!
sb_user park race-a.json '{"name":"u_2222222222222222"}' >"$TMP/race-2" &
r2=$!
wait $r1; rc1=$?
wait $r2; rc2=$?
eval "$(extract_fn json_parked_read)"
chk "two parks at once both succeed" "$rc1/$rc2" "0/0"
chk "neither user is left on the line" "$(users_of race-a.json)" "[$OWNER]"
chk "both are parked" "$(jq -c '[.users[].user.name] | sort' "$PARKED/race-a.json")" \
    '["u_1111111111111111","u_2222222222222222"]'
chk "one restart each" "$(restarts)" "2"
chk "no restart in this suite was handed the lock's descriptor" "$(sort -u "$RESTARTS.fd")" "fd8-closed"

# A call that cannot get the lock in time refuses before it reads anything.
LOCK="$is_core_dir/lattice-user.lock"
exec 7>>"$LOCK"; flock -w 1 7
line race-b.json vless "[$OWNER,$U1]"
before=$(users_of race-b.json); : >"$RESTARTS"
out=$(is_lattice_user_lock_wait=1; sb_user park race-b.json '{"name":"u_1111111111111111"}'); rc=$?
chk "a park that cannot get the lock is refused" "$rc" "2"
chk "as busy" "$(jq -r .error <<<"$out")" "busy"
out=$(is_lattice_user_lock_wait=1; sb_user del race-b.json "$U1"); rc=$?
chk "so is a del" "$rc/$(jq -r .error <<<"$out")" "2/busy"
chk "having changed nothing" "$(users_of race-b.json)/$(parked_of race-b.json)/$(restarts)" "$before/none/0"
out=$(sb_user parked race-b.json ""); rc=$?
chk "listing parked users takes no lock" "$rc" "0"
out=$(json_user_lock_available() { return 1; }; sb_user add race-b.json "$U2"); rc=$?
chk "a node without flock runs the call unlocked, as before" "$rc/$(users_of race-b.json)" "0/[$OWNER,$U1,$U2]"
exec 7>&-
out=$(sb_user park race-b.json '{"name":"u_1111111111111111"}'); rc=$?
chk "once the lock is free the park goes through" "$(jq -r '.results[0].state' <<<"$out")" "parked"

REACHED_END=1
echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
