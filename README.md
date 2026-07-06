# hart — the agent-first artifact host

> Publish self-contained HTML to a live, shareable URL — from **any** terminal agent, on **your**
> infrastructure, in one CLI call. Claude Artifacts, unbundled and made universal.

`hart` (HTML ARTifacts) is an **agent-first, CLI-only** micro-SaaS built as one static
**MFL / [machin](https://github.com/javimosch/machin)** binary — it is both the client (`hart
publish …`) and the hosting daemon (`hart serve`). Fully **BYOK** (bring your own storage +
domain), open-core, self-hostable. It's the *show* to grepapi's *find*, bland-cli's *call*, and
crm-cli's *remember*.

> **Status: pre-M0.** This repo currently holds the design docs. See [VISION.md](VISION.md) and
> [ROADMAP.md](ROADMAP.md). The next agent implements M0 (see the bottom of the roadmap).

---

## Why

Terminal agents (Claude Code, Cursor, aider, Codex CLI, Gemini CLI, custom SDK agents, cron jobs)
now generate rich HTML deliverables — dashboards, reports, call sheets, mockups — but have
**nowhere to put them**. `open` dies at share-time; a gist mangles the styling; standing up S3 by
hand isn't agent-operable. Claude solved this *inside claude.ai*; everyone else is stuck. `hart`
is the missing primitive:

```
$ hart publish call-budget.html --title "€5 Call Budget"
{"ok":true,"id":"x7f3k","url":"https://a.hart.host/x7f3k","version":1,"mode":"unlisted"}
```

Any agent can call that, parse the JSON, and hand the URL to the user. No UI, no build step, no
lock-in.

## Quickstart (self-host)

```sh
# 1. build (needs `machin` on PATH; vendors framework/machweb.src)
./build.sh                       # → ./hart

# 2. run the host daemon (SQLite store, your box). Free/open by default; set HART_TOKEN to gate publishing.
HART_DB=~/.hart.db HART_RUNTIME_DIR=./runtime ./hart serve 8080 &

# 3. point the client at it (+ token only if the daemon set one)
export HART_URL=http://localhost:8080
# ./hart login <token>            # only if this instance requires a token

# 4. publish — owner + artifact = a stable, legible URL
./hart publish report.html --owner alice --artifact q3-report --title "Q3 report"
# → {"ok":true,"id":"alice/q3-report","url":"http://localhost:8080/a/alice/q3-report"}
./hart publish report.html --owner alice --artifact q3-report   # re-publish → v2, latest moves
```

For a public host, put `hart serve` behind Traefik + Cloudflare + Let's Encrypt with
[hotify-cli](https://github.com/javimosch/hotify-cli) (the pattern used across the stack), or use
the hosted control plane (M3).

## The publish contract

`hart` hosts **finished, self-contained HTML** — one file, everything inlined. The daemon wraps
your `<body>` content in a `<!doctype>…<head>` skeleton (title, favicon, viewport, CSP) and
serves it under a strict, sandboxed **Content-Security-Policy**:

- ✅ inline `<style>` / `<script>`, `data:` URIs for images/fonts, self-contained pages
- ❌ external `src`/`href` (CDN scripts, remote stylesheets, web fonts, remote images)
- ❌ `fetch` / `XHR` / WebSocket to any host (`connect-src 'none'` by default)

This is the same envelope that wraps Claude's own artifacts — it renders the page while neutering
it as an attack or exfiltration vector. `hart publish --dry-run` returns the wrapped output + a
CSP lint report so an agent can self-correct before shipping. Full spec: `CONTRACT.md` (M1).

## Command surface (agent-first)

Every command prints **JSON on stdout**, structured errors on **stderr**, and uses **semantic
exit codes** (`0` ok · `80–89` input · `90–99` resource · `100–109` integration · `110–119`
internal). Non-interactive and idempotent. `hart help-json` introspects the whole contract.

| Command | Does |
|---|---|
| `hart publish <file> [--owner <who>] [--artifact <name>] [--title --format html\|jsx] [--dry-run --force]` | upload → `{id,url,version}`. `owner`+`artifact` ⇒ stable id `owner/artifact`; re-publishing appends a version |
| `hart data <id> '<json>'` | update the artifact's live data — template re-renders (push just what changed) |
| `hart versions <id>` / `hart rollback <id> <v>` | history + instant revert (non-destructive) |
| `hart list [--owner <who>]` / `hart get <id>` / `hart rm <id>` | manage artifacts |
| `hart serve [port]` | run the hosting daemon |
| `hart login <token>` | store the client token in `~/.hart-token` |

URLs: `/a/<owner>/<artifact>` (or `/a/<id>`) → latest · `…/latest` · `…/v<n>` → immutable pin.
JSX (`--format jsx`) is transpiled in-browser via a same-origin React+Babel runtime the daemon
serves at `/_hart/runtime/*`.

Env: `HART_URL` (daemon), `HART_TOKEN` (a single **optional** static token — set it on the daemon
to require it for publishing, leave unset for a free/open instance; reads are always public),
`HART_DB`, `HART_RUNTIME_DIR`, `HART_PUBLIC`
(daemon storage, e.g. `s3://bucket`).

## Architecture

```
  ┌──────────────┐   publish/update (HTTPS, token)   ┌───────────────────────────┐
  │  any agent   │ ────────────────────────────────► │  hart serve  (MFL daemon) │
  │  hart <cmd>  │ ◄──────────  {id,url,version} ──── │  ─ machweb HTTP server    │
  └──────────────┘                                    │  ─ SQLite / S3 blob store │
                                                      │  ─ versioned, content-CAS │
   browser ── GET ─►  a.host/<id>  ── CSP-wrapped ───►│  ─ CSP + origin isolation │
   (isolated artifact origin, default-deny CSP)       └───────────────────────────┘
```

- **One binary, two roles.** `hart <cmd>` is the client; `hart serve` is the daemon (same
  `machin-backend` idioms: `machweb` router, `sqlite` store, signed sessions, pooled conns).
- **Storage is BYOK.** `local` FS, embedded `sqlite` blobs, or a BYO **S3-compatible** bucket.
- **Origin isolation.** Artifacts are served from a dedicated origin distinct from the API, so a
  hostile page can't reach control-plane cookies. (Wildcard subdomain per artifact for the hosted
  tier; path-based acceptable for self-host — see ROADMAP open questions.)
- **Custom domains** via the hotify-cli (Traefik + Cloudflare + Let's Encrypt) pattern.

## BYOK / open-core

The OSS core (`hart serve` + CLI) is the whole product — self-host it for free, your storage,
zero per-artifact cost. The **hosted tier** (M3) only sells not having to run it: flat monthly,
you still BYO storage + domain, and bandwidth is the sole metered dimension. Same fair,
predictable model as grepapi — a price for a *capability*, never a markup on commodity infra.

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
call from HTML to URL.

## For the next agent

Read [VISION.md](VISION.md) → [ROADMAP.md](ROADMAP.md) (start at **M0**), then the
`machin-backend` skill. First commit: `src/hart.src` with `serve` (machweb daemon + SQLite blob
store + CSP-wrapped `/a/<id>`) and `publish` (POST a file, print `{url}`). Prove the loop; grow
into the M1 contract + CLI. Resolve the five open questions at the end of ROADMAP.md before M1.

## License

Open-core. OSS core under a permissive license (TBD — MIT/Apache-2.0); hosted control plane is
the commercial layer. Confirm at first real release.
