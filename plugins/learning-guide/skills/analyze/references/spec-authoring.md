# Spec authoring

How to fill in `tour-spec.json` so the renderer produces a useful tour.

## Required fields

- `schema_version`: always `"1.0"` for this plugin version.
- `title`: 1–200 chars.
- `lang`: `"en"` default; `"ru"` ships; any locale string with an `i18n/<lang>.json` file works.
- `archetype`: one of `codebase`, `planning-session`, `refactor-plan`, `generic`.
- `sections`: at least one. Each needs `id`, `level`, `title`, `body_md`. Sections with `level >= 2` MUST have a `parent` pointing at a level-1 section's `id` (the renderer enforces this; the JSON Schema only hints it for editors).

## body_md best practices

- One idea per paragraph; lists for parallel items; tables for comparisons.
- Use callouts sparingly: `info` for context, `warn` for important constraints, `danger` for halt criteria, `success` for green-path summaries, `tip` for sidebar-style hints. Callouts may wrap fenced code blocks.
- Reference files via `[label](path:LINE)` — never inline source code.
- Cross-refs and external link tokens (`TICKET-123`) appear inline naturally; the renderer linkifies inline text only (never code spans/blocks).

## quiz items

- 2–8 options; pick the most-likely-wrong-but-plausible distractors.
- `answer_index` is 0-based.
- `explanation` is rendered through markdown — short paragraphs OK.

## final_quiz and glossary

- `final_quiz` — 3–5 items spanning the whole tour. It is appended as its own navigable section at the end.
- `glossary` — one short paragraph per term. It renders as a navigable section near the end. Avoid jargon for the audience the tour targets.

## external_links

Each template must start with an allowed scheme (`http://`, `https://`, or `mailto:`) and contain `{id}`, which is replaced by the part after the prefix. Other schemes (e.g. `javascript:`) are rejected by the schema.

## renderer hints

- `include_mermaid: null` — auto-detect from the rendered body HTML (default). Diagrams are scoped to `body_md`; a `mermaid` fence shown inside a code example is not treated as a diagram.
- `include_progress_tracker: true` — sidebar progress block.
- `include_pager: true` — Prev/Next buttons.
- `max_inline_payload_kb: <integer or null>` — soft warning when the inlined content (the vendored Mermaid bundle is excluded) exceeds this.
- `template_compatibility_version: "1"` — required only when overriding `template.html`.
