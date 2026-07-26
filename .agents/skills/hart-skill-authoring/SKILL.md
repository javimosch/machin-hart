---
name: hart-skill-authoring
description: Publish agent skills as minimal, discoverable hart HTML artifacts using meta title/description/keywords.
---

# hart Skill Authoring

Publish agent skills as hart artifacts so they are versioned, gated, and discoverable.

## When to use

- The skill is a runbook, recipe, or one-shot fix.
- You want a stable URL, versioning, or password gating.
- The skill does not need a fancy report/dashboard layout.

## Artifact format

A hart skill is a plain HTML file with no CSS, no external resources, and a semantic body.

Required `<head>`:

```html
<meta charset="utf-8">
<meta name="title" content="Skill title">
<meta name="description" content="One-line description">
<meta name="keywords" content="foo, bar, baz">
<title>Skill title</title>
```

Required structure:

- `<!doctype html>`, `<html>`, `<head>`, `<body>`.
- `<h1>` for the title.
- `<h2>` for sections.
- `<ul>` / `<ol>` for lists.
- `<pre><code>` for commands.
- No `<style>`, no `<link>`, no `<script>`, no images, no external URLs.

Keep the whole file under 200 lines.

## Minimal template

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="title" content="Fix X">
  <meta name="description" content="Recover from X by doing Y">
  <meta name="keywords" content="x, y, z">
  <title>Fix X</title>
</head>
<body>
  <h1>Fix X</h1>
  <p>One-line trigger.</p>

  <h2>Prerequisites</h2>
  <ul>
    <li>Thing 1</li>
  </ul>

  <h2>Steps</h2>
  <pre><code>command one
command two</code></pre>

  <h2>Verify</h2>
  <pre><code>verify command</code></pre>
</body>
</html>
```

## Publish

```bash
hart publish fix-x.html \
  --owner jar-skills \
  --artifact fix-x \
  --title "Fix X" \
  --visibility private \
  --read-key gtf \
  --tags x,y,z \
  --meta '{"trigger":"claude failed with X","verified":true}'
```

Use `--visibility unlisted` if no password is needed.

## Verify

```bash
wc -l fix-x.html          # should be < 200
hart publish fix-x.html --dry-run
hart list --owner jar-skills --format skills  # confirm the skill appears in the catalog
claude -p "read https://hart.intrane.fr/a/jar-skills/fix-x and follow it"
```

## Notes

- Description/keywords are read from `<meta>` tags and exposed automatically in `hart list --owner <who> --format skills` and `GET /v1/skills/<owner>`.
- For password-gated skills, agents fetch with `X-Hart-Read-Key: <password>` or `HART_READ_KEY`.
- Re-publish the same `--owner/--artifact` to version the skill.
