# hart — the agent-first artifact host

> Publish self-contained HTML or JSX to a live, shareable URL — from **any** terminal agent, on
> **your** infrastructure, in one CLI call. Claude Artifacts, unbundled and made universal.

`hart` (HTML ARTifacts) is an **agent-first, CLI-only, open-source, self-hosted** artifact host
built as one static **MFL / [machin](https://github.com/javimosch/machin)** binary — it is both
the client (`hart publish …`) and the hosting daemon (`hart serve`). It's the *show* to grepapi's
*find*, bland-cli's *call*, and crm-cli's *remember*.

> **Live demo instance:** **[hart.intrane.fr](https://hart.intrane.fr)** (free/open, rate-limited).
> **Prebuilt binary:** [Releases](https://github.com/javimosch/machin-hart/releases).
> **Want it hosted** (managed, on your own domain, no ops)? Email **[javi@intrane.fr](mailto:javi@intrane.fr)** — I'm gauging interest in a hosted tier.

> **🤖 For agents:** read **[`llms.txt`](llms.txt)** for a 30-second orientation, or run **`hart
> guide`** (also served at any instance's `/llms.txt` and `/guide.md`) for the full, version-exact
> manual. To make an agent publish here **by default**, self-install the drop-in skill: **`hart
> skill > ~/.claude/skills/hart/SKILL.md`** (also served at `/skill.md`).

---

## Why

Terminal agents (Claude Code, Cursor, aider, Codex CLI, Gemini CLI, custom SDK agents, cron jobs)
generate rich HTML deliverables — dashboards, reports, call sheets, mockups — but have **nowhere
to put them**. `open` dies at share-time; a gist mangles the styling; standing up hosting by hand
isn't agent-operable. Claude solved this *inside claude.ai*; everyone else is stuck. `hart` is the
missing primitive — for every agent, on your own box:

```
$ hart publish call-budget.html --owner acme --artifact call-budget
{"ok":true,"id":"acme/call-budget","url":"https://hart.intrane.fr/a/acme/call-budget","version":1,"visibility":"unlisted"}
```

Any agent calls that, parses the JSON, and hands the URL to the user. No UI, no build step, no
lock-in.

## Use an existing instance (fastest)

Install the CLI in one line — it drops `hart` on your PATH already pointed at that instance:

```sh
curl -fsSL https://hart.intrane.fr/install.sh | sh
```

Then publish:

```sh
export HART_URL=https://hart.intrane.fr
hart publish page.html --owner you --artifact my-page
# → {"url":"https://hart.intrane.fr/a/you/my-page", ...}
```

No `hart` binary? Every write is just an HTTP POST — curl it:

```sh
curl -X POST 'https://hart.intrane.fr/v1/publish?owner=you&artifact=my-page' \
  -H 'content-type: text/html' --data-binary @page.html
```

## Agent setup

Agents can publish through **curl**, the **CLI**, a **drop-in skill**, or **MCP** — same HTTP contract, same JSON response. Pick one:

| Path | When to use | Minimal setup |
|---|---|---|
| **curl** | One-off publish, no install | POST body to `/v1/publish?owner=…&artifact=…` |
| **CLI** | Shell agents, cron, scripts | `curl -fsSL <instance>/install.sh \| sh` → `export HART_URL=…` → `hart publish …` |
| **Skill** | Claude / Cursor sessions that publish often | `hart skill > ~/.claude/skills/hart/SKILL.md` (also at `/skill.md`) |
| **MCP** | MCP-native clients (Cursor, Claude Desktop) | `hart mcp` with `HART_URL` (+ tokens if required) in env |

**Claim your namespace** on any instance: the first write to a new `--owner` claims it. Pass
`--owner-key` (or `HART_OWNER_KEY`) to lock that namespace against other writers — especially on
open instances like hart.intrane.fr.

**Self-hosted or locked-down instances** need a publish token on the daemon (`HART_TOKEN`) and
`hart login <token>` on the client. Operators may also set `HART_ADMIN_TOKEN` (separate god-token
for cross-owner audit). Full key map, MCP env example, and systemd layout:
[`docs/BYOK.md`](docs/BYOK.md) (also served at `/byok.md` on any instance).

Repo orientation for agent contributors: [`AGENTS.md`](AGENTS.md).

## Self-host

```sh
# 1. get the binary — from a Release, or build it (needs `machin` on PATH)
./runtime/fetch.sh        # seed the JSX runtime (react/react-dom/babel)
./build.sh                # → ./hart   (vendors framework/machweb.src)
./test.sh                 # optional: 38-check end-to-end regression suite (boots a throwaway daemon)

# 2. run the daemon (SQLite store, your box). Free/open by default.
HART_DB=~/.hart.db HART_RUNTIME_DIR=./runtime HART_LANDING=./landing.html ./hart serve 8799 &

# 3. publish — owner + artifact = a stable, legible URL
export HART_URL=http://localhost:8799
hart publish report.html --owner alice --artifact q3
# → {"id":"alice/q3","url":"http://localhost:8799/a/alice/q3","version":1}
hart publish report.html --owner alice --artifact q3   # re-publish → v2, latest moves
```

Gate publishing with `HART_TOKEN=<secret>`. Expose publicly behind any reverse proxy
(e.g. Traefik + Cloudflare + Let's Encrypt via [hotify-cli](https://github.com/javimosch/hotify-cli))
and set `HART_PUBLIC=https://your.domain` so returned URLs are canonical. Production hardening
(proxy-aware IP, body caps, read timeouts) turns on automatically when `HART_PUBLIC` is set; see
[`docs/BYOK.md`](docs/BYOK.md) for the full key map and a systemd-ready env layout.

Deploying an update to a systemd host? [`scripts/deploy.sh`](scripts/deploy.sh) stages the freshly
built binary, verifies the transfer, backs up + swaps + restarts, health-checks, and **rotates old
backups** (keeps the newest N binaries/DB snapshots). `./scripts/deploy.sh --build --db-backup`
(config via `HART_DEPLOY_HOST` / `HART_KEEP_BINARY_BACKUPS` / …; `--dry-run` to preview).

## The publish contract

`hart` hosts **self-contained** pages — one file, everything inlined. The daemon wraps your body
in a `<!doctype>…<head>` skeleton (title, viewport, CSP) and serves it under a strict, sandboxed
**Content-Security-Policy**:

- ✅ inline `<style>` / `<script>`, `data:` URIs for images/fonts, self-contained pages
- ❌ external `src`/`href` (CDN scripts, remote stylesheets, web fonts, remote images)
- ❌ `fetch` / `XHR` / WebSocket to any host (no `connect-src` → `default-src 'none'`)

Same envelope that wraps Claude's own artifacts — it renders the page while neutering it as an
attack or exfiltration vector. A **publish-time linter** rejects external refs + network calls
(HTTP 422) unless you pass `--force`; `hart publish --dry-run` lints without storing. Full spec:
[`CONTRACT.md`](CONTRACT.md).

## Versioning

Re-publishing the same `--owner/--artifact` appends a version; `latest` tracks newest, old
versions are immutably pinned.

- `/a/<owner>/<artifact>` or `…/latest` → newest
- `/a/<owner>/<artifact>/v<n>` → a pinned version
- `hart rollback <id> <v>` re-points latest (non-destructive)

## Template + data (update without re-uploading)

Publish a template **once**, then push just the **data** — it re-renders. Two mechanisms:
`{{key}}` placeholders in the markup, and `window.HART_DATA` (a JS global your script/JSX reads).

```sh
hart publish chart.html --owner you --artifact sales
hart data you/sales '{"points":[3,1,4,1,5]}'   # re-renders, same URL — great for agent-driven dashboards
```

## JSX

`hart publish app.jsx --format jsx` — author React/JSX; the daemon serves a **same-origin**
React+Babel runtime (`/_hart/runtime/*`) and transpiles **in the browser**. No build step, no CDN.
`React`/`ReactDOM` are globals; render into `#root`.

## Visibility & discovery

- **unlisted** *(default)* — public read, not listed anywhere
- **public** — public read + listed/searchable at **`/explore`** (global) and **`/o/<owner>`**
  (per-owner); `hart explore [query]` is the JSON feed
- **private** — **gated read**: browsers get a password **unlock page** (→ signed cookie); agents
  send an **`X-Hart-Read-Key`** header (`HART_READ_KEY`)

Set with `--visibility` / `--read-key` at publish, or change later with `hart visibility <id>
<mode>` (no new version).

## Ownership (write protection, even on a free instance)

The first write to a new `--owner` claims it. Pass `--owner-key <secret>` (or `HART_OWNER_KEY`) to
claim a namespace; then all writes to that owner require the key (else `403`). Anonymous (no-owner)
artifacts get a random id. Free to create new stuff; your namespace stays yours.

## Command surface (agent-first)

Every command prints **JSON on stdout**, structured errors on **stderr**, and uses **semantic exit
codes** (`0` ok · `80–89` input · `90–99` resource · `100–109` integration · `110–119` internal).
Non-interactive and idempotent. `hart guide` prints the full manual.

| Command | Does |
|---|---|
| `publish <file> [--owner --artifact --title --format html\|jsx --visibility --read-key --unguessable --dry-run --force]` | upload → `{id,url,version}` |
| `data <id> '<json>'` | update the live data — template re-renders |
| `visibility <id> <unlisted\|public\|private> [--read-key --clear-read-key]` | change visibility |
| `versions <id>` / `rollback <id> <v>` | history / instant revert |
| `list [--owner <who>]` / `get <id>` / `rm <id>` | manage artifacts |
| `stats <id>` | living-deliverable analytics — views, last view, freshness, top referrers (server-side, CSP-safe) |
| `fresh <id> <30s\|15m\|2h\|1d\|off>` / `stale [--owner <who>] [--older-than <dur>]` | freshness SLA + the staleness signal (JSON; your agent alerts) |
| `explore [query]` | public discovery feed (JSON) |
| `admin owners` / `admin list [--owner <who>]` | operator cross-owner visibility (needs `HART_ADMIN_TOKEN`) |
| `serve [port]` | run the hosting daemon |
| `mcp` | run as a stdio MCP server (native tools for MCP-capable agents) |
| `login <token>` / `guide` / `skill` | store creds / print the manual / print a drop-in agent SKILL.md |

### MCP (native tools for MCP-capable agents)

Besides the CLI + the drop-in skill, hart can run as a **stdio MCP server** so MCP-native agents
(Claude Desktop, Cursor, …) get hart as first-class tools — one binary, no extra runtime. It wraps
hart's own HTTP API and inherits auth from env. Configure your MCP client:

```json
{"mcpServers":{"hart":{"command":"hart","args":["mcp"],"env":{"HART_URL":"https://hart.intrane.fr"}}}}
```

Tools: `hart_publish`, `hart_data`, `hart_list`, `hart_get`, `hart_stats`, `hart_stale`,
`hart_explore`. The CLI stays the primary interface; MCP is an additional surface.

## Admin — operator visibility (an instance you host)

Running an instance others also use, but want to audit every artifact **your** agents/operators
produced on your box? Set `HART_ADMIN_TOKEN` on the daemon — a god-token **separate** from
`HART_TOKEN` (a publish token never grants admin). Then, from any operator machine:

```sh
export HART_ADMIN_TOKEN=<secret>        # or: hart admin login <secret>
hart admin owners                       # → [{owner, artifacts, bytes, has_owner_key, updated}, …]
hart admin list [--owner <who>]         # → [{id, owner, url, visibility, has_read_key, version, updated}, …]
hart admin mv <old-id> <new-owner/new-name>   # move/rename in place — keeps version history + read-key
```

`admin mv` renames an artifact and **all its versions** to a new owner/name — history, visibility,
live data, and read-key are preserved (nothing re-uploaded); the old URL 404s. e.g. `hart admin mv
am/fleet-monitor intrane/am-fleet-monitor`.

Owner-keys and read-keys are stored **hashed**, so admin surfaces `has_owner_key` / `has_read_key`
booleans — never the secret (to enter a private artifact, reset its key with `hart visibility <id>
private --read-key <new>`). With `HART_ADMIN_TOKEN` unset the admin API is **off** (`403`), and on
such multi-tenant instances a cross-owner `hart list` (no `--owner`) is admin-only — owner-scoped
`list --owner X` is unaffected. It's your box and your SQLite file; this just exposes that reach
over the CLI.

**Env** — client: `HART_URL`, `HART_TOKEN` (publish token, if the instance requires one),
`HART_OWNER_KEY` (namespace write key), `HART_READ_KEY` (read a private artifact),
`HART_ADMIN_TOKEN` (operator admin API — cross-owner list; separate from `HART_TOKEN`). Server:
`HART_DB`, `HART_RUNTIME_DIR`, `HART_PUBLIC`, `HART_LANDING`, `HART_MAX_SUBMITS_PER_MIN` (10),
`HART_MAX_OWNER_MB` (30), `HART_EXPLORE=0`, `HART_COOKIE_SECRET`.

**Production hardening** — auto-enabled when `HART_PUBLIC` is set (or force with `HART_HARDEN=1`):
`HART_TRUST_PROXY`, `HART_MAX_BODY_BYTES`, `HART_READ_TIMEOUT_MS`, `HART_ACCESS_LOG`. Opt out
locally with `HART_HARDEN=0`. Full BYOK setup: [`docs/BYOK.md`](docs/BYOK.md).

## Architecture

```
  ┌──────────────┐   publish/data/visibility (HTTP)   ┌──────────────────────────────┐
  │  any agent   │ ─────────────────────────────────► │  hart serve  (one MFL binary)│
  │  hart <cmd>  │ ◄─────────  {id,url,version}  ───── │  ─ machweb HTTP server        │
  └──────────────┘                                     │  ─ SQLite store (artifacts,   │
                                                       │      versions, owners)        │
   browser ── GET ─►  /a/<owner>/<artifact>  ─────────►│  ─ doctype-wrap + strict CSP  │
             (default-deny CSP; private = unlock page) │  ─ same-origin JSX runtime    │
                                                       └──────────────────────────────┘
```

- **One binary, two roles.** `hart <cmd>` is the client; `hart serve` is the daemon (same
  `machin-backend` idioms: `machweb` router, `sqlite` store, signed cookies).
- **Storage is a single SQLite file** (`HART_DB`) — zero-dep, one file to back up.
- **Sandbox.** Every artifact is served under a default-deny CSP; a hostile page can't reach the
  network or external hosts. Signed-cookie unlock gates private artifacts.

## Build & verify

```sh
machin encode framework/machweb.src src/hart.src > build/hart.mfl
machin build build/hart.mfl -o hart
```

`machin encode` runs the typechecker (most errors surface without a C compiler). Verify by
publishing a fixture and `curl`-ing the artifact URL: it must render, and an inline `fetch()` to
any host must be blocked by the CSP.

## Positioning

**The agent-first artifact host.** Not a Netlify (human-first PaaS), not a Pastebin (no rendering,
no safety) — the **publish primitive for the agent era**. Any terminal agent, any infra, one CLI
call from HTML to URL. See [VISION.md](VISION.md) and the running [ROADMAP.md](ROADMAP.md).

## Status & license

**Live and shipped:** publish (HTML/JSX) · versioning + rollback · CSP sandbox + linter · template
+ data · visibility (unlisted/public/private, gated read) · discovery (`/explore`, `/o/<owner>`) ·
owner-claim keys · rate limits · `hart guide` / `/llms.txt`. Open-source, self-hosted — not a
hosted service. License: TBD at first tagged release (MIT/Apache-2.0).
