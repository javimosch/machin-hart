# This app was scaffolded by machin-web-ui

An isomorphic machin app: one binary = CLI + HTTP server + reactive wasm UI,
styled by machin-web-ui's pure-MFL Tailwind engine. No Node.

- Build: `./build.sh` (needs `machin`, `zig`, `machin-web-ui` on PATH).
- Components you own live in `components/` — add more with `machin-web-ui add <name>`.
- Write Tailwind classes in any `.src`; `build.sh` regenerates `web/tw.css`.
- Rebrand via `theme.json` (semantic tokens); `machin-web-ui theme check theme.json`.

Operate the framework through the binary — it is the docs:

```
machin-web-ui guide        # verbs, contracts, gotchas, component catalog (JSON)
machin-web-ui list         # available components
machin-web-ui check <cls>  # does a class resolve?
machin-web-ui coverage     # implemented Tailwind surface
```

The five contracts and the gotchas (dynamic-class trap, peer-checked siblings,
label double-click) are in `machin-web-ui guide`. Full manual:
https://github.com/javimosch/machin-web-ui/blob/main/AGENTS.md
