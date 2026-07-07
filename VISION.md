# hart — Vision

> **Artifacts for every agent.** A terminal agent generates a self-contained HTML deliverable
> and gets back a live, shareable URL — from *any* agent, on *your* infrastructure, in one
> CLI call.

`hart` (HTML ARTifacts) is an agent-first, CLI-only micro-SaaS that publishes self-contained
HTML to hosted URLs. It is the **deliverable layer for terminal agents** — the thing Claude
Artifacts do inside claude.ai, unbundled and made universal: usable from Claude Code, Cursor,
aider, Codex CLI, Gemini CLI, Aider, OpenClaw, cron jobs, or a shell script. One static MFL
binary, fully **BYOK**, open-core, self-hostable.

---

## The problem

Terminal agents have learned to *produce* rich deliverables — dashboards, call sheets, run
reports, mockups, one-pagers, data explorers. But outside of claude.ai they have **nowhere to
put them**. The agent writes a beautiful `report.html` to disk and the human has to:

- `open` it locally (dies the moment they want to share it),
- paste it into a gist (loses styling, no rendering),
- spin up a static host / S3 bucket / Netlify by hand (not agent-operable), or
- copy-paste into a chat that mangles it.

The result: the deliverable never leaves the machine. The single most shareable output an agent
makes has the worst distribution story. **Claude solved this — for Claude.** Everyone else is
stuck. `hart` is the missing primitive: `hart publish report.html → https://…`, callable by any
agent, from any terminal.

## The wedge

**Agent-first, not human-first.** Every incumbent (Netlify, Vercel, GitHub Pages, S3+CloudFront,
even Claude Artifacts) is built for a *human* clicking a UI or wiring a CI pipeline. None expose
a clean, non-interactive, JSON-in/JSON-out contract an agent can call blind and parse. `hart` is
the opposite: the **primary user is a program**. JSON on stdout, structured errors on stderr,
semantic exit codes, a `guide` command that prints the version-exact manual, deterministic idempotent publishes. No UI
tax. That's the same unserved seam [[grepapi]] found for search and [[crm-cli]] found for CRM.

**The hard part is the moat: safely hosting untrusted, agent-generated HTML.** Anyone can `scp`
a file to nginx. The value is doing it *safely and repeatably*: a strict, sandboxed
Content-Security-Policy that renders the page but neuters it as an attack or exfiltration vector;
isolation of the artifact origin from the control-plane origin; a stable publish contract
(inline-only, CSP-safe) that agents can target every time; content-addressed versioning with
instant rollback; and access control (private / unlisted / public). That security envelope —
identical in spirit to the CSP that wraps Claude's own artifacts — is the product.

## What it is (and isn't)

**It is:** a publish contract + a hosting daemon + an agent-first CLI. You point an agent at it,
the agent ships HTML, a URL comes back. Self-host it on your own box, or use a thin hosted
control plane. Bring your own storage and domain.

**It is not:** a web framework, a site builder, a CMS, or a general PaaS. It hosts *finished,
self-contained HTML artifacts* — one file, everything inlined, no build step, no server-side
runtime. If it needs a bundler or a backend, it's out of scope. That constraint is a feature:
it's what makes the security model tractable and the CLI a one-liner.

## The BYOK / open-core model (same playbook as grepapi)

`hart` sells the **brains**, never the commodity infra — so margins stay clean and trust stays high.

| Layer | Who provides it |
|---|---|
| **Storage** (blobs) | **You** — a single SQLite file today; a BYO S3-compatible bucket is a parked option |
| **Domain** (custom vanity URL) | **You** — bring a domain + reverse proxy |
| **Compute** | **You** for self-host; a thin control plane if a hosted tier ever ships |
| **The publish contract, CSP sandbox, versioning, template/data, visibility, CLI, gallery** | **hart** |

- **Self-host** (OSS core): `hart serve` → your own artifact host, single binary, your storage,
  zero per-artifact cost. Free forever.
- **Hosted** (convenience tier): we run the control plane; you BYO storage/domain. Flat monthly,
  usage-metered only where it must be (bandwidth), never a markup on someone else's commodity.

The economics mirror grepapi: a flat, predictable price for a *capability*, not a metered tax on
infra you could run yourself. That's what makes it fair, and what makes self-host a feature
rather than a threat.

## Why now

1. **Every agent runtime now generates HTML deliverables** and the number of non-Claude agents
   (Cursor, aider, Codex, Gemini CLI, OpenClaw, custom SDK agents) is exploding — a market Claude
   Artifacts structurally cannot serve because it's bound to claude.ai.
2. **Agents are the new integrators.** A tool whose interface is a clean CLI + JSON is instantly
   composable into any agent loop; a tool whose interface is a dashboard is not.
3. **The security envelope is genuinely hard**, which is exactly why a focused product wins over
   "just use S3" — the same reason grepapi beats "just scrape Google yourself."

## Positioning

> **The agent-first artifact host.** Any terminal agent, any infra, one CLI call from HTML to URL.

Not "a better Netlify" (that's human-first PaaS). Not "hosted Pastebin" (no rendering, no
safety). It's the **publish primitive for the agent era** — the counterpart to grepapi (find),
bland-cli (call), and crm-cli (remember) in an agent-first tool suite: `hart` is **show**.

## Design principles

- **Agent-first or nothing.** No feature ships unless an agent can drive it headless. The human
  dashboard is a read-only courtesy on top of the API, never the source of truth.
- **The publish contract is sacred.** One documented, stable target (self-contained HTML,
  inline-only, CSP-safe). Agents optimize against it; we never break it.
- **Safe by construction.** Untrusted HTML is sandboxed by a default-deny CSP and origin
  isolation *before* it's ever served. Security is not a setting.
- **BYOK, self-hostable, one binary.** No lock-in. The OSS core is the whole product; the hosted
  tier only sells not having to run it.
- **Boring, durable, legible.** Content-addressed blobs, versioned, rollback-able. An operator
  (human or agent) can always see exactly what's live and revert in one call.

## The north-star loop

```
  agent writes deliverable.html   ─┐
  hart publish deliverable.html    │  →  { "url": "https://a.host/x7f…", "version": 3 }
  agent hands the URL to the user ─┘
        …user edits request…
  hart update x7f deliverable.html →  same URL, new version, instant rollback available
```

When that loop is one CLI call on every agent runtime, `hart` is the default way agents ship
what they make.
