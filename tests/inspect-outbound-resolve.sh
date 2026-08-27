#!/usr/bin/env bash
# The reality flow parks the public key in a second `direct` outbound and reuses
# that tag as a storage slot. `sb --json inspect` used to report it as the
# outbound of the line, which made every reality inbound look like a relay.
# This extracts the jq resolver from src/core.sh (no Linux box needed) and
# asserts it never reports the storage slot, while real relays still resolve.
set -u
CORE="$(cd "$(dirname "$0")/.." && pwd)/src/core.sh"
TMP=$(mktemp -d /tmp/sb-outbound-test.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: got [$2] want [$3]"; fi; }

# Take the resolver straight from the shipped source so the test cannot drift.
awk '/^        def real_outbound_tag:/,/protocol: \(\$ob.type \/\/ "direct"\) \};/' "$CORE" >"$TMP/resolve.jq"
if ! [ -s "$TMP/resolve.jq" ]; then
    echo "FAIL - could not extract resolve_outbound from $CORE"; exit 1
fi
echo 'resolve_outbound($t) | "\(.tag)/\(.protocol)"' >>"$TMP/resolve.jq"

res() { jq -r --arg t "$1" -f "$TMP/resolve.jq" <<<"$2"; }

chk "reality storage slot is not the outbound" \
    "$(res tagA '{"outbounds":[{"type":"direct"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[]}}')" "direct/direct"
chk "route rule naming this inbound wins" \
    "$(res tagA '{"outbounds":[{"type":"direct"},{"tag":"relay-out","type":"vless"}],"route":{"rules":[{"inbound":["tagA"],"outbound":"relay-out"}]}}')" "relay-out/vless"
chk "route.final is the fallback target" \
    "$(res tagA '{"outbounds":[{"tag":"a","type":"direct"},{"tag":"b","type":"vless"}],"route":{"final":"b"}}')" "b/vless"
chk "a lone untagged direct reports direct" \
    "$(res tagA '{"outbounds":[{"type":"direct"}]}')" "direct/direct"
chk "storage slot alongside a real relay does not shadow it" \
    "$(res tagA '{"outbounds":[{"tag":"relay-out","type":"vless"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[{"inbound":["tagA"],"outbound":"relay-out"}]}}')" "relay-out/vless"
chk "no outbounds at all reports direct" \
    "$(res tagA '{}')" "direct/direct"
chk "a rule pointing at the storage slot still never leaks the key" \
    "$(res tagA '{"outbounds":[{"type":"direct"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[{"inbound":["tagA"],"outbound":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4"}]}}')" "direct/direct"
chk "a rule for another inbound does not apply here" \
    "$(res tagA '{"outbounds":[{"type":"direct"},{"tag":"public_key_69bcoKtJXBYDQzqMtjt55HsXzxJg4","type":"direct"}],"route":{"rules":[{"inbound":["other"],"outbound":"relay-out"}]}}')" "direct/direct"

echo "---"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
