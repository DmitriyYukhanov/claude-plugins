# learning-guide

Generate self-contained, offline-first, interactive HTML learning guides for any artifact.

## Installation

```bash
/plugin install learning-guide@DmitriyYukhanov/claude-plugins
```

## Quickstart

1. In Claude Code, say: *"Create a learning guide for `<path>`."*
2. The `analyze` skill drafts `tour-spec.json` and hands off to `render`.
3. Open `index.html` (or double-click `open.cmd` on Windows).

## Skills

- **`learning-guide:learning-guide`** — entry-point; explains the flow.
- **`learning-guide:analyze`** — reads input → writes `tour-spec.json`.
- **`learning-guide:render`** — renders `tour-spec.json` → `index.html`.

## Requirements

Node.js on PATH. The renderer is zero-dependency — no `npm install`.

## Verifying

- `node scripts/tests/run-all.cjs` — zero-dependency unit tests (schema validator, markdown processor, renderer).
- `node scripts/verify.cjs` — end-to-end smoke render across the sample archetypes.
- `node scripts/browser-verify.cjs` — optional browser test that drives the real runtime in Chromium. Requires Playwright (`npm i -D playwright && npx playwright install chromium`); not a runtime dependency.

## Customization

Drop overrides in `<output-dir>/.learning-guide/`:
- `template.html` (set `renderer.template_compatibility_version` in spec)
- `i18n/<locale>.json` (shallow-merged over plugin defaults)
- `extra-styles.css` (appended after defaults)
- `archetype-<name>.md` (custom analyzer templates)
- `policy.json` — `{ "project_root": "<relative-path>" }` widens embedded-source resolution.
