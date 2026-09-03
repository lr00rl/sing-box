#!/usr/bin/env bash
# Regression harness for argument quoting through the entry point.
#
# sing-box.sh assigned the caller's arguments to a plain string (args=$@) and
# src/init.sh expanded it unquoted (main $args), so the shell re-split every
# argument on whitespace. Any argument containing a space arrived at the
# dispatcher in pieces. The visible symptom was that a user could never be
# added if a field held a space: `sb --json user add <line> '{"name":"a b"}'`
# reached `jq -e .` truncated at the space and came back
# {"ok":false,"error":"invalid_payload"}, which is what a caller sees when the
# JSON it sent was perfectly valid. The argument list must survive intact.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

# The entry point's two lines, read from the files rather than restated here,
# so the test fails if either regresses to the string form.
grep -q 'args=("$@")' "$ROOT/sing-box.sh" \
  && ok "sing-box.sh keeps the arguments as an array" \
  || bad "sing-box.sh no longer assigns args as an array"
grep -q 'main "${args\[@\]}"' "$ROOT/src/init.sh" \
  && ok "init.sh expands the argument array quoted" \
  || bad "init.sh no longer expands the argument array quoted"
grep -q 'args=\$@' "$ROOT/sing-box.sh" \
  && bad "sing-box.sh still flattens the arguments into a string" \
  || ok "sing-box.sh does not flatten the arguments"

# And the behaviour itself, exercised the way the entry point does it.
# read -a rather than mapfile: bash 3.2 ships on some hosts and has no mapfile.
run_entry() { local args=("$@"); [[ ${#args[@]} -eq 0 ]] && args=(main); printf '%s\n' "${args[@]}"; }

PAYLOAD='{"user_id":"u1","name":"usage verification probe","protocol":"vless"}'
IFS=$'\n' read -r -d '' -a got < <(run_entry --json user add my-line "$PAYLOAD"; printf '\0')
chk "an argument list with a spaced payload keeps its length" "${#got[@]}" "5"
chk "the payload arrives whole"                                "${got[4]}"  "$PAYLOAD"
chk "the line name is still its own argument"                  "${got[3]}"  "my-line"

IFS=$'\n' read -r -d '' -a empty < <(run_entry; printf '\0')
chk "no arguments still means the main menu" "${empty[0]}" "main"

SPACED_LINE='my line with spaces'
IFS=$'\n' read -r -d '' -a got2 < <(run_entry inspect "$SPACED_LINE"; printf '\0')
chk "a spaced line name survives too" "${got2[1]}" "$SPACED_LINE"

echo "--- $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
