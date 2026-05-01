# humanizer

Auto-routing English + Russian humanizer for Claude Code. Removes signs of AI-generated writing by detecting the input language and applying the matching ruleset.

## Install

```
/plugin install humanizer@dmitriy-claude-plugins
```

## Use

Paste text into Claude and ask to humanize. The skill auto-detects language by Cyrillic ratio:

- **English text** → 29-pattern Wikipedia "Signs of AI writing" ruleset (Wikipedia AI Cleanup project).
- **Russian text** → 44-pattern ruleset with hard bans, traffic-light segmental markup, contrast-subtraction rewriting, and triple-pass audit.
- **Mixed text** (10–60 % Cyrillic) → asks which ruleset to apply: RU, EN, or both passes.

You can force a language with phrases like:

- `humanize this as English`
- `humanize as Russian` / `обработай как русский` / `на русском`

### Voice calibration

Provide a writing sample inline or as a file path; the skill matches its rhythm, lexicon, and quirks instead of using its default voice. The sample's own language doesn't matter — it's used only as a style reference.

## Credits

This plugin **bundles two MIT-licensed upstream skills as vendored copies**:

- English ruleset — [blader/humanizer](https://github.com/blader/humanizer) by blader, MIT.
- Russian ruleset — [ilyautov/humanizer-ru](https://github.com/ilyautov/humanizer-ru) by ilyautov, MIT.

Routing logic and plugin scaffolding © 2026 Dmitry Yuhanov, MIT. Full attribution and pinned upstream commit SHAs in [`NOTICE`](./NOTICE); upstream license texts in [`skills/humanizer/references/`](./skills/humanizer/references/).

## Refreshing vendored content

When upstream releases changes worth pulling:

1. Get the new commit SHA:
   ```
   git ls-remote https://github.com/blader/humanizer HEAD
   git ls-remote https://github.com/ilyautov/humanizer-ru HEAD
   ```
2. Fetch and diff against the current vendored body (skip the first 4 lines — those are our header).
3. Replace the body, keep our 4-line header, update the SHA both in the header and in `NOTICE`.
4. Bump the plugin version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`:
   - **MINOR** if upstream added new rules or sections
   - **PATCH** for typo / wording fixes
   - **MAJOR** if upstream removed sections we depend on
5. Add a `CHANGELOG.md` entry under a new version header.
