#!/usr/bin/env bash
# Regression harness for `get file`.
#
# The lookup treats its argument as a regex matched as a substring, so a caller
# that passes a real filename (sb --json list passes each name it enumerated)
# also matched a sibling <name>.json.backup-<ts>. Two matches made the lookup
# ambiguous, the non-interactive caller got a prompt it could not answer, and
# the line vanished from the inventory. An exact filename must win outright.
set -u
# is_config_file / is_dont_auto_exit are set by callers in the real script.
is_config_file=""; is_dont_auto_exit=""; is_all_json=(); ASKED=0
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-getfile-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

extract_fn() { awk "/^$1\\(\\) \\{/,/^\\}/" "$CORE"; }

# --- stubs -----------------------------------------------------------------
is_conf_dir="$TMP/conf"; mkdir -p "$is_conf_dir"
err()  { echo "ERR:$*"; exit 9; }
ask()  { ASKED=1; }            # records that the interactive path was reached
get_ip() { :; }
detect_ip() { :; }
eval "$(extract_fn get)"

reset() { is_config_file=""; is_auto_get_config=""; is_all_json=(); ASKED=0; }

# --- 1. exact filename wins even with a same-prefix backup alongside --------
printf '{}' >"$is_conf_dir/VLESS-REALITY-57289.json"
printf '{}' >"$is_conf_dir/VLESS-REALITY-57289.json.backup-20260704-114329"
reset; get file "VLESS-REALITY-57289.json"
chk "exact name resolves" "${is_config_file:-}" "VLESS-REALITY-57289.json"
chk "exact name does not prompt" "$ASKED" "0"
chk "exact name marks auto-resolved" "${is_auto_get_config:-}" "1"

# --- 2. the default anchored pattern still lists only real configs ----------
reset; get file
chk "default pattern skips the backup" "${is_config_file:-}" "VLESS-REALITY-57289.json"
chk "default pattern does not prompt" "$ASKED" "0"

# --- 3. a genuinely ambiguous pattern must still ask ------------------------
printf '{}' >"$is_conf_dir/VLESS-REALITY-57290.json"
reset; get file "VLESS-REALITY-.*\.json$"
chk "two real configs still prompt" "$ASKED" "1"

# --- 4. a name that matches nothing still errors ----------------------------
reset; out=$( get file "no-such-line" 2>&1 ); rc=$?
chk "missing name exits nonzero" "$rc" "9"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
