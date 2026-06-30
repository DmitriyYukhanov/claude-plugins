# tour-companion.md synthesis contract

Triggered when:
- Archetype is `codebase` or `generic`, AND
- Step 5 of `analyze` discovered no user-authored markdown to embed.

## Output skeleton (required H2s, in order)

```markdown
# <Project> — Companion

## Overview

(2–4 paragraphs introducing the artifact's purpose and shape.)

## Map

(Annotated list of entry points, key modules, or top-level docs. Forward-slash paths only. NO inlined source code.)

## Glossary

(Domain terms encountered during survey, format `**term** — definition`.)

## Where to look next

(Pointers into the artifact for further exploration.)
```

## Constraints

- **No source code inlined.** Reference files via paths only; the rendered tour body uses click-to-copy `[label](path:LINE)` to jump in the IDE.
- **Soft cap 600 lines.** Do not truncate; the renderer warns if exceeded.
- **Synthesized content describes the artifact** — it does not paraphrase or summarise it inaccurately. When in doubt, point at the source via a path link.

## After synthesis

Add the companion to `tour-spec.json`:

```json
"embedded_sources": [
  { "name": "companion", "path": "tour-companion.md", "label": "Companion" }
]
```

And propose at least one cross-ref pattern targeting it — e.g. `[[companion]]` or `[[companion:overview]]` with `anchor_format: "{1}"`, so the token resolves to the companion's `## Overview` heading.
