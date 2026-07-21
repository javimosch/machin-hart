---
name: hart-artifact-design
description: Design and publish a polished, self-contained HTML deliverable to a live hart URL (https://hart.intrane.fr) — pairs the artifact-design craft standard (deliberate palette/type/layout, no templated AI look) with hart's publish/versioning/visibility workflow. Use whenever the human wants a hart link (not a claude.ai artifact) for a report, briefing, dashboard, or one-pager, especially when the content should be password-gated or living/updatable.
---

# hart-artifact-design — designed HTML, published to hart

Two things this skill fuses:
1. **The craft bar** (from `artifact-design`): every deliverable — even a memo — gets a real design plan (palette, type pairing, layout concept) calibrated to how much visual investment the content actually calls for. No lorem, no generic AI-cliché look.
2. **The publish mechanics** (from `hart`): self-contained HTML, strict CSP, versioned URL, optional password gate, optional living/refreshable data.

Use this instead of the `Artifact` tool when the deliverable needs to live at a **hart URL** specifically — e.g. the human asked for hart by name, wants it password-gated for a third party without a claude.ai account, wants a `hart data`-refreshable dashboard, or wants it discoverable via `hart list`/`hart explore`.

## Step 1 — design plan (do this before writing HTML)

Read the request the way `artifact-design` does:
- **Calibrate treatment.** A memo, incident briefing, status report, or internal doc gets a *utilitarian* treatment: real typographic hierarchy, considered spacing, a proper (small) palette — not a giant hero, not flourishes. A landing page, demo, or something the recipient will want to keep/share gets an *editorial* treatment: a stronger point of view, one deliberate aesthetic risk, motion where it earns its keep.
- **Ground it in the subject.** Pin one concrete subject, its audience, and the page's single job. Pull distinctive choices from the subject's own vernacular (ops/infra doc → blueprint/schematic instincts; a product pitch → its category's visual language) — never the generic default.
- **Name the palette**: 4–6 hex values with a role each (background, surface, ink, accent, plus semantic colors like resolved/caution/critical if the content needs status signaling). Pick a neutral on purpose — don't default to pure grey or cream-serif-terracotta.
- **Pair type for 2+ roles**: a display face, a body face, a utility/mono face for data — via system font stacks (`Georgia`/`ui-serif`, `-apple-system`/`Segoe UI`, `ui-monospace`/`SF Mono`/`Consolas`) unless the piece justifies embedding a real display face as a `data:` URI `@font-face`. hart's CSP blocks font CDNs same as claude.ai artifacts — inline or use system stacks, never link out.
- **One-line layout concept.** State it before building.
- Avoid the AI-cliché cluster: warm cream + serif + terracotta, near-black + acid-green pop, centered everything, `rounded-lg` cards with an accent rail, emoji section markers.

Design **both color-scheme branches** (`prefers-color-scheme` + `:root[data-theme]` overrides) unless the piece deliberately commits to one visual world.

## Step 2 — build

Write the page as a normal self-contained HTML file (Write/Edit tool, local path — hart uploads it, it isn't inline content). Requirements from the hart publish contract:
- Inline **all** CSS/JS. No `<link>` to external stylesheets/fonts, no CDN script tags, no `fetch`/XHR/WebSocket calls (the CSP blocks them — `--force` can bypass the linter but never bypasses the runtime CSP, so don't rely on it).
- Embed any image/icon as a `data:` URI, or skip images and lean on typography/layout/CSS shapes instead.
- No `<!DOCTYPE>`/`<html>`/`<head>`/`<body>` wrapper needed for the *page content* if you're handing hart the same body-only file style used for claude.ai artifacts — but hart does **not** auto-wrap the way the `Artifact` tool does, so for hart write a **complete HTML document** (`<!doctype html><html><head><meta charset><title>…</title><style>…</style></head><body>…</body></html>`) unless you've confirmed this hart instance auto-skeletons bare bodies. When unsure, ship the full document — it's always valid input.
- `text-wrap: balance` on headings, ~65ch measure on body copy, `font-variant-numeric: tabular-nums` on any column of digits, `overflow-x: auto` on wide tables/code, layout spacing via flex/grid `gap` not stacked margins.

## Step 3 — publish

```sh
export HART_URL=https://hart.intrane.fr   # once per session
```

No `hart` binary on PATH (check with `which hart`) → publish via curl, same contract:

```sh
curl -s -X POST 'https://hart.intrane.fr/v1/publish?owner=<owner>&artifact=<slug>&visibility=<unlisted|public|private>&read_key=<password>' \
  -H 'content-type: text/html' --data-binary @deliverable.html
```
(If the CLI is present, prefer it: `hart publish deliverable.html --owner <owner> --artifact <slug> --visibility private --read-key <password>`.)

- **Owner**: a stable namespace for this human/team/project — reuse it across related artifacts so `hart list --owner <owner>` collects them. First write to a fresh owner claims it (free instance, no `--owner-key` needed unless the human wants write-protection).
- **Slug**: kebab-case, stable across re-publishes of the *same* deliverable — re-publishing the same owner/artifact appends a version and moves `latest`; a new slug mints a new URL.
- **Visibility**: default `unlisted` (public-read, not listed) for most work. Use `private` + `--read-key <password>` whenever the human gives you a password/pass-phrase, or the content is sensitive (credentials-adjacent infra detail, internal incident data, anything not meant for an open link). `public` only if the human wants it discoverable at `/explore`.
- Report back the returned `.url` (and the read-key/password separately if private, since it's not embedded in the link) — don't fabricate a URL if the publish call fails; surface the error instead.

## Living updates (optional)

If the deliverable is a dashboard/status page meant to stay current rather than a one-off report, publish it once as a template reading `{{key}}` placeholders or `window.HART_DATA`, then push fresh data with `hart data <owner>/<slug> '<json>'` on subsequent updates — same URL, no re-publish. Pair with `hart fresh <id> <ttl>` if a cron/agent is expected to keep it current, so staleness is detectable (`hart stale`).

## Quick reference

| Need | Command |
|---|---|
| Publish | `hart publish file.html --owner O --artifact A [--visibility private --read-key P]` |
| No CLI | `curl -X POST '.../v1/publish?owner=O&artifact=A' -H 'content-type: text/html' --data-binary @file.html` |
| Update data only | `hart data O/A '<json>'` |
| Change visibility later | `hart visibility O/A private --read-key P` |
| List mine | `hart list --owner O` |
| Full manual | `hart guide` / `curl https://hart.intrane.fr/guide.md` |

## Build & publish caveats from usage

- When converting Markdown to hart HTML, use `pandoc --embed-resources --standalone --css style.css -f markdown-yaml_metadata_block --metadata title="..."`. The `-f markdown-yaml_metadata_block` switch is required when the source has an email-style frontmatter with colons (e.g. `Asunto: foo: bar`).
- Re-publishing the same `owner/artifact` updates `latest`; old versions remain at `/v<n>`.
- To move an artifact to a new owner: publish under the new owner, update source links, re-publish to refresh `latest`, then delete the old artifact with `curl -s -X DELETE 'https://hart.intrane.fr/v1/artifacts/<old-owner>/<artifact>'`.
- Hart's CSP blocks external fonts/CDNs; use system font stacks or inline `data:` URI `@font-face` only.

> **Agent self-improvement note:** After each hart-artifact-design session, if you find a new build/publish caveat, design shortcut, or lint gotcha, append a concise bullet to this "Build & publish caveats from usage" section and to any in-repo `.devin/skills/hart/SKILL.md` or `.agents/skills/hart/SKILL.md` if it exists. Keep it factual and non-duplicative.
