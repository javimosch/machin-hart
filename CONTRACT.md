# The hart publish contract

hart hosts **finished, self-contained pages**. You submit body content; the daemon wraps it in a
`<!doctype>…<head>…</head><body>…</body>` skeleton and serves it under a strict, sandboxed CSP.
This is the same envelope that wraps Claude's own artifacts: it renders the page while neutering
it as an attack or exfiltration vector.

## What you submit

- **One file, everything inlined.** Write the page content directly — no `<!doctype>`, `<html>`,
  `<head>`, or `<body>` wrapper (hart injects those). A leading `<title>` / `<style>` / `<script>`
  is fine (artifact convention).
- **Inline all CSS and JS.** Embed images/fonts as `data:` URIs.
- **No network.** `fetch` / `XMLHttpRequest` / `WebSocket` are blocked by CSP (`connect-src`
  absent ⇒ `default-src 'none'`).

## The CSP (served on every artifact)

```
default-src 'none';
img-src data: blob:; media-src data: blob:; font-src data:;
style-src 'unsafe-inline'; script-src 'unsafe-inline' 'unsafe-eval';
base-uri 'none'; form-action 'none'; frame-ancestors 'self'
```

Plus `X-Content-Type-Options: nosniff`, `X-Frame-Options: SAMEORIGIN`, `Referrer-Policy:
no-referrer`. Private artifacts also get `Cache-Control: no-store`. JSX artifacts add `'self'` to
`script-src` (only) so the same-origin React/Babel runtime can load — still no external host, still
no network.

*(A future hardening step is serving artifacts from a dedicated origin distinct from the control-
plane API, so a hostile page can't reach same-origin API routes. Today both share one origin;
the default-deny CSP + no API cookies on the artifact path keep the blast radius small.)*

## Publish-time lint

`hart publish` runs the linter before storing. Findings are `{level, rule, note}`:

| Rule | Level | Trigger |
|---|---|---|
| `external-script` | **error** | `<script src="http…">` |
| `network-fetch` | **error** | `fetch(` |
| `network-xhr` | **error** | `XMLHttpRequest` |
| `network-ws` | **error** | `new WebSocket` |
| `external-css` | warn | `<link rel="stylesheet" href="http…">` |
| `external-import` | warn | `@import url(http…)` |
| `external-asset` | warn | `src="http…"` |

**Errors block publish** (HTTP 422) — inline the offending resource, or pass `--force` to publish
anyway (escape hatch; the page's external refs will simply fail under CSP). Warnings never block.
`hart publish --dry-run` returns `{would_block, lint}` and stores nothing, so an agent can
self-correct before shipping.

*(The linter is a cheap substring scan — good enough to catch the common cases and teach the
contract. A DOM-accurate pass is a later hardening step.)*

## Versioning

Every publish to the same artifact (`--owner/--artifact`, or `--id`) mints the next version;
`latest` always tracks the newest.
- `/a/<owner>/<artifact>` and `…/latest` → newest
- `…/v<n>` → **immutable pin** (content + title frozen at that version)

Workflow: `hart publish x.html --owner a --artifact p` (→ v1) → re-publish the same (→ v2).
`hart rollback <id> <v>` re-points `latest` at an older version (non-destructive; the next publish
still appends `MAX(version)+1`).

## Data (template + live data)

An artifact carries a mutable **data slot** separate from its versioned HTML. Publish a template
once; update the data with `hart data <id> '<json>'` and the page re-renders — no re-upload. The
data reaches the page two ways:

- **`{{key}}`** placeholders in the markup are substituted with top-level values.
- **`window.HART_DATA`** is injected as a JS global for scripts / JSX / charts to read.

Data is a pointer, not a version (updating it doesn't mint a new version).

## JSX

`hart publish app.jsx --format jsx` — author React/JSX. The daemon serves a **same-origin** runtime
(`/_hart/runtime/{react,react-dom,babel}.js`) and transpiles **in the browser** via
`Babel.transform` (classic runtime — the automatic runtime emits `import` statements that fail
outside a module). `React`/`ReactDOM` are globals; render into `#root`. Keeps pages small (runtime
cached per-origin) and inside the sandbox (`script-src` gains `'self'` for the runtime only,
`'unsafe-eval'` for the transform). No build step, no CDN.

## Visibility

Set with `--visibility` at publish (or `hart visibility <id> <mode>` later):

| Mode | Read | Listed |
|---|---|---|
| **unlisted** *(default)* | public (anyone with the URL) | no |
| **public** | public | yes — `/explore` and `/o/<owner>` |
| **private** | **gated** — password | no |

A **private** artifact requires a read key: a browser is shown a password **unlock page**
(`POST /a/<id>/unlock` → an HMAC-signed cookie), and an agent sends an **`X-Hart-Read-Key`** header.
Reads are otherwise always public (unlisted ≠ secret — the URL is just not advertised).

## Ownership

The first write to a new `--owner` claims the namespace. Pass `--owner-key <secret>` (header
`X-Hart-Owner-Key`) to claim it with a key; afterwards every write to that owner requires the key
(else `403`). This protects a namespace even on a free/tokenless instance.
