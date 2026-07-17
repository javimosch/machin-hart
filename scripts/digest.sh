#!/usr/bin/env bash
# digest.sh — publish the operator adoption digest to hart ITSELF as a private, versioned
# artifact (dogfooding: the digest is a living hart deliverable; each run appends a version,
# so /a/<owner>/<artifact>/v<n> is a week-by-week history). Drive it from a systemd timer.
#
# Reads the digest via the admin API, renders a self-contained dark HTML page (CSP-safe:
# inline only, no external refs/network), and publishes it under a dedicated, key-protected,
# private namespace.
#
# Env:
#   HART_URL               daemon (e.g. http://127.0.0.1:8799 on the host, or https://hart.intrane.fr)
#   HART_ADMIN_TOKEN       to read /v1/admin/digest
#   HART_DIGEST_OWNER_KEY  claims + protects the digest namespace (only this script can update it)
#   HART_DIGEST_READ_KEY   password to VIEW the private digest
#   HART_DIGEST_DAYS       window (default 7) · HART_DIGEST_OWNER (default ops) · HART_DIGEST_ARTIFACT (default digest)
#   HART_BIN               hart binary (default: hart on PATH)
#
# Flags:
#   --stdout   render the HTML to stdout and exit — do NOT publish. Lets one renderer feed
#              both the hart artifact and an emailer (e.g. machin-herald's target command).
set -euo pipefail
STDOUT_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --stdout) STDOUT_ONLY=1 ;;
    *) echo "digest.sh: unknown flag: $arg (only --stdout)" >&2; exit 2 ;;
  esac
done
: "${HART_URL:?set HART_URL}"
: "${HART_ADMIN_TOKEN:?set HART_ADMIN_TOKEN}"
if [ "$STDOUT_ONLY" = 0 ]; then
  # only needed to publish
  : "${HART_DIGEST_OWNER_KEY:?set HART_DIGEST_OWNER_KEY}"
  : "${HART_DIGEST_READ_KEY:?set HART_DIGEST_READ_KEY}"
fi
DAYS="${HART_DIGEST_DAYS:-7}"
OWNER="${HART_DIGEST_OWNER:-ops}"
ART="${HART_DIGEST_ARTIFACT:-digest}"
HART="${HART_BIN:-hart}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

"$HART" admin digest --days "$DAYS" > "$TMP/d.json"

DIGEST_JSON="$TMP/d.json" HART_URL="$HART_URL" DAYS="$DAYS" python3 - > "$TMP/d.html" <<'PY'
import json, os, datetime
d = json.load(open(os.environ["DIGEST_JSON"]))
base = os.environ["HART_URL"].rstrip("/")
days = os.environ["DAYS"]
t = d["totals"]
gen = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
esc = lambda s: (str(s).replace("&","&amp;").replace("<","&lt;").replace(">","&gt;"))

def stat(label, val, sub):
    return (f'<div class="card"><div class="v">{esc(val)}</div>'
            f'<div class="l">{esc(label)}</div><div class="s">{esc(sub)}</div></div>')

tops = "".join(
    f'<tr><td><a href="{base}/a/{esc(x["id"])}">{esc(x["id"])}</a></td>'
    f'<td class="num">{x["views"]}</td></tr>' for x in d.get("top_artifacts", [])
) or '<tr><td colspan="2" class="muted">no views yet</td></tr>'

recent = "".join(
    f'<li><a href="{base}/a/{esc(x["id"])}">{esc(x["id"])}</a></li>'
    for x in d.get("recent", [])
) or '<li class="muted">nothing new in this window</li>'

html = f"""<h1>hart &mdash; operator digest</h1>
<p class="sub">Last {esc(days)} days &middot; generated {esc(gen)}</p>
<div class="grid">
{stat("new owners", "+"+str(d["new_owners"]), "first publish in window")}
{stat("new artifacts", "+"+str(d["new_artifacts"]), "created in window")}
{stat("active", str(d["active_artifacts"]), "updated in window")}
{stat("total views", str(t["views"]), f'{t["artifacts"]} artifacts · {t["owners"]} owners')}
</div>
<h2>Top by views</h2>
<table><thead><tr><th>artifact</th><th class="num">views</th></tr></thead><tbody>{tops}</tbody></table>
<h2>Recent publishes</h2>
<ul class="recent">{recent}</ul>
<p class="foot">hart operator digest &middot; a living, versioned hart artifact &middot; each run appends a version.</p>"""

style = """
:root{color-scheme:dark}
body{margin:0;background:#0e1216;color:#e8edf2;font:15px/1.6 system-ui,-apple-system,sans-serif}
.wrap{max-width:720px;margin:0 auto;padding:48px 24px 72px}
h1{font-size:26px;letter-spacing:-.02em;margin:0 0 4px}
.sub{color:#8b97a4;font:13px ui-monospace,monospace;margin:0 0 28px}
h2{font-size:15px;text-transform:uppercase;letter-spacing:.12em;color:#8b97a4;margin:32px 0 12px}
.grid{display:grid;grid-template-columns:repeat(2,1fr);gap:12px}
@media(min-width:560px){.grid{grid-template-columns:repeat(4,1fr)}}
.card{background:#151b21;border:1px solid #232c34;border-radius:12px;padding:16px}
.card .v{font-size:26px;font-weight:700;color:#3ad0c4;letter-spacing:-.02em}
.card .l{font-size:13px;color:#e8edf2;margin-top:2px}
.card .s{font-size:11px;color:#5c6773;margin-top:4px}
table{width:100%;border-collapse:collapse;font-size:14px}
th{text-align:left;color:#5c6773;font:11px ui-monospace,monospace;text-transform:uppercase;letter-spacing:.1em;border-bottom:1px solid #232c34;padding:8px 6px}
td{padding:9px 6px;border-bottom:1px solid #1b232a}
.num{text-align:right;font-variant-numeric:tabular-nums}
a{color:#3ad0c4;text-decoration:none}a:hover{text-decoration:underline}
.recent{list-style:none;padding:0;margin:0;font:13px ui-monospace,monospace}
.recent li{padding:5px 0;border-bottom:1px solid #1b232a}
.muted{color:#5c6773}
.foot{color:#5c6773;font-size:12px;margin-top:36px;border-top:1px solid #232c34;padding-top:16px}
"""
print(f'<div class="wrap"><style>{style}</style>{html}</div>')
PY

if [ "$STDOUT_ONLY" = 1 ]; then cat "$TMP/d.html"; exit 0; fi

"$HART" publish "$TMP/d.html" --owner "$OWNER" --artifact "$ART" \
  --title "hart — operator digest" --format html --visibility private \
  --owner-key "$HART_DIGEST_OWNER_KEY" --read-key "$HART_DIGEST_READ_KEY"
