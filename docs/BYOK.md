# hart — BYOK setup (Bring Your Own Key)

hart is **BYOK by design**: you run the binary on your infrastructure and supply every secret
yourself. Nothing is hosted for you unless you choose a shared instance (e.g. hart.intrane.fr).
This guide maps each key/token to its role, where to set it, and a minimal production layout.

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
HART_MAX_SUBMITS_PER_MIN=30
HART_MAX_OWNER_MB=30
# Production hardening (auto-enabled when HART_PUBLIC is set):
# HART_TRUST_PROXY=1          # only if behind nginx/Traefik/Cloudflare
# HART_MAX_BODY_BYTES=10485760
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

# input validation
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/publish?owner=!!!&artifact=x" \
  -H 'content-type: text/html' --data-binary '<h1>x</h1>'   # expect 400

# input validation (owner slugs + artifact ids)
curl -s -o /dev/null -w '%{http_code}\n' "$HART_PUBLIC/v1/artifacts?owner=!!!"   # expect 400
curl -s -o /dev/null -w '%{http_code}\n' -X POST "$HART_PUBLIC/v1/data?id=bad\$" \
  -H 'content-type: application/json' --data-binary '{}'                         # expect 400

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
