# AGENTS.md — working on machin-hart

hart (HTML ARTifacts) is an agent-first artifact host: one MFL binary = CLI + daemon. This file
orients agents contributing to **this repo** — not the drop-in skill agents install at runtime
(see `hart skill` / `/skill.md`).

## 30-second orientation

| Doc | Purpose |
|---|---|
| [`llms.txt`](llms.txt) | Publish quickstart, CSP rules, agent-setup paths, doc map |
| [`docs/BYOK.md`](docs/BYOK.md) | BYOK key map, which-keys table, systemd layout, post-deploy checks (also `/byok.md`) |
| [`CONTRACT.md`](CONTRACT.md) | Publish contract — self-contained HTML, CSP sandbox |
| `hart guide` / `/guide.md` | Version-exact command reference on any running instance |

## Publish / BYOK / agent setup

**Publish flow:** build a self-contained HTML (or JSX) file → `hart publish file.html --owner O
--artifact A` (or curl POST to `/v1/publish`) → parse JSON `{url, version, …}` → hand the URL to
the human.

**Integration paths** (same env vars for all):

1. **curl** — no binary; POST the file body.
2. **CLI** — `<instance>/install.sh` or build from source; `HART_URL` points at the daemon.
3. **Skill** — `hart skill` writes a drop-in SKILL.md; craft-aware variant lives at
   [`.agents/skills/hart-artifact-design/SKILL.md`](.agents/skills/hart-artifact-design/SKILL.md).
4. **MCP** — `hart mcp` (stdio); configure `HART_URL`, `HART_TOKEN`, `HART_OWNER_KEY` in the MCP
   client's env block.

**Keys (BYOK):** daemon env = operator knobs; client env = what agents carry. Open instances need
no token; locked-down boxes set `HART_TOKEN` on the daemon and `hart login` on clients. Namespace
write protection uses `--owner-key` / `HART_OWNER_KEY`. See the **Which keys do I need?** table in
[`docs/BYOK.md`](docs/BYOK.md).

## Build & verify

```sh
./build.sh && ./test.sh   # full regression suite (~165 checks)
```

Needs `machin` on PATH. `./runtime/fetch.sh` seeds the JSX runtime before first build.

## Doc-only changes

Smoke doc PRs should touch markdown only: `README.md`, `docs/`, `llms.txt`, `AGENTS.md`. Do not
refactor MFL sources or binaries in doc-only tasks. Note: `/llms.txt` on a running instance is
generated from `src/hart.src`; the repo copy is for GitHub browsing — keep them aligned when you
can, but doc-only PRs must not change code.

## Config loading (added 2026-07)

CLI commands (everything except `hart serve`) auto-load `~/.hart/config` then `.hart.env` from the
current working directory. Precedence: CLI flag > environment variable > `.hart.env` >
`~/.hart/config`. Use these files to avoid repeating `HART_URL`, `HART_OWNER_KEY`, etc.

Multiple namespaces/artifacts can share one flat file with the flat-key form:
`HART_OWNER_KEY_<owner>` and `HART_READ_KEY_<owner>_<artifact>` (non-alnum/slashes become `_`).

`hart serve` ignores these files and reads env from systemd/operator config so the daemon cannot
be hijacked by a `.hart.env` in the cwd.

## Architecture note

`src/hart.src` is a single MFL source that `build.sh` concatenates with other `.src` files into
`build/hart.mfl`. This repo intentionally keeps the core logic in one MFL file; the global
500-LOC modularity rule does not apply here because `machin build` and the project's single-binary
design expect a single main source.
