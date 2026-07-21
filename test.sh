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
has "admin digest: new artifacts + totals" "$(curl -s -H "$ADMH" "$HART_URL/v1/admin/digest?days=7")" '"new_artifacts"'
echo "== feedback =="
has "feedback CLI dual-write (relay off -> stored locally)" "$(FEEDBACK_RELAY=off ./hart feedback 'a bug from the suite' --kind bug --context test.sh)" '"stored":true'
has "feedback CLI reports relayed=false when relay off" "$(FEEDBACK_RELAY=off ./hart feedback 'idea' --kind idea)" '"relayed":false'
eq  "feedback: empty message -> 400" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/feedback" -d '{"message":""}')" "400"
eq  "admin digest: no token -> 403" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/admin/digest")" "403"
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
MCP_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"hart_get","arguments":{"id":"bad$/x"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_get rejects invalid id" "$MCP_BAD" 'invalid id'
MCP_DATA_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"hart_data","arguments":{"id":"bad$/x","data":"{}"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_data rejects invalid id" "$MCP_DATA_BAD" 'invalid id'
MCP_PUB_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"hart_publish","arguments":{"html":"<h1>x</h1>","owner":"!!!","artifact":"x"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_publish rejects invalid owner" "$MCP_PUB_BAD" 'invalid owner'
MCP_LIST_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"hart_list","arguments":{"owner":"!!!"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_list rejects invalid owner" "$MCP_LIST_BAD" 'invalid owner'
MCP_STATS_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"hart_stats","arguments":{"id":"bad$/x"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_stats rejects invalid id" "$MCP_STATS_BAD" 'invalid id'
MCP_STALE_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"hart_stale","arguments":{"owner":"!!!"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_stale rejects invalid owner" "$MCP_STALE_BAD" 'invalid owner'
MCP_PUB_ART_BAD=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"hart_publish","arguments":{"html":"<h1>x</h1>","owner":"acme","artifact":"!!!"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_publish rejects invalid artifact" "$MCP_PUB_ART_BAD" 'invalid artifact'

echo "== living loop (refresh) =="
# url source: point at the daemon's own /_health (valid JSON), min-interval clamps 5s -> 30s
RS=$(./hart refresh acme/page --url "$HART_URL/_health" --every 5s)
eq "refresh set ok" "$(echo "$RS" | jget ok)" "True"
eq "sub-30s interval clamps to 30" "$(echo "$RS" | jget every)" "30"
has "refresh --now runs and reports ok" "$(./hart refresh acme/page --now)" '"last_status":"ok"'
has "page now embeds the fetched data" "$(curl -s "$HART_URL/a/acme/page")" '"service":"hart"'
has "refresh status shows configured" "$(./hart refresh acme/page)" '"configured":true'
# cmd source requires the admin token; without it -> 403
has "cmd source needs admin (403 without)" "$(HART_ADMIN_TOKEN= ./hart refresh acme/page --cmd 'echo x' --every 30s 2>&1)" "admin only"
has "cmd source ok with admin token" "$(./hart refresh acme/page --cmd 'printf "{\"n\":1}"' --every 30s)" '"kind":"cmd"'
has "cmd --now pushes JSON" "$(./hart refresh acme/page --now && curl -s "$HART_URL/a/acme/page")" '"n":1'
# non-JSON output is rejected, existing data preserved
has "non-JSON source rejected" "$(./hart refresh acme/page --cmd 'echo nope' --every 30s >/dev/null; ./hart refresh acme/page --now)" "not JSON"
has "refresh --off disables" "$(./hart refresh acme/page --off)" '"enabled":false'
# rm must clean up the refresh row (no orphan self-refresh source)
./hart publish "$P" --owner acme --artifact rtmp >/dev/null
./hart refresh acme/rtmp --url "$HART_URL/_health" --every 30s >/dev/null
./hart rm acme/rtmp >/dev/null
./hart publish "$P" --owner acme --artifact rtmp >/dev/null
has "rm cleans up the refresh row" "$(./hart refresh acme/rtmp)" '"configured":false'

echo "== live repaint (browser, D2 slice 2) =="
LIVE="$TMP/live.html"; printf '<div id=x></div><script>window.addEventListener("hart:data",function(e){})</script>' > "$LIVE"
./hart publish "$LIVE" --owner acme --artifact live --live >/dev/null
./hart data acme/live '{"count":7}' >/dev/null
has "live page relaxes CSP to connect-src 'self'" "$(curl -s -D - -o /dev/null "$HART_URL/a/acme/live")" "connect-src 'self'"
has "live page injects the self-poller" "$(curl -s "$HART_URL/a/acme/live")" "/a/acme/live/data.json"
eq  "data.json serves current data" "$(curl -s "$HART_URL/a/acme/live/data.json")" '{"count":7}'
# a pristine (never-live) artifact stays fully locked down
./hart publish "$LIVE" --owner acme --artifact plainx >/dev/null
has "non-live page keeps default-src 'none'" "$(curl -s -D - -o /dev/null "$HART_URL/a/acme/plainx")" "default-src 'none'"
case "$(curl -s -D - -o /dev/null "$HART_URL/a/acme/plainx")" in *"connect-src"*) bad "non-live page has NO connect-src";; *) ok "non-live page has NO connect-src";; esac
has "hart live off returns to lockdown" "$(./hart live acme/live off; curl -s -D - -o /dev/null "$HART_URL/a/acme/live")" "default-src 'none'"
case "$(curl -s -D - -o /dev/null "$HART_URL/a/acme/live")" in *"connect-src"*) bad "live off removed connect-src";; *) ok "live off removed connect-src";; esac

echo "== pro license (M3 slice 0) =="
has "no license -> free tier" "$(./hart license status)" '"tier":"free"'
has "no license -> not licensed" "$(./hart license status)" '"licensed":false'
has "garbage key stored but invalid" "$(./hart license 'hart_pro.bogus.sig')" '"valid":false'
has "still free after invalid key" "$(./hart license status)" '"licensed":false'
# limits gating (slice 1): status exposes the effective quota; default free ceiling = 30MB (no regression)
has "status exposes limits + free ceiling" "$(./hart license status)" '"free_ceiling_mb"'
has "default effective quota is 30MB (unchanged for free)" "$(./hart license status)" '"owner_mb":30'
has "free tier is not unlimited" "$(./hart license status)" '"unlimited":false'
# audit log is a pro feature: gated when unlicensed
has "audit log gated to Pro (403)" "$(./hart audit 2>&1)" "hart Pro feature"
# teams gated to Pro
has "team add gated to Pro" "$(./hart team add acme x@y.co 2>&1)" "hart Pro feature"
has "team list gated to Pro" "$(./hart team list acme 2>&1)" "hart Pro feature"
# upgrade: agent-first buy — fails gracefully when hart-cloud is unreachable
eq "upgrade errors cleanly if hart-cloud down" "$(HART_CLOUD_URL=http://127.0.0.1:1 ./hart upgrade >/dev/null 2>&1; echo $?)" "100"
# teams SSO (join) gated to Pro; team invite gated to Pro
has "join gated to Pro" "$(./hart join acme 2>&1)" "hart Pro feature"
has "team invite gated to Pro" "$(./hart team invite acme x@y.co 2>&1)" "hart Pro feature"

echo "== hardening (input validation + production defaults) =="
eq "invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?owner=!!!&artifact=x" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
eq "invalid artifact rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?owner=acme&artifact=!!!" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
has "publish invalid artifact body" "$(curl -s -X POST "$HART_URL/v1/publish?owner=acme&artifact=!!!" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "invalid artifact"
eq "traversal id rejected at publish (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?id=acme/evil/../page" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
eq "double-slash id rejected at publish (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?id=acme//page" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
eq "multi-segment id rejected at publish (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?id=a/b/c" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
eq "empty owner segment rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/publish?id=/page" -H 'content-type: text/html' --data-binary '<h1>x</h1>')" "400"
eq "GET /a double-slash id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/acme//page")" "400"
eq "GET /a traversal rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$HART_URL/a/acme/../page")" "400"
eq "GET /a/bad\$/data.json rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/bad\$/data.json")" "400"
eq "CLI invalid owner rejected locally (80)" "$(printf '<h1>x</h1>' > "$TMP/x2.html"; ./hart publish "$TMP/x2.html" --owner '!!!' --artifact x >/dev/null 2>&1; echo $?)" "80"
eq "CLI invalid artifact rejected locally (80)" "$(printf '<h1>x</h1>' > "$TMP/x3.html"; ./hart publish "$TMP/x3.html" --owner acme --artifact '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "CLI rm invalid id rejected locally (80)" "$(./hart rm 'acme/../page' >/dev/null 2>&1; echo $?)" "80"
eq "CLI admin mv invalid from rejected locally (80)" "$(./hart admin mv '!!!/x' moved/y >/dev/null 2>&1; echo $?)" "80"
eq "CLI admin mv invalid to rejected locally (80)" "$(./hart admin mv acme/page '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "API visibility invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/visibility?id=bad\$&visibility=public")" "400"
eq "API DELETE invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE "$HART_URL/v1/artifacts/bad\$")" "400"
eq "API rollback invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/artifacts/bad\$/rollback?to=1")" "400"
eq "API stats invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/artifacts/bad\$/stats")" "400"
eq "API fresh invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/fresh?id=bad\$&ttl=60")" "400"
eq "API refresh invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/refresh?id=bad\$")" "400"
eq "GET /a/bad\$ rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/a/bad\$")" "400"
eq "CLI stale invalid owner rejected locally (80)" "$(./hart stale --owner '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "CLI data invalid id rejected locally (80)" "$(./hart data 'bad$/x' '{}' >/dev/null 2>&1; echo $?)" "80"
eq "CLI visibility invalid id rejected locally (80)" "$(./hart visibility 'bad$/x' public >/dev/null 2>&1; echo $?)" "80"
eq "CLI fresh invalid id rejected locally (80)" "$(./hart fresh 'bad$/x' 1m >/dev/null 2>&1; echo $?)" "80"
eq "CLI live invalid id rejected locally (80)" "$(./hart live 'bad$/x' on >/dev/null 2>&1; echo $?)" "80"
eq "CLI list invalid owner rejected locally (80)" "$(./hart list --owner '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "API data invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/data?id=bad\$" -H 'content-type: application/json' --data-binary '{}')" "400"
eq "API data invalid artifact rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/data?owner=acme&artifact=!!!" -H 'content-type: application/json' --data-binary '{}')" "400"
eq "API live invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/live?id=bad\$&on=1")" "400"
eq "API list invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/artifacts?owner=!!!")" "400"
eq "API stale invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -H "$ADMH" "$HART_URL/v1/stale?owner=!!!")" "400"
eq "API admin list invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -H "$ADMH" "$HART_URL/v1/admin/list?owner=!!!")" "400"
eq "GET /o invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/o/!!!")" "400"
eq "GET /v1/public invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/v1/public?owner=!!!")" "400"
eq "POST /a/bad\$/unlock rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/a/bad\$/unlock" -d 'key=x')" "400"
eq "POST /v1/join/start invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/join/start?owner=!!!")" "400"
has "join/start invalid owner body" "$(curl -s -X POST "$HART_URL/v1/join/start?owner=!!!")" "invalid owner"
eq "POST /v1/team invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/team?owner=!!!&email=x@y.co")" "400"
eq "POST /v1/team/rm invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/team/rm?owner=!!!&email=x@y.co")" "400"
eq "GET /v1/audit invalid owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -H "$ADMH" "$HART_URL/v1/audit?owner=!!!")" "400"
eq "CLI get invalid id rejected locally (80)" "$(./hart get 'bad$/x' >/dev/null 2>&1; echo $?)" "80"
eq "CLI versions invalid id rejected locally (80)" "$(./hart versions 'bad$/x' >/dev/null 2>&1; echo $?)" "80"
eq "CLI rollback invalid id rejected locally (80)" "$(./hart rollback 'bad$/x' 1 >/dev/null 2>&1; echo $?)" "80"
eq "CLI audit invalid owner rejected locally (80)" "$(./hart audit --owner '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "CLI team list invalid owner rejected locally (80)" "$(./hart team list '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "CLI join invalid owner rejected locally (80)" "$(./hart join '!!!' >/dev/null 2>&1; echo $?)" "80"
eq "CLI get rejects double-slash id locally (80)" "$(./hart get 'acme//page' >/dev/null 2>&1; echo $?)" "80"
MCP_DBL=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"hart_data","arguments":{"id":"acme//page","data":"{}"}}}' \
  | ./hart mcp 2>/dev/null)
has "mcp hart_data rejects double-slash id" "$MCP_DBL" 'invalid id'
ANON=$(./hart publish "$P" --title anon-test)
has "anonymous publish (hex id) still ok" "$ANON" '"ok":true'
case "$(echo "$ANON" | jget id)" in */*) bad "anonymous id must not contain /";; *) ok "anonymous id is hex (no slash)";; esac
eq "API admin mv invalid to owner rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -H "$ADMH" -X POST "$HART_URL/v1/admin/mv?from=acme/page&to=!!!/x")" "400"
eq "API admin mv invalid to artifact rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -H "$ADMH" -X POST "$HART_URL/v1/admin/mv?from=acme/page&to=acme/!!!")" "400"
eq "API refresh/run invalid id rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$HART_URL/v1/refresh/run?id=bad\$")" "400"
eq "runtime path traversal rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' --path-as-is "$HART_URL/_hart/runtime/../react.js")" "400"
eq "runtime backslash rejected (400)" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/_hart/runtime/%5C..%5Creact.js")" "400"
# boot a hardened daemon (HART_PUBLIC triggers machweb harden + body cap)
HPORT=$((PORT + 1))
export HART_DB="$TMP/harden.db"
HART_PUBLIC="http://127.0.0.1:$HPORT" HART_HARDEN=1 HART_MAX_BODY_BYTES=100 HART_MAX_SUBMITS_PER_MIN=100000 \
  ./hart serve "$HPORT" >"$TMP/harden.log" 2>&1 &
HSRV=$!
sleep 1
kill -0 "$HSRV" 2>/dev/null || { echo "test: hardened daemon failed to boot"; cat "$TMP/harden.log"; exit 1; }
BIG="$(python3 -c 'print("x"*200)')"
eq "hardened daemon rejects oversized body (413)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$HPORT/v1/publish?owner=t&artifact=big" -H 'content-type: text/html' --data-binary "$BIG")" "413"
curl -s -o /dev/null "http://127.0.0.1:$HPORT/_health" >/dev/null
has "hardened daemon emits JSON access log" "$(grep -q '"method"' "$TMP/harden.log" && echo yes || echo no)" "yes"
kill "$HSRV" 2>/dev/null
# HART_PUBLIC alone (no explicit HART_HARDEN=1) still enables body cap
HPORT2=$((PORT + 2))
export HART_DB="$TMP/harden2.db"
HART_PUBLIC="http://127.0.0.1:$HPORT2" HART_MAX_BODY_BYTES=100 HART_MAX_SUBMITS_PER_MIN=100000 \
  ./hart serve "$HPORT2" >"$TMP/harden2.log" 2>&1 &
HSRV2=$!
sleep 1
kill -0 "$HSRV2" 2>/dev/null || { echo "test: HART_PUBLIC-only daemon failed to boot"; cat "$TMP/harden2.log"; exit 1; }
eq "HART_PUBLIC alone rejects oversized body (413)" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$HPORT2/v1/publish?owner=t&artifact=big" -H 'content-type: text/html' --data-binary "$BIG")" "413"
kill "$HSRV2" 2>/dev/null
export HART_DB="$TMP/test.db"   # restore primary daemon db
# rate-limit smoke: 2 submits/min → third publish in the same window gets 429
RPORT=$((PORT + 3))
export HART_DB="$TMP/rate.db"
HART_MAX_SUBMITS_PER_MIN=2 ./hart serve "$RPORT" >"$TMP/rate.log" 2>&1 &
RSRV=$!
sleep 1
kill -0 "$RSRV" 2>/dev/null || { echo "test: rate-limit daemon failed to boot"; cat "$TMP/rate.log"; exit 1; }
RB="$TMP/rate.html"; printf '<h1>r</h1>' > "$RB"
curl -s -o /dev/null -X POST "http://127.0.0.1:$RPORT/v1/publish?owner=rl&artifact=a" -H 'content-type: text/html' --data-binary @"$RB" >/dev/null
curl -s -o /dev/null -X POST "http://127.0.0.1:$RPORT/v1/publish?owner=rl&artifact=b" -H 'content-type: text/html' --data-binary @"$RB" >/dev/null
eq "rate limit: third submit in window -> 429" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$RPORT/v1/publish?owner=rl&artifact=c" -H 'content-type: text/html' --data-binary @"$RB")" "429"
kill "$RSRV" 2>/dev/null
export HART_DB="$TMP/test.db"

echo "== served endpoints =="
for ep in _health guide.md skill.md llms.txt install.sh _status byok.md; do
  eq "GET /$ep -> 200" "$(curl -s -o /dev/null -w '%{http_code}' "$HART_URL/$ep")" "200"
done
has "byok.md documents HART_ADMIN_TOKEN" "$(curl -s "$HART_URL/byok.md")" "HART_ADMIN_TOKEN"
has "/_status shows production hardening row" "$(curl -s "$HART_URL/_status")" "production hardening"

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
