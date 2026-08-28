#!/usr/bin/env bash
# `sb --json inspect` reports which outbound a line actually uses. Two traps:
#
#   1. A reality inbound stores its public key by parking it in a second
#      `direct` outbound and reusing that tag as the storage slot. Reporting it
#      makes every reality line look like a relay.
#   2. The route rule that steers an inbound to a relay often lives in a
#      different config file than the inbound itself. Reading one file makes a
#      real relay look terminal, which is the more dangerous of the two: it
#      reads as a confident "direct" rather than as an obvious oddity.
#
# The resolver is extracted from src/core.sh so these assertions cannot drift
# from the shipped implementation.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-outbound-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

awk '/^        def real_outbound_tag:/,/^              end;$/' "$CORE" >"$TMP/resolve.jq"
if ! [ -s "$TMP/resolve.jq" ]; then
    echo "FAIL - could not extract resolve_outbound from $CORE"; exit 1
fi
echo 'resolve_outbound($t) | "\(.tag)/\(.protocol)"' >>"$TMP/resolve.jq"

NOMAP='{"routes":{},"types":{}}'
# res <inbound tag> <maps json> <config json>
res() { jq -r --arg t "$1" --argjson maps "$2" -f "$TMP/resolve.jq" <<<"$3"; }

PUBKEY='{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}'
REALITY_CONF="{\"outbounds\":[{\"type\":\"direct\"},$PUBKEY],\"route\":{\"rules\":[]}}"

# --- the public-key storage slot -------------------------------------------
chk "reality storage slot is not the outbound" \
    "$(res tagA "$NOMAP" "$REALITY_CONF")" "direct/direct"
chk "a lone untagged direct reports direct" \
    "$(res tagA "$NOMAP" '{"outbounds":[{"type":"direct"}]}')" "direct/direct"
chk "no outbounds at all reports direct" \
    "$(res tagA "$NOMAP" '{}')" "direct/direct"
SELF_ROUTED_TO_SLOT='{"outbounds":[{"type":"direct"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[{"inbound":["tagA"],"outbound":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4"}]}}'
chk "a same-file rule pointing at the storage slot never leaks the key" \
    "$(res tagA "$NOMAP" "$SELF_ROUTED_TO_SLOT")" "direct/direct"
chk "a cross-file rule pointing at the storage slot never leaks the key" \
    "$(res tagA '{"routes":{"tagA":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4"},"types":{}}' "$REALITY_CONF")" \
    "direct/direct"

# --- same-file routing (unchanged behaviour) -------------------------------
chk "same-file rule naming this inbound wins" \
    "$(res tagA "$NOMAP" '{"outbounds":[{"type":"direct"},{"tag":"relay-out","type":"vless"}],"route":{"rules":[{"inbound":["tagA"],"outbound":"relay-out"}]}}')" \
    "relay-out/vless"
chk "route.final is the fallback target" \
    "$(res tagA "$NOMAP" '{"outbounds":[{"tag":"a","type":"direct"},{"tag":"b","type":"vless"}],"route":{"final":"b"}}')" \
    "b/vless"
OTHER_RULE='{"outbounds":[{"type":"direct"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[{"inbound":["other"],"outbound":"relay-out"}]}}'
chk "a rule for another inbound does not apply here" \
    "$(res tagA "$NOMAP" "$OTHER_RULE")" "direct/direct"

# --- cross-file routing (the case a single file cannot see) ----------------
CROSS='{"routes":{"tagA":"[openjobs]-vircs-us-ca-home-vless"},"types":{"[openjobs]-vircs-us-ca-home-vless":"vless"}}'
chk "cross-file rule beats the terminal look of the inbound file" \
    "$(res tagA "$CROSS" "$REALITY_CONF")" "[openjobs]-vircs-us-ca-home-vless/vless"
chk "cross-file rule beats a same-file route.final" \
    "$(res tagA "$CROSS" '{"outbounds":[{"tag":"a","type":"direct"}],"route":{"final":"a"}}')" \
    "[openjobs]-vircs-us-ca-home-vless/vless"
chk "an outbound of unknown type is named, with the protocol left empty rather than guessed" \
    "$(res tagA '{"routes":{"tagA":"relay-out"},"types":{}}' "$REALITY_CONF")" "relay-out/"
chk "a locally defined outbound keeps its own type over the map" \
    "$(res tagA '{"routes":{"tagA":"relay-out"},"types":{"relay-out":"trojan"}}' '{"outbounds":[{"tag":"relay-out","type":"vless"}]}')" \
    "relay-out/vless"
chk "the map does not affect an inbound it has no entry for" \
    "$(res tagB "$CROSS" "$REALITY_CONF")" "direct/direct"

echo "---"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
