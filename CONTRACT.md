# The hart publish contract (v1)

hart hosts **finished, self-contained pages**. You submit body content; the daemon wraps it in a
`<!doctype>…<head>…</head><body>…</body>` skeleton and serves it under a strict, sandboxed CSP on
a dedicated artifact origin. This is the same envelope that wraps Claude's own artifacts: it
renders the page while neutering it as an attack or exfiltration vector.

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
no-referrer`. **Origin isolation** (M1→M2): artifacts are served from a **dedicated origin**
(e.g. `a.hart.host`), distinct from the control-plane API origin, so a hostile artifact can't
reach API cookies or same-origin API routes.

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

*(The M1 linter is a cheap substring scan — good enough to catch the common cases and teach the
contract. A DOM-accurate pass is a later hardening step.)*

## Versioning

Every publish to the same `--id` mints the next version; `latest` always tracks the newest.
- `/a/<id>` and `/a/<id>/latest` → newest
- `/a/<id>/v<n>` → **immutable pin** (content + title frozen at that version)

Workflow: `hart publish x.html` (→ v1, new id) → `hart publish --id <id> x.html` (→ v2). Rollback
(M2) re-points `latest` at an older version.

## JSX (planned — M1 tail)

`hart publish app.jsx --format jsx` — author React/JSX, not just raw HTML. Every version already
stores its `format`; the transpile is the remaining piece.

**Decision:** transpile in the browser, self-hosted (no CDN). The JSX wrapper loads a small
**same-origin** runtime the hart deployment serves — `/_hart/runtime/{react,babel}.js` — and the
page's JSX runs through `Babel.transform` at load. This keeps pages small (the runtime is cached
per-origin, not embedded per-page) and stays within the sandbox: script-src gains `'self'` for the
runtime only, CSP already allows `'unsafe-eval'` for the transform. Server-side transpile is not
viable (no JS engine in MFL). Open sub-question: ship full `babel-standalone` (~1.5 MB, most
compatible) vs a minimal JSX→`h()` pass (tiny, but partial) — start with babel-standalone for
correctness, optimize later.
