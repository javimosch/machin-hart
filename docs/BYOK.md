# hart — BYOK setup (Bring Your Own Key)

hart is **BYOK by design**: you run the binary on your infrastructure and supply every secret
yourself. Nothing is hosted for you unless you choose a shared instance (e.g. hart.intrane.fr).
This guide maps each key/token to its role, where to set it, and a minimal production layout.

---

## Which keys do I need?

Pick the row that matches your setup — only configure what that row lists.

| Scenario | Daemon (`hart serve`) | Agent / CLI client |
|---|---|---|
| **Open shared instance** (e.g. hart.intrane.fr — anyone may publish) | *(none)* | Optional `HART_OWNER_KEY` — pass on the **first** write to `--owner` to claim and lock that namespace |
| **Self-hosted, open publish** (localhost / internal LAN) | *(none)* | Same as above — claim namespaces with `--owner-key` if you care about write protection |
| **Self-hosted, locked down** (team box behind a proxy) | `HART_TOKEN` · `HART_PUBLIC` · `HART_COOKIE_SECRET` (if private pages) | `HART_TOKEN` (`hart login`) · per-namespace `HART_OWNER_KEY` |
| **Operator audit / fleet dashboard** | add `HART_ADMIN_TOKEN` (**≠** `HART_TOKEN`) | operators only: `HART_ADMIN_TOKEN` (`hart admin login`) |
| **Private deliverables** | `HART_COOKIE_SECRET` (so unlock cookies survive restarts) | `--read-key` at publish, or `HART_READ_KEY` when fetching |
| **hart Pro** (higher limits, audit log, teams) | `HART_LICENSE_KEY` | `hart license <key>` on the client; teams may also need `HART_MEMBER_KEY` |

**Agent integration paths** (all inherit the same env vars):

1. **curl** — no install; POST to `/v1/publish` (see [`llms.txt`](../llms.txt)).
2. **CLI** — `curl -fsSL <instance>/install.sh | sh`, then `export HART_URL=…` and `hart publish …`.
3. **Drop-in skill** — `hart skill > ~/.claude/skills/hart/SKILL.md` (Cursor: `.cursor/skills/hart/SKILL.md`).
4. **MCP** — `{"mcpServers":{"hart":{"command":"hart","args":["mcp"],"env":{"HART_URL":"…","HART_TOKEN":"…","HART_OWNER_KEY":"…"}}}}`.

---

## Key map

| Secret | Who sets it | Where (daemon) | Where (client / agent) | Purpose |
|---|---|---|---|---|
| **Publish token** | Operator | `HART_TOKEN` | `hart login <token>`, `HART_TOKEN` env, or `.hart.env` / `~/.hart/config` | Gates *all* mutating API calls when set. Unset = open publish (fine for localhost). |
| **Owner key** | Publisher (first claim) | — | `--owner-key`, `HART_OWNER_KEY` env, or `.hart.env` / `~/.hart/config` | Claims an `--owner` namespace; further writes to that owner need the key. Stored **hashed** server-side. |
| **Read key** | Publisher | — | `--read-key` at publish, `HART_READ_KEY` env, or `.hart.env` / `~/.hart/config` | Unlocks **private** artifacts (`--visibility private`). Browsers use the unlock page + cookie; agents send `X-Hart-Read-Key`. Stored **hashed**. |
| **Admin token** | Operator | `HART_ADMIN_TOKEN` | `hart admin login <token>`, `HART_ADMIN_TOKEN` env, or `.hart.env` / `~/.hart/config` | Cross-owner `hart admin list`, `/_fleet` dashboard, `refresh --cmd`, etc. **Separate** from `HART_TOKEN`. Unset = admin API off (403). |
| **Member key** | Team admin (Pro) | — | `--member-key`, `HART_MEMBER_KEY` env, or `.hart.env` / `~/.hart/config` | Per-member write access to a shared owner namespace. Stored **hashed**. |
| **License key** | Buyer (Pro) | `HART_LICENSE_KEY` | `hart license <key>` | Unlocks Pro features (limits, audit log, teams). Verified offline (Ed25519). |
| **Cookie secret** | Operator | `HART_COOKIE_SECRET` | — | Signs private-artifact unlock cookies. Pin across restarts or users re-enter passwords after deploy. |
| **Domain policy** | Operator | `HART_DOMAIN_ALLOW`, `HART_DOMAIN_DENY`, `HART_DOMAIN_PRIVATE_PATTERNS`, `HART_DOMAIN_SUBDOMAIN_OWNER_MATCH`, `HART_DOMAIN_MAX_PER_OWNER`, `HART_DOMAIN_GC_INTERVAL` | — | Controls self-service custom domains: allow/deny patterns, forced-private patterns, owner-label matching, per-owner cap, and orphan cleanup interval. |
| **Domain hook** | Operator | `HART_DOMAIN_HOOK=<path>` | — | Executable invoked `add|remove <domain> <owner> <artifact>` on every mapping change (e.g. `hart-domain-sync`). |
| **Read rate limit** | Operator | `HART_MAX_READ_ATTEMPTS_PER_MIN`, `HART_MAX_READ_ATTEMPTS_PER_ID_PER_MIN` | — | Per-IP sliding-window limits for failed attempts to read a private artifact. Defaults: 30 per IP per minute, 10 per IP per artifact per minute. Set to `0` to disable. |
| **OIDC client** | Operator (Pro SSO) | `HART_OIDC_ISSUER`, `HART_OIDC_CLIENT_ID`, `HART_OIDC_CLIENT_SECRET` | — | Generic OpenID Connect for `hart join` team self-onboarding. |

**Rule of thumb:** daemon env = operator knobs; client env / flags = what your agents carry.

**Client config files:** `.hart.env` in the current directory and `~/.hart/config` are loaded for every CLI command except `hart serve`. Precedence: flag > env > `.hart.env` > `~/.hart/config`. Keep them out of git if they hold secrets.

For multiple namespaces/artifacts you can use the flat-key form: `HART_OWNER_KEY_<owner>` and `HART_READ_KEY_<owner>_<artifact>` (non-alnum/slashes become `_`). Example: `HART_OWNER_KEY_vigie` or `HART_READ_KEY_vigie_secret_report`.

---

## Quick start — single operator, one agent fleet

### 1. Generate secrets

```sh
PUBLISH=$(openssl rand -hex 24)
ADMIN=$(openssl rand -hex 24)
OWNER=$(openssl rand -hex 24)
COOKIE=$(openssl rand -hex 24)
```

### 2. Run the daemon (systemd-friendly env file)

```sh
# /etc/hart/env
HART_DB=/var/lib/hart/hart.db
HART_PUBLIC=https://hart.example.com
HART_TOKEN=<PUBLISH>
HART_ADMIN_TOKEN=<ADMIN>
HART_COOKIE_SECRET=<COOKIE>
HART_TRUST_PROXY=1
HART_MAX_BODY_BYTES=10485760
HART_MAX_SUBMITS_PER_MIN=30
HART_MAX_READ_ATTEMPTS_PER_MIN=30
HART_MAX_READ_ATTEMPTS_PER_ID_PER_MIN=10
HART_MAX_OWNER_MB=30
# Optional — self-service custom domains (patterns are comma-separated; examples use *.example.com):
# HART_DOMAIN_ALLOW=*.example.com
# HART_DOMAIN_DENY=blocked.example.com
# HART_DOMAIN_PRIVATE_PATTERNS=secret.example.com
# HART_DOMAIN_SUBDOMAIN_OWNER_MATCH=1
# HART_DOMAIN_MAX_PER_OWNER=10
# HART_DOMAIN_GC_INTERVAL=5m
# HART_DOMAIN_HOOK=/opt/hart/hart-domain-hook.sh
# Optional — hart Pro + teams SSO (see key map above):
# HART_LICENSE_KEY=<pro-key>
# HART_OIDC_ISSUER=https://your-idp.example.com
# HART_OIDC_CLIENT_ID=<client-id>
# HART_OIDC_CLIENT_SECRET=<client-secret>
```

```sh
hart serve 8799   # or bind via reverse proxy to :8799
```

With `HART_PUBLIC` set, the daemon enables **machweb hardening**: proxy-aware client IP (when
`HART_TRUST_PROXY=1`), Secure cookies over HTTPS, structured access logs, a per-request body cap
(default 10 MiB), and read timeouts. Local dev: `HART_HARDEN=0` disables this.

### 3. Configure agents (CLI)

```sh
export HART_URL=https://hart.example.com
hart login <PUBLISH>              # writes ~/.hart-token
export HART_OWNER_KEY=<OWNER>     # claim your namespace on first publish

hart publish report.html --owner acme --artifact q3 --owner-key "$HART_OWNER_KEY"
```

Or in MCP / Cursor:

```json
{
  "mcpServers": {
    "hart": {
      "command": "hart",
      "args": ["mcp"],
      "env": {
        "HART_URL": "https://hart.example.com",
        "HART_TOKEN": "<PUBLISH>",
        "HART_OWNER_KEY": "<OWNER>"
      }
    }
  }
}
```

### 4. curl-only agents (HTTP headers)

No `hart` binary? The CLI sends the same headers on every mutating call — mirror them in curl or
any HTTP client:

| Header | When |
|---|---|
| `Authorization: Bearer <token>` | Instance has `HART_TOKEN` set (401 without it). Publish token, or admin token for operator scripts. |
| `X-Hart-Owner-Key: <secret>` | Writes to a **claimed** `--owner` namespace (403 without it). Pass on the first publish to claim. |
| `X-Hart-Read-Key: <password>` | Read a **private** artifact (401 without it). Browsers may use `?read_key=` instead. |
| `X-Hart-Member-Key: <secret>` | hart Pro teams — per-member write to a shared owner namespace. |

```sh
curl -X POST "$HART_URL/v1/publish?owner=acme&artifact=q3" \
  -H "authorization: Bearer $HART_TOKEN" \
  -H "x-hart-owner-key: $HART_OWNER_KEY" \
  -H "content-type: text/html" \
  --data-binary @report.html
```

**Token files vs env:** `HART_TOKEN` / `HART_ADMIN_TOKEN` env vars win over
`~/.hart-token` / `~/.hart-admin-token` (written by `hart login` / `hart admin login`). Flags
`--owner-key` / `--read-key` override `HART_OWNER_KEY` / `HART_READ_KEY` for a single call.

---

## Patterns

### Open instance, protected namespaces (hart.intrane.fr style)

- Daemon: **no** `HART_TOKEN` (anyone may publish).
- Agents: pass `--owner-key` on the **first** write to a new `--owner` to claim it; keep the key in
  `HART_OWNER_KEY` for later publishes / `hart data` / `hart visibility`.

### Locked-down team instance

- Daemon: `HART_TOKEN` + `HART_ADMIN_TOKEN`.
- Agents: `HART_TOKEN` + per-namespace `HART_OWNER_KEY`.
- Operators: `HART_ADMIN_TOKEN` for fleet-wide audit (`hart admin list`, `/_fleet`).

### Private deliverables

```sh
hart publish sheet.html --owner acme --artifact leads \
  --visibility private --read-key "$(openssl rand -hex 16)"
# Share the read key out-of-band. Agents: HART_READ_KEY or X-Hart-Read-Key header.
```

### hart Pro (self-host)

```sh
hart upgrade                    # checkout URL for the human
hart license <key>              # or HART_LICENSE_KEY on the daemon
hart license status             # tier, features, storage limits
```

---

## Self-service custom domains (#19)

### What a mapped domain serves — and what it does not

A mapped domain serves **the artifact, and nothing else about hart**. `/` is the page, its own
`/a/<id>/data.json` and `/_hart/runtime/*` load so a live or JSX artifact works, and `/_health`
answers so an uptime probe can point at the domain it already knows. **Every other path 404s**,
with a body naming hart's real home.

This matters more than a tidy 404. Before it, hart's own surfaces fell through on a mapped
domain: `GET /llms.txt` on a customer's product domain returned **hart's manual** with a `200`,
so an agent following the `llms.txt` convention was told the domain was an artifact host with an
open publish API — a confident wrong answer, not a recoverable error. It also leaked past a gate:
a domain mapped to a *private* artifact answered `401` at `/` and `200` at `/llms.txt`.

It is deliberately an allow-list rather than a growing set of exceptions. An artifact is **one
self-contained page**; the moment a domain answers for a second file — a stylesheet, an image, a
sitemap — hart is a static site host wearing a different name. If your domain needs a file tree,
it needs a server, not an artifact host.


Custom-domain mapping (`hart domain <id> <domain>`, `POST /v1/domain`) is open to any agent that
can write to the owner namespace. On a shared instance like `hart.intrane.fr`, that means an
external agent can reserve and serve `mything.hart.intrane.fr` **without operator approval**. Four
daemon env vars gate that flow so self-hosters can keep abusive or off-policy domains out without
reviewing every mapping by hand. All four are read via the existing `cfg()` layer and default to
*off* — an unset variable preserves the previous unrestricted behavior, so upgrading is safe.

The gate order inside `h_domain_set` is **allow/deny → owner-match → private patterns**, run after
`valid_domain` and the owner-key proof, so a rejected mapping never reaches the `domains` table and
never fires `HART_DOMAIN_HOOK`. Each rejection returns `403` with a JSON body that names the policy
that blocked it (`"error":"domain not allowed by policy"` and similar), so an agent can tell which
knob to ask the operator to relax.

### `HART_DOMAIN_ALLOW` / `HART_DOMAIN_DENY`

Comma-separated glob patterns matched case-insensitively against the requested `Host`. `*` is the
only wildcard (suffix, prefix, contains, or whole-string); no `?` or character classes on purpose.

| Var | Empty | Set |
|---|---|---|
| `HART_DOMAIN_ALLOW` | **unrestricted** (current behavior) | the domain must match at least one pattern, else `403` |
| `HART_DOMAIN_DENY` | no denylist | a match is **always `403`**, even if it also matches `ALLOW` |

Examples:

```sh
# /etc/hart/env — only *.hart.intrane.fr may be mapped, and never the admin/api hosts
HART_DOMAIN_ALLOW=*.hart.intrane.fr
HART_DOMAIN_DENY=admin.hart.intrane.fr,api.hart.intrane.fr
```

`HART_DOMAIN_DENY` **always wins over `HART_DOMAIN_ALLOW`** — keep the denylist for the small set of
hostnames you never want served by an agent artifact (`admin.*`, `api.*`, the bare apex, etc.) and
use `ALLOW` for the broad wildcard you do permit. Patterns like `*.hart.intrane.fr` (suffix),
`admin.*` (prefix), and `*x*` (contains) are all supported; exact literals work too.

### `HART_DOMAIN_SUBDOMAIN_OWNER_MATCH`

When set to `1`, the **owner label** in the requested domain must equal the artifact's owner. The
owner label is the label immediately before the instance domain (the canonical host of
`HART_PUBLIC`). For `HART_PUBLIC=https://hart.intrane.fr`:

- `myagent.hart.intrane.fr` → owner label `myagent`
- `foo.myagent.hart.intrane.fr` → owner label `myagent` *(the label right before the instance domain)*
- `shop.example.com` → not under the instance domain → **not subject** to owner-match (left to
  ALLOW/DENY)

| `HART_DOMAIN_SUBDOMAIN_OWNER_MATCH` | `HART_PUBLIC` | domain under instance? | result |
|---|---|---|---|
| empty / `0` | — | — | check disabled (current behavior) |
| `1` | unset | — | skipped — no instance domain to compare (left to ALLOW/DENY) |
| `1` | set | yes, label matches owner | accepted |
| `1` | set | yes, label ≠ owner | **403** |
| `1` | set | no (e.g. `shop.example.com`) | exempt — left to ALLOW/DENY |
| `1` | set | domain == instance domain | skipped (canonical host, not a mapping target) |

The check runs **after** the owner-key proof, using the DB-confirmed artifact owner, so a caller
can't fake the owner label by passing an unverified `--owner`. Pair with
`HART_DOMAIN_ALLOW=*.hart.intrane.fr` to give every agent a self-service subdomain under your
instance while keeping them inside their own namespace.

### `HART_DOMAIN_PRIVATE_PATTERNS`

Comma-separated glob patterns (same `glob_match` as ALLOW/DENY). When a requested domain matches a
pattern, the mapped artifact **must** be `--visibility private`, **must** have a read key set, and
the caller **must** prove read access (`X-Hart-Read-Key` header or `?read_key=` matched against the
stored sha256 hash). Use it to force anything served on a sensitive hostname to be gated.

| `HART_DOMAIN_PRIVATE_PATTERNS` | domain matches? | artifact state | caller read key | result |
|---|---|---|---|---|
| empty | — | — | — | check disabled (current behavior) |
| set | no | — | — | not subject (left to ALLOW/DENY + owner-match) |
| set | yes | private + has read key | valid | accepted |
| set | yes | private + has read key | wrong/missing | **403** |
| set | yes | public/unlisted | — | **403** (must be private) |
| set | yes | private but no read key set | — | **403** (must have a read key) |

```sh
# Internal-only hostnames must always be private + read-key gated
HART_DOMAIN_PRIVATE_PATTERNS=internal.hart.intrane.fr,*.internal.hart.intrane.fr
```

The check runs **after** the owner-match check, so the three gates stack cleanly: ALLOW/DENY →
owner-match → private patterns. A mapped private artifact still requires its read key on every read
(the unlock page for browsers, `X-Hart-Read-Key` for agents) — this knob only tightens *mapping*,
not reads.

### `POST /v1/domain/check` — availability probe

A **public, rate-limited** probe an agent calls before `POST /v1/domain` to ask "is
`mything.hart.intrane.fr` free to reserve?". No token required — it only reports whether the domain
is already recorded in the `domains` table, nothing about the mapped artifact.

```sh
curl -X POST "$HART_URL/v1/domain/check?domain=mything.hart.intrane.fr"
# → {"ok":true,"domain":"mything.hart.intrane.fr","available":1,"reason":"free"}
#   {"ok":true,"domain":"…","available":0,"reason":"taken"}   # already mapped
```

Behavior:

- **Trailing dot is normalized away** — `shop.example.com.` reads as `shop.example.com` (FQDN root
  form). The echoed `domain` is the normalized bare hostname.
- **Invalid domains return `400`** with `{"ok":false,"error":"invalid domain — a bare hostname like shop.example.com"}` (same `valid_domain` gate as `POST /v1/domain`).
- **Rate-limited per IP** via a dedicated `domain_checks` table, independent of the publish rate so
  a busy publisher can't starve availability probes. Defaults: **10 checks / 60s / IP**.
  - `HART_MAX_DOMAIN_CHECKS_PER_MIN` — per-IP cap (default `10`).
  - `HART_DOMAIN_CHECK_WINDOW_S` — sliding window length in seconds (default `60`; shrink for tests).
  - Over the cap → `429 Too Many Requests` with a body naming the limit. Each IP gets its own
    bucket; set `HART_TRUST_PROXY=1` behind a reverse proxy so `X-Forwarded-For` distinguishes
    callers (otherwise every proxied request shares the proxy's IP bucket).

`check` only tells you whether the domain is **currently recorded** — it does **not** run the
ALLOW/DENY, owner-match, or private-pattern gates. An agent that wants to know whether a mapping
will *succeed* still has to attempt `POST /v1/domain` and read the `403` body to learn which policy
blocked it. Use `check` for the cheap "is this name free?" UX, then `POST /v1/domain` for the
authoritative answer.

### Lifecycle notes

- **Domains never expire by TTL.** A mapping stays until `hart domain-rm <domain>` (or
  `DELETE /v1/domain?domain=`) removes it.
- **Overwriting an existing mapping** requires **both** the current mapped owner's key and the new
  artifact owner's key (see the `POST /v1/domain` flow in `hart guide`).
- **`HART_DOMAIN_HOOK`** fires `add` / `remove` on every successful mapping change so an external
  provisioner (e.g. [hart-domain-sync](https://github.com/javimosch/hart-domain-sync)) can reconcile
  Traefik dynamic config + DNS. Rejected mappings never fire the hook.
- **Cleanup of orphaned mappings** (when an artifact is `rm`'d, an owner is `admin mv`'d, or policy
  drifts) is handled by the lifecycle slices of #19 — see `hart domains --prune` and
  `POST /v1/admin/domains/prune` in `hart guide` once enabled on your instance.

---

## Security notes

- **Never commit secrets.** Use env files with `0600` permissions or your secret manager.
- **Admin ≠ publish.** `HART_ADMIN_TOKEN` must differ from `HART_TOKEN` so a publish credential
  cannot enumerate every owner on the box.
- **Owner keys are hashed** — the daemon never stores or returns the plaintext; reset by claiming
  a new owner or using admin tooling.
- **Rate limits** use the client IP from the socket unless `HART_TRUST_PROXY=1` (only enable behind
  a reverse proxy you control). A separate per-IP sliding window limits failed attempts to read a private artifact (`HART_MAX_READ_ATTEMPTS_PER_MIN`, `HART_MAX_READ_ATTEMPTS_PER_ID_PER_MIN`).
- **CSP sandbox** is independent of keys: even with a URL, artifact JS cannot reach the network
  (except opt-in `--live` artifacts polling their own `data.json`).

---

## Production layout (systemd)

Minimal unit — adjust paths and user:

```ini
# /etc/systemd/system/hart.service
[Unit]
Description=hart artifact host
After=network.target

[Service]
Type=simple
User=hart
EnvironmentFile=/etc/hart/env
ExecStart=/usr/local/bin/hart serve 8799
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Behind nginx or Traefik, terminate TLS at the proxy and forward to `:8799`. Set
`HART_PUBLIC=https://hart.example.com` and `HART_TRUST_PROXY=1` so rate limits use the real
client IP and returned URLs are canonical.

---

## Post-deploy verification

After first deploy, confirm the instance is locked down:

```sh
# health + agent onboarding docs
curl -sf "$HART_PUBLIC/_health"
curl -sf "$HART_PUBLIC/byok.md" | head
curl -sf "$HART_PUBLIC/llms.txt" | head

# publish gate (when HART_TOKEN is set)
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=test&artifact=x" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 401

# input validation (owner + artifact slugs)
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=!!!&artifact=x" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=you&artifact=!!!" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400

# input validation (list/data/admin routes)
curl -s -o /dev/null -w '%{http_code}\n' "$HART_PUBLIC/v1/artifacts?owner=!!!"   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/data?id=bad\$" \
  -H 'content-type: application/json' --data-binary '{}'                         # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/data?owner=you&artifact=!!!" \
  -H 'content-type: application/json' --data-binary '{}'                         # expect 400

# input validation (id shape: owner/artifact or anonymous hex — no //, no extra segments)
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?id=acme//page" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?id=a/b/c" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400

# input validation (slug edge cases — no leading/trailing hyphens)
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=-acme&artifact=page" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=acme&artifact=page-" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400

# refresh route id validation
curl -s -o /dev/null -w '%{http_code}\n' "$HART_PUBLIC/v1/refresh?id=bad\$"   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' "$HART_PUBLIC/v1/refresh?id=acme//page"   # expect 400

# optional Pro / team keys (when licensed)
# export HART_MEMBER_KEY=<member-key>   # per-member write access (from `hart team add`)
# export HART_LICENSE_KEY=<pro-key>     # or: hart license <key>

# body cap (when HART_PUBLIC / HART_HARDEN is on)
python3 -c 'print("x"*20000000)' | curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$HART_PUBLIC/v1/publish?owner=t&artifact=big" -H 'content-type: text/html' --data-binary @-  # expect 413
```

Run `./test.sh` from a release checkout (or `./build.sh && ./test.sh`) for the full 90+ check
regression suite before marking production ready.

---

## Related docs

- [`README.md`](../README.md) — overview and self-host quickstart
- [`CONTRACT.md`](../CONTRACT.md) — publish contract and CSP
- `hart guide` / `/guide.md` on any instance — version-exact command reference
