#!/usr/bin/env bash
# Self-confirmation (ADR 0006): the same Kennung confirms its own bin when it
# is back there at least 20 h after adding it. Needs a local dev server
# started with the wait time set to 0:
#   npx wrangler dev --local --var TEST_IP_HEADER:X-Test-IP --var SELF_CONFIRM_S:0
#   server/test/self_confirm_test.sh [base URL]
set -u
export LC_ALL=C
API="${1:-http://localhost:8787}/api/v1"
PASS=0; FAIL=0
check() { if [ "$2" == "$3" ]; then PASS=$((PASS+1)); echo "  ok   $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1: want $2, got $3"; fi; }
post() { curl -s -X POST -H 'Content-Type: application/json' -H "X-Test-IP: $2" --data-binary "{\"u\":\"$1\",\"e\":$3}" "$API/c"; }
U=$(openssl rand -hex 16); IP="10.9.$((RANDOM % 256)).$((RANDOM % 256))"
LA=$(awk -v r=$RANDOM 'BEGIN { printf "%.5f", 30 + r / 1000 }'); LO=$(awk -v r=$RANDOM 'BEGIN { printf "%.5f", -40 + r / 1000 }')
A_G="[{\"t\":\"a\",\"k\":\"g\",\"la\":$LA,\"lo\":$LO,\"i\":0}]"
A_G_IMP="[{\"t\":\"a\",\"k\":\"g\",\"la\":$LA,\"lo\":$LO,\"i\":1}]"
A_D="[{\"t\":\"a\",\"k\":\"d\",\"la\":$LA,\"lo\":$LO,\"i\":0}]"
S=$(post "$U" "$IP" "$A_G" | jq -r '.r[0].s')
R=$(post "$U" "$IP" "$A_G_IMP" | jq -r '.r[0].f'); check "imprecise re-add does not confirm" "0" "$R"
R=$(post "$U" "$IP" "$A_G" | jq -c '.r[0]'); check "precise re-add later confirms" "{\"s\":$S,\"f\":1}" "$R"
S2=$(post "$U" "$IP" "$A_D" | jq -r '.r[0].s')
F="[{\"t\":\"f\",\"s\":$S2}]"
R=$(post "$U" "$IP" "$F" | jq -c '.r[0]'); check "f on own bin later confirms" '{"ok":1,"f":1}' "$R"
echo "passed $PASS, failed $FAIL"; [ "$FAIL" -eq 0 ]
