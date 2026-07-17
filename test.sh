#!/usr/bin/env bash
# test.sh — end-to-end regression suite for hart. Boots a throwaway daemon on a
# temp DB and exercises the whole surface (publish/version/rollback, visibility +
# gated read, template+data, stats, fresh/stale, admin owners/list/mv, the CSP
# linter, MCP, the served endpoints, and the operator dashboard). Exits non-zero
# on any failure. Needs ./hart (run ./build.sh first) + curl + python3.
set -uo pipefail
cd "$(dirname "$0")"
[ -x ./hart ] || { echo "test: ./hart not found — run ./build.sh first" >&2; exit 1; }

PORT="${HART_TEST_PORT:-8760}"
TMP="$(mktemp -d)"
export HART_DB="$TMP/test.db"
export HART_URL="http://127.0.0.1:$PORT"
export HART_ADMIN_TOKEN="test-admin-$$"
export HART_PUBLIC=""
export HART_MAX_SUBMITS_PER_MIN=100000   # the suite does many writes fast — don't rate-limit tests
ADMH="authorization: Bearer $HART_ADMIN_TOKEN"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2' want '$3')"; fi; }
has()  { case "$2" in *"$3"*) ok "$1";; *) bad "$1 (missing '$3')";; esac; }
jget() { python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get(sys.argv[1],""))' "$1"; }

# boot the daemon
./hart serve "$PORT" >"$TMP/serve.log" 2>&1 &
SRV=$!
cleanup() { kill "$SRV" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT
sleep 1
kill -0 "$SRV" 2>/dev/null || { echo "test: daemon failed to boot"; cat "$TMP/serve.log"; exit 1; }

echo "hart test suite (daemon pid $SRV, db $HART_DB)"
P="$TMP/p.html"; printf '<h1>{{t}}</h1><p>hello</p>' > "$P"

echo "== publish + versioning =="
R=$(./hart publish "$P" --owner acme --artifact page --title Q3)
eq "publish returns version 1" "$(echo "$R" | jget version)" "1"
eq "publish ok" "$(echo "$R" | jget ok)" "True"
R2=$(./hart publish "$P" --owner acme --artifact page)
eq "re-publish appends version 2" "$(echo "$R2" | jget version)" "2"
eq "GET /a latest serves 200" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/acme/page")" "200"
eq "pinned /v1 still serves" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/acme/page/v1")" "200"
has "rollback re-points latest (ok)" "$(./hart rollback acme/page 1)" '"ok":true'

echo "== template + data =="
D=$(./hart data acme/page '{"t":"LIVE"}')
eq "data ok" "$(echo "$D" | jget ok)" "True"
has "page re-renders with data" "$(curl -s "$HART_URL/a/acme/page")" "window.HART_DATA"

echo "== CSP linter =="
BAD="$TMP/bad.html"; printf '<script src="https://evil.example/x.js"></script>' > "$BAD"
eq "external ref rejected (422)" "$(./hart publish "$BAD" --owner acme --artifact bad >/dev/null 2>&1; echo $?)" "80"
eq "--force overrides linter" "$(./hart publish "$BAD" --owner acme --artifact bad --force | jget version)" "1"

echo "== visibility + gated read =="
./hart publish "$P" --owner acme --artifact secret --visibility private --read-key pw >/dev/null
eq "private: no key -> 401 unlock" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/acme/secret")" "401"
eq "private: correct key -> 200" "$(curl -s -o /dev/null -w '%{http_code}' -H 'x-hart-read-key: pw' "$HART_URL/a/acme/secret")" "200"
./hart publish "$P" --owner acme --artifact pub --visibility public >/dev/null
has "public artifact listed in explore" "$(./hart explore)" "acme/pub"

echo "== owner-claim keys =="
./hart publish "$P" --owner locked --artifact a --owner-key sekret >/dev/null
eq "claimed owner: wrong/no key -> 403" "$(printf '<h1>x</h1>' > "$TMP/x.html"; ./hart publish "$TMP/x.html" --owner locked --artifact b >/dev/null 2>&1; echo $?)" "80"
eq "claimed owner: right key -> ok" "$(./hart publish "$TMP/x.html" --owner locked --artifact b --owner-key sekret | jget ok)" "True"

echo "== stats (server-side views) =="
curl -s -o /dev/null "$HART_URL/a/acme/pub"
curl -s -o /dev/null -H 'Referer: https://news.ycombinator.com/x' "$HART_URL/a/acme/pub"
S=$(./hart stats acme/pub)
eq "views counted (2)" "$(echo "$S" | jget views)" "2"
has "referrer bucketed" "$S" "news.ycombinator.com"

echo "== fresh + stale =="
./hart publish "$P" --owner ops --artifact board --fresh 1s >/dev/null
sleep 2
has "stale (SLA mode) flags the board" "$(./hart stale --owner ops)" "ops/board"
eq "stale count via older-than" "$(./hart stale --owner ops --older-than 1s | jget count | grep -qE '^[1-9]' && echo yes || echo no)" "yes"
./hart fresh ops/board off >/dev/null
eq "fresh off clears SLA" "$(./hart stale --owner ops | jget count)" "0"

echo "== admin API =="
eq "admin owners: no token -> 403" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/admin/owners")" "403"
has "admin owners: with token -> data" "$(curl -s -H "$ADMH" "$HART_URL/v1/admin/owners")" '"owners"'
has "admin list carries views+stale" "$(curl -s -H "$ADMH" "$HART_URL/v1/admin/list")" '"stale"'
MV=$(curl -s -H "$ADMH" -X POST "$HART_URL/v1/admin/mv?from=acme/pub&to=moved/pub")
eq "admin mv ok" "$(echo "$MV" | jget ok)" "True"
eq "moved: old id 404" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/acme/pub")" "404"
eq "moved: new id 200" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/moved/pub")" "200"

echo "== MCP server =="
MCP=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"hart_list","arguments":{"owner":"acme"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp initialize -> serverInfo" "$MCP" '"serverInfo"'
has "mcp tools/list -> hart_publish" "$MCP" 'hart_publish'
has "mcp tools/call hart_list works" "$MCP" 'acme/page'

echo "== served endpoints =="
for ep in _health guide.md skill.md llms.txt install.sh _status; do
  eq "GET /$ep -> 200" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/$ep")" "200"
done

echo "== operator dashboard =="
eq "/_fleet unauth -> 401" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/_fleet")" "401"
curl -s -o /dev/null -c "$TMP/cj" -X POST -d "token=$HART_ADMIN_TOKEN" "$HART_URL/_fleet/login"
eq "/_fleet with cookie -> 200" "$(curl -s -o /dev/null -w '%{http_code}' -b "$TMP/cj" "$HART_URL/_fleet")" "200"
has "/_fleet shows private artifact (operator view)" "$(curl -s -b "$TMP/cj" "$HART_URL/_fleet")" "acme/secret"
has "/_fleet is anti-clickjacking (X-Frame-Options DENY)" "$(curl -s -D - -o /dev/null -b "$TMP/cj" "$HART_URL/_fleet")" "X-Frame-Options: DENY"
has "admin cookie is SameSite=Strict" "$(curl -s -D - -o /dev/null -X POST -d "token=$HART_ADMIN_TOKEN" "$HART_URL/_fleet/login")" "SameSite=Strict"

echo
echo "== $((PASS+FAIL)) checks: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
