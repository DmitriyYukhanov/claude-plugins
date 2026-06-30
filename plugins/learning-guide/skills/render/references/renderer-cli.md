# Renderer CLI

The renderer is `${CLAUDE_PLUGIN_ROOT}/scripts/render.cjs`. Zero-dependency Node script — no `npm install`.

## Usage

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/render.cjs" <tour-spec.json> [--output-dir <dir>]
```

- `<tour-spec.json>` — required path to a valid tour spec.
- `--output-dir <dir>` — defaults to the spec file's parent directory.

## Exit codes

- `0` — success. Prints a single-line summary to stdout.
- `1` — failure. Prints reason(s) to stderr.

## Common failures and fixes

| Stderr message contains | Cause | Fix |
|---|---|---|
| `not found` | spec path is wrong | confirm with `ls` |
| `invalid JSON` | spec is malformed | run `node -e "JSON.parse(require('fs').readFileSync(...))"` |
| `does not match pattern` | field violates schema | inspect the path in the error and consult `assets/tour-spec.schema.json` |
| `outside project root` | `embedded_sources[].path` resolves outside the spec's parent dir (including via a symlink) | move the source under the spec's directory OR widen with `.learning-guide/policy.json` `{"project_root":"<rel>"}` |
| `template_compatibility_version` | user `template.html` override mismatched | update `tour-spec.renderer.template_compatibility_version` to match the value in `<!-- template_compatibility_version: N -->` at the top of the override |
| `schema_version` | spec uses an unsupported major version | regenerate via `analyze` or upgrade/downgrade the plugin |
| `payload` | inlined content exceeds `max_inline_payload_kb` | soft warning only. The vendored Mermaid bundle is excluded from the count, so this reflects content + embedded sources — trim oversized embedded sources or raise the cap |

## Quick recipes

- Re-render after editing the spec:
  ```bash
  node "${CLAUDE_PLUGIN_ROOT}/scripts/render.cjs" tour-spec.json
  ```
- Render to a different output directory:
  ```bash
  node "${CLAUDE_PLUGIN_ROOT}/scripts/render.cjs" tour-spec.json --output-dir build/tour
  ```
- Force-disable Mermaid even if a diagram is present: set `renderer.include_mermaid` to `false` in the spec.
