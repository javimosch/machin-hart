# hart — Roadmap

Built in **MFL / [machin](https://github.com/javimosch/machin)** — one static binary that is CLI
*and* daemon (see the `machin-backend` skill: `machweb` HTTP server, `sqlite` store, signed
sessions, the agent-first CLI contract). Phases are shippable and ordered so each proves the next
is worth building. Dogfood target: replace the ad-hoc "write HTML to scratchpad" step every agent
already does with `hart publish`.

Legend: 🎯 goal · 📦 deliverable · ✅ done-when.

---

## M0 — Spike: HTML → URL, once ✅ DONE (2026-07-06)

🎯 Prove the core loop end to end with the crudest possible version.
- 📦 `hart publish <file.html>` → POST bytes to a local `hart serve` daemon → returns
  `{ok,id,url}`. Daemon stores the blob in SQLite, serves it at `/a/<id>` wrapped in the doctype
  skeleton + a hardcoded strict CSP.
- 📦 Open the URL in a browser; the page renders; an external `fetch()` inside it is blocked.
- ✅ One command turns a local HTML file into a working, sandboxed hosted URL.

## M1 — The publish contract + CLI MVP

🎯 A real, stable, agent-first client and a safe render envelope.
- 📦 **Publish contract v1** (documented in `CONTRACT.md`): self-contained HTML only — inline all
  CSS/JS, embed assets as `data:` URIs; the daemon injects `<!doctype>…<head>`(title, favicon,
  viewport, CSP)`…<body>`. Publish-time linter rejects/►warns on external `src`/`href`/`@import`,
  `connect-src` usage, `<script src>` to a CDN. Same envelope that wraps Claude artifacts.
- 📦 **CSP + origin isolation**: `default-src 'none'; img-src data:; style-src 'unsafe-inline';
  font-src data:; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'`. Artifacts
  served from a **dedicated artifact origin** distinct from the control-plane API origin, so a
  hostile artifact can't touch API cookies. `X-Frame-Options`, `X-Content-Type-Options`, no
  referrer.
- 📦 **CLI contract** (agent-first): `publish` `list` `get` `update` `rm` `open` `help-json`.
  JSON on stdout, structured errors on stderr, exit codes `0 / 80–89 input / 90–99 resource /
  100–109 integration / 110–119 internal`. Env: `HART_URL`, `HART_TOKEN`. Non-interactive,
  idempotent (`--slug` ⇒ stable id).
- 📦 **Auth**: `hart login <token>` / server `hart grant <email>`; signed sessions
  (`machweb` `set_session`), per-account token.
- ✅ Any agent can `hart publish x.html` and get a stable URL; re-publishing a slug updates in
  place; a malicious page is inert.

## M2 — Versioning, access control, custom domains

🎯 Make it durable and shareable the way a deliverable needs to be.
- 📦 **Content-addressed versioning**: every publish stores a new immutable blob; `hart versions
  <id>`, `hart rollback <id> <v>`. `latest` pointer per artifact.
- 📦 **Access control**: `--private` (token-gated), `--unlisted` (unguessable id, default),
  `--public` (listed in the gallery). Per-artifact ACL, changeable via `hart share <id> <mode>`.
- 📦 **Custom domains**: `hart domain <id> <sub.you.dev>` → wires Cloudflare DNS + Traefik + Let's
  Encrypt via the existing [hotify-cli](https://github.com/javimosch/hotify-cli) pattern (proven
  on dk1). Vanity artifact URLs on the user's own domain.
- 📦 **Storage backends (BYOK)**: pluggable blob store — `local` FS, `sqlite` (embedded), and
  BYO **S3-compatible** (creds via env). `hart serve --store s3://…`.
- ✅ An artifact has a stable URL, a version history with one-command rollback, an access mode,
  and can live on the user's own domain and storage.

## M3 — Hosted tier + billing (the micro-SaaS)

🎯 Sell "not having to run it" without ever selling commodity infra.
- 📦 **Thin hosted control plane** (mirrors grepapi on dk1): managed daemon, BYO storage/domain.
- 📦 **Stripe billing**: free tier (N artifacts, unlisted-only, hart-subdomain); Pro flat monthly
  (custom domains, private/auth artifacts, higher limits, version retention, analytics). Same
  `metadata`-tagged checkout + webhook pattern grepapi uses.
- 📦 **Usage/limits**: per-account artifact count, storage bytes, bandwidth surfaced in
  `hart usage`. Bandwidth is the only metered dimension (the one real variable cost); everything
  else flat.
- 📦 **Landing + guide**: `hart guide` (in-binary, version-exact agent skill) + a self-serve
  install (`curl … | sh`) that drops the CLI + a one-liner to point it at the hosted control
  plane or a self-host.
- ✅ A stranger can `hart upgrade`, publish to their own domain on their own bucket, and be
  billed a flat, predictable price.

## M4 — Agent-native distribution + observability

🎯 Make `hart` the *reflexive* place agents publish, and give both sides trust.
- 📦 **Agent integration kit**: a drop-in skill / tool spec ("after generating a shareable HTML
  deliverable, `hart publish` it and return the URL"), plus an **MCP server** wrapping the CLI so
  MCP-capable agents get `publish/update/list` as native tools. Ship adapters/snippets for Claude
  Code, Cursor, aider, Codex CLI, Gemini CLI.
- 📦 **Read-only dashboard** (isomorphic, same binary via `machweb` + wasm, the [[machin-vault]]
  pattern): a gallery of your artifacts, versions, view counts — a courtesy on top of the API,
  never the source of truth.
- 📦 **Lightweight analytics**: privacy-respecting view counts / referrers per artifact
  (`hart stats <id>`), no third-party trackers (would violate the CSP anyway).
- 📦 **Publish-time preview + diff**: `hart publish --dry-run` returns the wrapped HTML + a CSP
  lint report; `hart diff <id>` shows what changed vs live.
- ✅ Agents publish to `hart` by default across runtimes; users can see and trust what's live.

## M5 — Hardening & scale (ongoing)

- 📦 **Abuse & safety**: rate limits, phishing/malware heuristics on publish (a hosted artifact
  host is a phishing target — this is non-optional for the hosted tier), takedown tooling,
  per-account quotas, content hashing against known-bad.
- 📦 **Big-payload robustness**: chunked/streamed uploads for large inlined assets; size caps with
  clear errors (learn from grepapi's large-submit timeout — batch/stream, never silently drop).
- 📦 **Edge caching / TTL**, artifact expiry (`--ttl`), ephemeral one-view links.
- 📦 **Team accounts**, shared namespaces, audit log.

---

## Open questions for the building agent

1. **Name/brand.** `hart` (HTML ARTifact) is the working name; the CLI is `hart`, repo
   `html-artifact` (could become `machin-hart` for the awesome-machin list). Confirm or rename
   before M1 — it's load-bearing across the CLI, domains, and docs.
2. **Interactivity boundary.** M0–M1 allow inline `<script>` (needed for real dashboards like the
   call-budget sheet). Decide the exact JS policy: inline-only is the default; consider a
   stricter `--static` (no JS) mode for maximum-trust artifacts, and whether to offer a *looser*
   opt-in origin for `connect-src` (BYO API) behind an explicit, per-artifact flag — it widens
   the attack surface, so default deny.
3. **Storage default.** SQLite-embedded (zero-dep, one file) vs local-FS vs forcing BYO-S3 from
   day one. Recommend SQLite for self-host simplicity, S3 for the hosted tier.
4. **Multi-origin isolation on one host.** Serving artifacts from a distinct origin while the API
   is on another — subdomain-per-artifact (`<id>.a.host`) is safest (true origin isolation) but
   needs wildcard TLS; path-based (`a.host/<id>`) is simpler but weaker. Recommend wildcard
   subdomain for the hosted tier, path-based acceptable for self-host.
5. **Where the CSP lives.** Injected by the daemon at serve time (authoritative) vs baked at
   publish time. Recommend serve-time injection so policy can tighten without re-publishing.

## Suggested first commit for the next agent

`M0` in one file: `src/hart.src` with a `serve` subcommand (`machweb` daemon, SQLite blob store,
CSP-wrapped `/a/<id>`) and a `publish` subcommand (POST a file, print `{url}`). Prove the loop,
then grow into M1's contract + CLI surface. Read the `machin-backend` skill first; vendor
`framework/machweb.src`.

---

## Founder notes (2026-07-06)

Two directives folded in, pulled earlier than their original milestone:

1. **Versioning from M0, not M2.** Every publish to the same id mints the next version —
   `v1, v2, v3, …` — and **`latest` always resolves to the newest**. URLs:
   `/a/<id>` and `/a/<id>/latest` → newest; `/a/<id>/v<n>` → pinned. So an agent's workflow is
   *create once, then submit updates*: `hart publish x.html` (→ v1) then `hart publish --id <id>
   x.html` (→ v2, latest moves). Rollback = re-point latest at an older version. M0 ships this.

2. **JSX as a first-class source format.** Agents author React/JSX, not just raw HTML.
   `hart publish app.jsx --format jsx` → the daemon transpiles+wraps into a self-contained,
   CSP-safe page (inline runtime, no CDN). M0 stores `format` on every version and serves HTML
   verbatim; **JSX transpile lands in M1** (the transpiler is the load-bearing piece — likely a
   vendored inline Babel-standalone-equivalent or a minimal JSX→JS pass, TBD in the open
   questions). The contract is: *source in (html|jsx) → self-contained sandboxed page out*.

---

## M0 status — SHIPPED (2026-07-06)

`src/hart.src` (one MFL binary, vendors `framework/machweb.src`) proves the full loop:
- `hart serve [port]` — machweb daemon; SQLite store (`artifacts` + immutable `versions`).
- `hart publish <file> [--id --title --format]` — POSTs raw HTML (body, no JSON-escaping) →
  `{id, version, url, latest_url, pinned_url}`. New id → v1; `--id <existing>` → next version.
- Serving: `GET /a/<id>` & `/a/<id>/latest` → newest; `GET /a/<id>/v<n>` → **immutable pin**
  (verified: v1 keeps its own content+title after v2 publishes). Wrapped in a doctype skeleton +
  strict **CSP** (`default-src 'none'`, no external anything, `connect-src` absent ⇒ no fetch),
  plus `X-Content-Type-Options`/`X-Frame-Options`/`Referrer-Policy`.
- `hart list`, `hart versions <id>`, `hart help` — agent-first JSON.
- **Versioning (v1/v2/v3/latest) is live** per the founder note; **JSX** is stored as a `format`
  (transpile deferred to M1). Built + tested end to end (published the €5 call-budget sheet,
  updated it to v2, confirmed latest moved and v1 stayed pinned).

**Known M0 limitations (for M1):** returned URL omits the port when published via the MFL HTTP
client (sends `Host` sans port) — set `HART_PUBLIC` for canonical URLs; no auth yet (publish is
open — add `HART_TOKEN` gate in M1); no publish-time CSP linter yet; JSX not transpiled.

---

## M1 status — auth + linter + CLI SHIPPED, JSX pending (2026-07-06)

Done + tested end to end:
- **Auth + per-account isolation** — `accounts`/`tokens` tables; `hart grant <email>` (admin,
  direct DB → account+token); `hart login <token>` (→ ~/.hart-token); publish/list/versions/rm
  require a bearer token and are scoped to the account. `HART_OPEN=1` = single-user no-auth
  self-host mode. Cross-account id reuse → 403.
- **Publish contract + CSP linter** (`CONTRACT.md`) — `lint()` flags external script/css/import/
  asset + fetch/XHR/WebSocket; **errors block (422) unless `--force`**; `--dry-run` returns
  `{would_block,lint}` without storing. Verified: clean page passes, `fetch()`+external `<script
  src>` blocks, `--force` overrides.
- **CLI surface** — `serve grant login publish get list versions rm help` (agent-first JSON,
  semantic exit codes, `HART_URL`/`HART_TOKEN`, idempotent `--id`).

M1 COMPLETE:
- **JSX transpile SHIPPED** — `--format jsx` → the daemon serves a same-origin runtime
  (`/_hart/runtime/{react,react-dom,babel}.js` from `HART_RUNTIME_DIR`; `runtime/fetch.sh` seeds
  them) + a JSX CSP (`script-src 'self' …`). Transform uses Babel's **classic runtime** (emits
  React.createElement — automatic runtime's `import` fails outside a module) via a bootstrap that
  evals the compiled code. **Verified with a headless render** (a useState counter mounted +
  computed). Path-traversal guarded.
- **Origin isolation** — serve artifacts from a dedicated origin (deploy-time; pairs with M3 hosting).
- **Signed sessions** — M1 uses opaque bearer tokens; `machweb set_session` cookies optional later.

---

## M2 scope decisions (2026-07-06, founder)

- **Rollback ✅ SHIPPED** — `hart rollback <id> <version>` re-points `latest` at an existing
  older version; non-destructive (versions stay immutable, next publish still appends MAX+1).
  Fixed the latent bug where `next = latest+1` would collide after a rollback (now MAX+1).
- **Custom domains — DEFERRED ("too soon").** Relative same-origin URLs (`/a/<id>`) under the one
  `hart.intrane.fr` (or a self-hoster's own domain via HART_PUBLIC) are far enough for now.
- **MCP — REJECTED.** We ship a **CLI** like grepapi — that *is* the agent interface. An
  agent-first CLI (JSON I/O, exit codes, composable) beats an MCP server; no MCP.
- **BYO-S3 — NOTED FOR LATER (not now).** Idea parked: let a hosted/self-host deployment back the
  blob store with the operator's own S3 bucket instead of SQLite, for durability/scale. Revisit
  when artifact volume or the hosted tier (M3) needs it.

**So M2 = rollback (done).** Next real work is **M3** (hosted tier + Stripe = the micro-SaaS)
when there's demand; until then hart is a complete, self-hostable, live agent-first artifact host.
