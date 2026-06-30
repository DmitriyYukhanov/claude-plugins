# Cross-ref pattern design

Patterns are matched against inline text only. Code spans, code blocks, and inline HTML are NEVER linkified. Clicking a cross-ref opens the named embedded source in the side panel and scrolls to a matching heading.

## Bare-word patterns are rejected

Patterns like `\bplan\b` are too aggressive — they match incidental occurrences of the word "plan" anywhere in the body. Propose only token shapes with a non-letter anchor.

## Token shapes that work

- **Section refs:** `§N`, `§N.M`, `§N.M.K`. Pattern: `§(\\d+(?:\\.\\d+)*)`.
- **Wiki-style:** `[[design]]`, `[[design:overview]]`. Pattern: `\\[\\[design(?::([^\\]]+))?\\]\\]`.
- **Custom prefixed:** `@design:overview`. Always require a non-letter prefix to avoid bare-word matches.

Avoid nested unbounded quantifiers (e.g. `(\\d+)+`); the renderer rejects catastrophic-backtracking patterns.

## anchor_format and the heading-id contract

`anchor_format` produces the `id` the side panel scrolls to. There is **no `section-` prefix** — a heading id is the plain slug of its text, and `anchor_format` must produce that same slug.

- `null` — open the source at the top (no scroll).
- `"{1}"` — substitute capture group 1, slugified. This is the usual choice: `[[design:overview]]` → anchor `overview`, which matches the `## Overview` heading (id `overview`).

**Slug algorithm** (shared byte-for-byte across `analyze`, `render.cjs`, and the browser runtime): lowercase, replace each run of characters outside `[\p{L}\p{N}]` (Unicode letters/numbers, so Cyrillic and other scripts survive) with `-`, then strip leading/trailing `-`.

Because the heading text is slugified whole, `§3.1` only resolves if the target heading slugifies to `3-1` — i.e. a heading literally titled `3.1`. For prose headings like `## Overview`, prefer the `[[name:heading-slug]]` shape over `§N`.

## During analyze

When you propose patterns, scan the embedded source for headings, slugify each, and propose token shapes whose `anchor_format` output equals one of those slugs. Show the user the proposed list and ask for confirmation. Never auto-add patterns that match common English words, and never propose an anchor that does not resolve to an existing heading.
