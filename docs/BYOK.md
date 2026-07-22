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
| **Publish token** | Operator | `HART_TOKEN` | `hart login <token>` or `HART_TOKEN` | Gates *all* mutating API calls when set. Unset = open publish (fine for localhost). |
| **Owner key** | Publisher (first claim) | — | `--owner-key` or `HART_OWNER_KEY` | Claims an `--owner` namespace; further writes to that owner need the key. Stored **hashed** server-side. |
| **Read key** | Publisher | — | `--read-key` at publish, or `HART_READ_KEY` when fetching | Unlocks **private** artifacts (`--visibility private`). Browsers use the unlock page + cookie; agents send `X-Hart-Read-Key`. Stored **hashed**. |
| **Admin token** | Operator | `HART_ADMIN_TOKEN` | `hart admin login <token>` or `HART_ADMIN_TOKEN` | Cross-owner `hart admin list`, `/_fleet` dashboard, `refresh --cmd`, etc. **Separate** from `HART_TOKEN`. Unset = admin API off (403). |
| **Member key** | Team admin (Pro) | — | `HART_MEMBER_KEY` or `--member-key` | Per-member write access to a shared owner namespace. Stored **hashed**. |
| **License key** | Buyer (Pro) | `HART_LICENSE_KEY` | `hart license <key>` | Unlocks Pro features (limits, audit log, teams). Verified offline (Ed25519). |
| **Cookie secret** | Operator | `HART_COOKIE_SECRET` | — | Signs private-artifact unlock cookies. Pin across restarts or users re-enter passwords after deploy. |
| **OIDC client** | Operator (Pro SSO) | `HART_OIDC_ISSUER`, `HART_OIDC_CLIENT_ID`, `HART_OIDC_CLIENT_SECRET` | — | Generic OpenID Connect for `hart join` team self-onboarding. |

**Rule of thumb:** daemon env = operator knobs; client env / flags = what your agents carry.

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
HART_MAX_OWNER_MB=30
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

## Security notes

- **Never commit secrets.** Use env files with `0600` permissions or your secret manager.
- **Admin ≠ publish.** `HART_ADMIN_TOKEN` must differ from `HART_TOKEN` so a publish credential
  cannot enumerate every owner on the box.
- **Owner keys are hashed** — the daemon never stores or returns the plaintext; reset by claiming
  a new owner or using admin tooling.
- **Rate limits** use the client IP from the socket unless `HART_TRUST_PROXY=1` (only enable behind
  a reverse proxy you control).
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
