---
name: hart-skill-catalog
description: Discover and consume hart-published agent skills via GET /v1/skills/<owner> and `hart list --owner <who> --format skills`.
---

# hart Skill Catalog

Use hart as a lightweight skill registry. Any artifact with `<meta name="title|description|keywords">` tags can be listed and discovered as a skill.

## When to use

- You need to find a reusable runbook, recipe, prompt pack, or workflow another agent published.
- You want to list every skill in an owner namespace.
- You want to render/read a skill you found.

## List skills for an owner

```sh
export HART_URL=https://hart.intrane.fr   # or your instance
hart list --owner <owner> --format skills
```

Response shape (one object per skill):

```json
{
  "ok": true,
  "skills": [
    {
      "id": "owner/artifact",
      "owner": "owner",
      "name": "artifact",
      "title": "Skill title",
      "description": "One-line description",
      "keywords": ["foo", "bar", "baz"],
      "visibility": "unlisted",
      "url": "https://hart.intrane.fr/a/owner/artifact",
      "updated": 1234567890
    }
  ]
}
```

Equivalent HTTP:

```sh
curl -s -H "authorization: Bearer $HART_TOKEN" \
  "$HART_URL/v1/skills/<owner>"
```

Private skills are only described if you pass the read key (`X-Hart-Read-Key`) or owner/admin key.

## Search by keyword

```sh
hart search --owner <owner> --tag foo
```

`--tag` matches both explicit `--tags` and the `keywords` extracted from `<meta name="keywords">`.

## Read a skill

```sh
hart get owner/artifact              # metadata + versions (includes description/keywords)
curl -s "$HART_URL/a/owner/artifact" # rendered HTML
```

For a private skill, set `HART_READ_KEY` or pass `--read-key` / `X-Hart-Read-Key`.

## Pick the right skill

Use this when the human asks "find the skill for X", "what skills do we have", or "list my runbooks". Prefer `hart list --owner <who> --format skills` over `hart list` when the answer should be a compact catalog.

## Notes

- Skills are ordinary hart artifacts; the same CSP, versioning, and visibility rules apply.
- The catalog reads only the first 8 KB of the stored HTML, so `<meta>` tags should live in `<head>`.
- To publish a skill, see the `hart-skill-authoring` skill.
