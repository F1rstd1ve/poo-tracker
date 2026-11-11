#!/usr/bin/env bash
# API test for the Gassi-Server, Etappe B (docs/spec-server.md).
#
#   server/test/api_test.sh [base URL]      default http://localhost:8787
#
# Meant for a local dev server with a fresh or reused local D1:
#   cd server
#   npx wrangler d1 migrations apply poo-tracker --local
#   npx wrangler dev --local --var TEST_IP_HEADER:X-Test-IP
#
# TEST_IP_HEADER lets every test group use its own client IP for the per-IP
# limits. Without it (e.g. against production) all requests share one IP and
# the IP limit of 30 adds per day breaks most checks - and the test would
# write junk into the live database. Do not run it against production.
#
# Every run uses random uids and a random area, so it can be repeated against
# the same local database. Needs curl, jq, awk, openssl.
set -u
BASE="${1:-http://localhost:8787}"
API="$BASE/api/v1"
PASS=0
FAIL=0
FAILED=()

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"; }
check() { # name expected actual
  if [ "$2" == "$3" ]; then ok "$1"; else fail "$1" "$2" "$3"; fi
}
check_ne() { # name not-expected actual
  if [ "$2" != "$3" ]; then ok "$1"; else fail "$1" "!= $2" "$3"; fi
}
check_has() { # name needle haystack
  case "$3" in *"$2"*) ok "$1" ;; *) fail "$1" "contains $2" "$3" ;; esac
}
check_hasnt() {
  case "$3" in *"$2"*) fail "$1" "does not contain $2" "$3" ;; *) ok "$1" ;; esac
}

new_uid() { openssl rand -hex 16; }
new_ip()  { echo "10.$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"; }

# post <uid> <ip> <events JSON array>  -> sets CODE and BODY
post_raw() { # <ip> <raw body>
  local out
  out=$(curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -H "X-Test-IP: $1" \
    --data-binary "$2" "$API/c")
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
}
post() { post_raw "$2" "{\"u\":\"$1\",\"e\":$3}"; }
res() { echo "$BODY" | jq -c ".r[$1]"; }     # result of event n
sid() { echo "$BODY" | jq -r ".r[$1].s"; }   # server id of add result n

# get_layer <root>  -> sets CODE, BODY, HEADERS, LB (b string), LH (h string)
get_layer() {
  local hdr
  hdr=$(mktemp)
  local out
  out=$(curl -s -D "$hdr" -w '\n%{http_code}' "$API/s/$1")
  CODE="${out##*$'\n'}"
  BODY="${out%$'\n'*}"
  HEADERS=$(tr -d '\r' < "$hdr")
  rm -f "$hdr"
  LB=$(echo "$BODY" | jq -r '.b' 2>/dev/null)
  LH=$(echo "$BODY" | jq -r '.h' 2>/dev/null)
}

# off <lat> <lon> <metres north> <metres east>  -> "lat lon"
off() {
  awk -v la="$1" -v lo="$2" -v n="$3" -v e="$4" 'BEGIN {
    m = 6371008.8 * 3.141592653589793 / 180;
    printf "%.7f %.7f", la + n / m, lo + e / (m * cos(la * 3.141592653589793 / 180)) }'
}
root_of() { awk -v la="$1" -v lo="$2" 'BEGIN {
  ri = int((la + 90) / 0.4); rj = int((lo + 180) / 0.4); printf "%d_%d", ri, rj }'; }
ev_add() { printf '{"t":"a","k":"%s","la":%s,"lo":%s,"i":%s}' "$1" "$2" "$3" "${4:-0}"; }
# entry "id,k,f,..." of shared bin <id> in the current layer (or empty)
entry() { echo "$LB" | tr ';' '\n' | grep "^$1," || true; }

# Random area in Austria for this run, groups 300 m apart.
LAT0=$(awk -v r=$RANDOM 'BEGIN { printf "%.5f", 47.2 + r / 32768 * 0.8 }')
LON0=$(awk -v r=$RANDOM 'BEGIN { printf "%.5f", 13.0 + r / 32768 * 3.0 }')
spot() { off "$LAT0" "$LON0" $(($1 * 300)) 0; }

echo "Gassi-Server API test against $BASE (area $LAT0 $LON0)"

# ----------------------------------------------------------------- add, dup
echo "add / duplicate / confirm / imprecise"
read -r P1LA P1LO <<<"$(spot 1)"
U1=$(new_uid); U2=$(new_uid); U3=$(new_uid); IP=$(new_ip)
post "$U1" "$IP" "[$(ev_add g "$P1LA" "$P1LO")]"
check "add -> 200" 200 "$CODE"
S1=$(sid 0)
check "add -> new unconfirmed" '0' "$(echo "$BODY" | jq -r '.r[0].f')"
check_ne "add -> server id" null "$S1"

read -r la lo <<<"$(off "$P1LA" "$P1LO" 0 3)"
post "$U1" "$IP" "[$(ev_add g "$la" "$lo")]"
check "same uid 3 m away -> existing entry" "{\"s\":$S1,\"f\":0}" "$(res 0)"

read -r la lo <<<"$(off "$P1LA" "$P1LO" 0 2)"
post "$U2" "$IP" "[$(ev_add g "$la" "$lo" 1)]"
S2=$(sid 0)
check_ne "imprecise by other uid -> own entry" "$S1" "$S2"
check "imprecise -> unconfirmed" 0 "$(echo "$BODY" | jq -r '.r[0].f')"

read -r la lo <<<"$(off "$P1LA" "$P1LO" 0 -4)"
post "$U3" "$IP" "[$(ev_add g "$la" "$lo")]"
check "precise by other uid 4 m away -> confirms" "{\"s\":$S1,\"f\":1}" "$(res 0)"

post "$U1" "$IP" "[$(ev_add g "$P1LA" "$P1LO")]"
check "owner adds again -> confirmed existing" "{\"s\":$S1,\"f\":1}" "$(res 0)"

get_layer "$(root_of "$P1LA" "$P1LO")"
check "layer: confirmed bin" "1" "$(entry "$S1" | cut -d, -f3)"
check "layer: imprecise bin unconfirmed" "0" "$(entry "$S2" | cut -d, -f3)"

# ------------------------------------------------- kind and distance rules
echo "different kind / distance"
U4=$(new_uid)
read -r la lo <<<"$(off "$P1LA" "$P1LO" 5 0)"
post "$U4" "$IP" "[$(ev_add d "$la" "$lo")]"
S4=$(sid 0)
check_ne "dog bin 5 m away -> separate" "$S1" "$S4"
check "dog bin 5 m away -> unconfirmed" 0 "$(echo "$BODY" | jq -r '.r[0].f')"

read -r QLA QLO <<<"$(spot 2)"
U6=$(new_uid); U7=$(new_uid); U8=$(new_uid)
post "$U6" "$IP" "[$(ev_add g "$QLA" "$QLO")]"
T1=$(sid 0)
read -r la lo <<<"$(off "$QLA" "$QLO" 0 9)"
post "$U7" "$IP" "[$(ev_add g "$la" "$lo")]"
T2=$(sid 0)
check_ne "9 m away -> separate" "$T1" "$T2"
check "9 m away -> unconfirmed" 0 "$(echo "$BODY" | jq -r '.r[0].f')"
read -r la lo <<<"$(off "$QLA" "$QLO" 0 -7.5)"
post "$U8" "$IP" "[$(ev_add g "$la" "$lo")]"
check "7.5 m away -> confirms" "{\"s\":$T1,\"f\":1}" "$(res 0)"

# ----------------------------------------------------------------- reports
echo "reports"
read -r RLA RLO <<<"$(spot 3)"
RROOT=$(root_of "$RLA" "$RLO")
U9=$(new_uid); U10=$(new_uid); U11=$(new_uid)
post "$U9" "$IP" "[$(ev_add g "$RLA" "$RLO")]"
B=$(sid 0)
post "$U10" "$IP" "[{\"t\":\"r\",\"k\":\"g\",\"la\":$RLA,\"lo\":$RLO,\"s\":$B}]"
check "report 1 -> ok" '{"ok":1}' "$(res 0)"
post "$U10" "$IP" "[{\"t\":\"r\",\"s\":$B}]"
check "report 1 again by same uid -> ok" '{"ok":1}' "$(res 0)"
get_layer "$RROOT"
check_ne "shared bin still visible after one uid" "" "$(entry "$B")"
post "$U11" "$IP" "[{\"t\":\"r\",\"k\":\"g\",\"la\":$RLA,\"lo\":$RLO,\"s\":$B}]"
check "report 2 -> ok" '{"ok":1}' "$(res 0)"
get_layer "$RROOT"
check "shared bin hidden after 2 uids" "" "$(entry "$B")"

# OSM bin, recognised by kind + coordinate on 1e-5 degrees.
read -r OLA OLO <<<"$(off "$RLA" "$RLO" 50 0)"
OLA=$(printf '%.5f' "$OLA"); OLO=$(printf '%.5f' "$OLO")
OH=$(awk -v la="$OLA" -v lo="$OLO" 'BEGIN {
  ri = int((la + 90) / 0.4); rj = int((lo + 180) / 0.4);
  printf "2,%d,%d;", sprintf("%.0f", la * 1e5) - (ri * 40000 - 9000000), sprintf("%.0f", lo * 1e5) - (rj * 40000 - 18000000) }')
post "$U10" "$IP" "[{\"t\":\"r\",\"k\":\"d\",\"la\":$OLA,\"lo\":$OLO,\"s\":0}]"
check "OSM report 1 -> ok" '{"ok":1}' "$(res 0)"
get_layer "$RROOT"
check_hasnt "OSM bin not hidden after one uid" "$OH" "$LH"
post "$U11" "$IP" "[{\"t\":\"r\",\"k\":\"d\",\"la\":$OLA,\"lo\":$OLO,\"s\":0}]"
check "OSM report 2 -> ok" '{"ok":1}' "$(res 0)"
get_layer "$RROOT"
check_has "OSM bin hidden after 2 uids" "$OH" "$LH"
post "$U9" "$IP" "[{\"t\":\"r\",\"k\":\"g\",\"la\":$OLA,\"lo\":$OLO,\"s\":0}]"
get_layer "$RROOT"
check_hasnt "OSM report of the other kind is separate" "${OH/#2,/1,}" "$LH"

# ----------------------------------------------------- delete and confirm
echo "delete own (x) / confirm by disposal (f)"
read -r XLA XLO <<<"$(spot 4)"
XROOT=$(root_of "$XLA" "$XLO")
U12=$(new_uid); U13=$(new_uid); U14=$(new_uid)
post "$U12" "$IP" "[$(ev_add g "$XLA" "$XLO")]"
XB=$(sid 0)
post "$U13" "$IP" "[{\"t\":\"x\",\"s\":$XB}]"
check "x on bin of another uid -> bad" '{"err":"bad"}' "$(res 0)"
post "$U12" "$IP" "[{\"t\":\"x\",\"s\":$XB}]"
check "x on own unconfirmed -> ok" '{"ok":1}' "$(res 0)"
get_layer "$XROOT"
check "x removed the bin" "" "$(entry "$XB")"

read -r la lo <<<"$(off "$XLA" "$XLO" 30 0)"
post "$U12" "$IP" "[$(ev_add d "$la" "$lo")]"
YB=$(sid 0)
post "$U12" "$IP" "[{\"t\":\"f\",\"s\":$YB}]"
check "f on own bin within 20 h -> ok, not confirmed" '{"ok":1,"f":0}' "$(res 0)"
get_layer "$XROOT"
check "f on own bin within 20 h does not confirm" "0" "$(entry "$YB" | cut -d, -f3)"
read -r la2 lo2 <<<"$(off "$XLA" "$XLO" 32 0)"
post "$U12" "$IP" "[$(ev_add d "$la2" "$lo2")]"
check "same uid re-add within 20 h -> existing, not confirmed" "{\"s\":$YB,\"f\":0}" "$(res 0)"
post "$U14" "$IP" "[{\"t\":\"f\",\"s\":$YB}]"
check "f by other uid -> ok, confirmed" '{"ok":1,"f":1}' "$(res 0)"
get_layer "$XROOT"
check "f by other uid confirms" "$YB,2,1" "$(entry "$YB" | cut -d, -f1-3)"
post "$U12" "$IP" "[{\"t\":\"x\",\"s\":$YB}]"
check "x on own confirmed -> bad" '{"err":"bad"}' "$(res 0)"
get_layer "$XROOT"
check_ne "confirmed bin kept" "" "$(entry "$YB")"
post "$U14" "$IP" '[{"t":"f","s":999999999}]'
check "f on unknown bin -> bad" '{"err":"bad"}' "$(res 0)"

# ------------------------------------------------------------------ limits
echo "limits"
batch10() { # <lat> <lon> <start>  -> 10 adds 20 m apart
  local i out="[" la lo
  for i in $(seq 0 9); do
    read -r la lo <<<"$(off "$1" "$2" 0 $((($3 + i) * 20)))"
    [ "$i" -gt 0 ] && out+=","
    out+=$(ev_add g "$la" "$lo")
  done
  echo "$out]"
}
read -r LLA LLO <<<"$(spot 5)"
U15=$(new_uid); IP15=$(new_ip)
for k in 0 1 2; do
  post "$U15" "$IP15" "$(batch10 "$LLA" "$LLO" $((k * 10)))"
  check "uid adds $((k * 10 + 1))-$((k * 10 + 10)) accepted" 10 "$(echo "$BODY" | jq '[.r[] | select(.f == 0)] | length')"
done
read -r la lo <<<"$(off "$LLA" "$LLO" 0 700)"
post "$U15" "$IP15" "[$(ev_add g "$la" "$lo")]"
check "31st add by uid -> limit" '{"err":"limit"}' "$(res 0)"
post "$U15" "$IP15" '[{"t":"x","s":999999999}]'
check "other events have their own counter" '{"ok":1}' "$(res 0)"

read -r LLA LLO <<<"$(spot 6)"
IPL=$(new_ip)
for k in 0 1 2; do
  post "$(new_uid)" "$IPL" "$(batch10 "$LLA" "$LLO" $((k * 10)))"
  check "IP adds $((k * 10 + 1))-$((k * 10 + 10)) accepted" 10 "$(echo "$BODY" | jq '[.r[] | select(.f == 0)] | length')"
done
U19=$(new_uid)
read -r la lo <<<"$(off "$LLA" "$LLO" 0 700)"
post "$U19" "$IPL" "[$(ev_add g "$la" "$lo")]"
check "31st add from the same IP (new uid) -> limit" '{"err":"limit"}' "$(res 0)"
post "$U19" "$(new_ip)" "[$(ev_add g "$la" "$lo")]"
check "same uid from another IP -> accepted" 0 "$(echo "$BODY" | jq -r '.r[0].f')"

U20=$(new_uid); IP20=$(new_ip)
X10='[{"t":"x","s":999999991},{"t":"x","s":999999992},{"t":"x","s":999999993},{"t":"x","s":999999994},{"t":"x","s":999999995},{"t":"x","s":999999996},{"t":"x","s":999999997},{"t":"x","s":999999998},{"t":"x","s":999999999},{"t":"x","s":999999990}]'
for k in 1 2 3; do post "$U20" "$IP20" "$X10"; done
check "30 other events accepted" 10 "$(echo "$BODY" | jq '[.r[] | select(.ok == 1)] | length')"
post "$U20" "$IP20" '[{"t":"r","k":"g","la":47.5,"lo":13.5,"s":0}]'
check "31st other event -> limit" '{"err":"limit"}' "$(res 0)"
read -r la lo <<<"$(spot 7)"
post "$U20" "$IP20" "[$(ev_add g "$la" "$lo")]"
check "adds still allowed after other limit" 0 "$(echo "$BODY" | jq -r '.r[0].f')"

# ------------------------------------------------------------ 50 km rule
echo "50 km rule"
read -r FLA FLO <<<"$(spot 8)"
U21=$(new_uid)
post "$U21" "$IP" "[$(ev_add g "$FLA" "$FLO")]"
read -r la45 lo45 <<<"$(off "$FLA" "$FLO" 45000 0)"
read -r la55 lo55 <<<"$(off "$FLA" "$FLO" 55000 0)"
post "$U21" "$IP" "[$(ev_add g "$la45" "$lo45")]"
check "add 45 km from first add -> accepted" 0 "$(echo "$BODY" | jq -r '.r[0].f')"
post "$U21" "$IP" "[$(ev_add g "$la55" "$lo55"),$(ev_add d "$FLA" "$FLO")]"
check "add 55 km from first add -> far" '{"err":"far"}' "$(res 0)"
check "next event in the batch still processed" 0 "$(echo "$BODY" | jq -r '.r[1].f')"
U21b=$(new_uid)
post "$U21b" "$IP" "[$(ev_add g "$FLA" "$FLO"),$(ev_add g "$la55" "$lo55")]"
check "50 km rule inside one batch -> far" '{"err":"far"}' "$(res 1)"

# --------------------------------------------------------- invalid requests
echo "invalid requests"
U=$(new_uid)
post_raw "$IP" 'not json'
check "no JSON -> 400" 400 "$CODE"
post_raw "$IP" '{"u":"0123456789abcdef0123456789abcde","e":[]}'
check "uid 31 chars -> 400" 400 "$CODE"
post_raw "$IP" '{"u":"0123456789abcdef0123456789abcdeg","e":[]}'
check "uid not hex -> 400" 400 "$CODE"
post_raw "$IP" "{\"u\":\"$U\"}"
check "events missing -> 400" 400 "$CODE"
post_raw "$IP" "{\"u\":\"$U\",\"e\":[{},{},{},{},{},{},{},{},{},{},{}]}"
check "11 events -> 400" 400 "$CODE"
post_raw "$IP" "[1,2]"
check "array body -> 400" 400 "$CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$API/c")
check "GET on /c -> 405" 405 "$CODE"
post "$U" "$IP" '[]'
check "empty batch -> 200 empty result" '200 {"r":[]}' "$CODE $BODY"
post "$U" "$IP" '[{"t":"z"},{"t":"a","k":"q","la":47,"lo":13},{"t":"a","k":"g","la":91,"lo":13},{"t":"a","k":"g","la":"47","lo":13},{"t":"x"},{"t":"f","s":-1},{"t":"r","s":0,"k":"g"},"a",null,{"t":"r","s":"5"}]'
check "per-event errors -> bad" 10 "$(echo "$BODY" | jq '[.r[] | select(.err == "bad")] | length')"

# ------------------------------------------------- layer content/encoding
echo "layer encoding"
# Random root far away from all other tests (Patagonia / Southern Ocean).
RI=$((110 + RANDOM % 10)); RJ=$((100 + RANDOM % 300))
GLA0=$(awk -v r="$RI" 'BEGIN { printf "%.5f", r * 0.4 - 90 }')
GLO0=$(awk -v r="$RJ" 'BEGIN { printf "%.5f", r * 0.4 - 180 }')
pt() { awk -v a="$1" -v d="$2" 'BEGIN { printf "%.5f", a + d / 1e5 }'; }
U22=$(new_uid); U23=$(new_uid); U24=$(new_uid)
post "$U22" "$IP" "[$(ev_add g "$(pt "$GLA0" 12345)" "$(pt "$GLO0" 23456)"),$(ev_add d "$(pt "$GLA0" 100)" "$(pt "$GLO0" 39999)" 1)]"
G1=$(sid 0); G2=$(sid 1)
get_layer "${RI}_${RJ}"
check "layer -> 200" 200 "$CODE"
check "layer exact b" "$G1,1,0,12345,23456;$G2,2,0,100,39999;" "$LB"
check "layer exact h (empty)" "" "$LH"
check_has "layer Cache-Control" "cache-control: public, max-age=3600" "$(echo "$HEADERS" | tr 'A-Z' 'a-z')"
check_has "layer Content-Type" "content-type: application/json" "$(echo "$HEADERS" | tr 'A-Z' 'a-z')"
post "$U23" "$IP" "[$(ev_add g "$(pt "$GLA0" 12345)" "$(pt "$GLO0" 23456)"),{\"t\":\"r\",\"k\":\"d\",\"la\":$(pt "$GLA0" 5),\"lo\":$(pt "$GLO0" 7),\"s\":0}]"
post "$U24" "$IP" "[{\"t\":\"r\",\"k\":\"d\",\"la\":$(pt "$GLA0" 5),\"lo\":$(pt "$GLO0" 7),\"s\":0}]"
get_layer "${RI}_${RJ}"
check "layer after confirm (cache refreshed)" "$G1,1,1,12345,23456;$G2,2,0,100,39999;" "$LB"
check "layer exact h" "2,5,7;" "$LH"
check "layer body is exactly {b,h}" '["b","h"]' "$(echo "$BODY" | jq -c 'keys')"
get_layer "0_0"
check "empty root -> 200 empty" '200 {"b":"","h":""}' "$CODE $BODY"
get_layer "450_0"
check "root out of range -> 400" 400 "$CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$API/s/abc")
check "malformed layer path -> 404" 404 "$CODE"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")
check "static pages still served" 200 "$CODE"

echo
echo "passed: $PASS, failed: $FAIL"
for f in "${FAILED[@]+"${FAILED[@]}"}"; do echo "  failed: $f"; done
[ "$FAIL" -eq 0 ]
