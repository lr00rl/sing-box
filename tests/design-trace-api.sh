#!/usr/bin/env bash
# Local harness for the Clash API command. Extracts the functions under test
# from src/core.sh (no Linux box needed) and asserts behavior with temp dirs.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-api-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok   - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

extract_fn() { awk "/^$1\\(\\) \\{/,/^\\}/" "$CORE"; }

# --- stubs -----------------------------------------------------------------
is_config_json="$TMP/config.json"
is_clash_api_secret="$TMP/lattice-clash-api.secret"
is_core_bin=$(command -v true); is_core=sing-box
get_uuid() { tmp_uuid=$(uuidgen | tr 'A-F' 'a-f'); }
json_err() { printf '{"ok":false,"error":"%s","message":"%s"}\n' "$1" "$2" >&2; exit "${3:-1}"; }
manage() { :; }
chown() { :; }
is_json_out=1

eval "$(extract_fn json_edit_config_atomically)"
eval "$(extract_fn cmd_json_api)"
echo '{"log":{},"dns":{}}' >"$is_config_json"

# --- 1. api on writes the default Clash API block ---------------------------
out=$(cmd_json_api on 2>/dev/null)
chk "api on ok" "$(jq -r .api <<<"$out")" "on"
chk "api listen default" "$(jq -r .listen <<<"$out")" "127.0.0.1:9090"
chk "api on output" "$out" \
  "{\"ok\":true,\"api\":\"on\",\"listen\":\"127.0.0.1:9090\",\"secret_path\":\"$is_clash_api_secret\"}"
chk "api block default" \
  "$(jq -c '.experimental.clash_api | {external_controller,secret}' "$is_config_json")" \
  "$(jq -nc --arg secret "$(cat "$is_clash_api_secret")" '{external_controller:"127.0.0.1:9090",secret:$secret}')"
chk "api secret path" "$(jq -r .secret_path <<<"$out")" "$is_clash_api_secret"

# --- 2. explicit valid loopback listen --------------------------------------
out=$(cmd_json_api on 127.1.2.3:9191 2>/dev/null)
chk "api custom listen output" "$(jq -r .listen <<<"$out")" "127.1.2.3:9191"
chk "api custom listen config" "$(jq -r .experimental.clash_api.external_controller "$is_config_json")" "127.1.2.3:9191"

# --- 3. routable hosts and invalid ports are rejected -----------------------
for case_data in \
  "wildcard|0.0.0.0:9090" \
  "public IP|8.8.8.8:9090" \
  "non-local hostname|api.example.com:9090" \
  "port zero|127.0.0.1:0" \
  "port too high|127.0.0.1:70000"
do
    label=${case_data%%|*}
    listen=${case_data#*|}
    reject_out=$(cmd_json_api on "$listen" 2>&1); reject_rc=$?
    [ $reject_rc -eq 2 ] && [[ $reject_out == *invalid_listen* ]] \
        && ok "$label rejected" || bad "$label rejected: rc=$reject_rc out=$reject_out"
done

# --- 4. off removes empty experimental and preserves other keys -------------
out=$(cmd_json_api off 2>/dev/null)
chk "api off ok" "$(jq -r .api <<<"$out")" "off"
chk "api off output" "$out" '{"ok":true,"api":"off"}'
chk "empty experimental removed" "$(jq 'has("experimental")' "$is_config_json")" "false"
cat >"$is_config_json" <<EOF
{"log":{},"experimental":{"cache_file":{"enabled":true},"clash_api":{"external_controller":"127.0.0.1:9090","secret":"$(cat "$is_clash_api_secret")"}}}
EOF
out=$(cmd_json_api off 2>/dev/null)
chk "api removed beside other experimental keys" "$(jq '.experimental | has("clash_api")' "$is_config_json")" "false"
chk "non-empty experimental kept" "$(jq -r .experimental.cache_file.enabled "$is_config_json")" "true"

# --- 5. rerunning on reuses and protects the secret -------------------------
secret_before=$(cat "$is_clash_api_secret")
out=$(cmd_json_api on 2>/dev/null)
secret_after=$(cat "$is_clash_api_secret")
chk "api on reuses secret" "$secret_after" "$secret_before"
if mode=$(stat -f '%Lp' "$is_clash_api_secret" 2>/dev/null); then
    :
else
    mode=$(stat -c '%a' "$is_clash_api_secret")
fi
chk "api secret mode" "$mode" "600"
[[ $out != *"$secret_after"* ]] && ok "secret value absent from stdout" || bad "secret value absent from stdout: $out"

# --- 6. restart failure cannot report success -------------------------------
manage() { return 1; }
restart_out=$(cmd_json_api off 2>&1); restart_rc=$?
[ $restart_rc -ne 0 ] && [[ $restart_out == *restart_failed* ]] \
    && ok "restart failure cannot report ok" || bad "restart failure cannot report ok: rc=$restart_rc out=$restart_out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ $FAIL -eq 0 ]
