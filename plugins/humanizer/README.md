# humanizer

Auto-routing English + Russian humanizer for Claude Code. Removes signs of AI-generated writing by detecting the input language and applying the matching ruleset.

## Install

```
/plugin install humanizer@dmitriy-claude-plugins
```

## Use

Paste text into Claude and ask to humanize. The skill auto-detects language by Cyrillic ratio:

- **English text** → 33-pattern Wikipedia "Signs of AI writing" ruleset (Wikipedia AI Cleanup project), plus detection guidance on what *not* to flag.
- **Russian text** → 54-pattern ruleset with hard bans, traffic-light segmental markup, contrast-subtraction rewriting, and triple-pass audit.
- **Mixed text** (10–60 % Cyrillic) → asks which ruleset to apply: RU, EN, or both passes.

You can force a language with phrases like:

- `humanize this as English`
- `humanize as Russian` / `обработай как русский` / `на русском`

### Deterministic scanner (Russian only, optional)

The Russian upstream ships a scanner that measures what a model can only eyeball: hard bans, marker density, sentence-length variation, noun-to-verb ratio, and paragraph evenness. It rolls those into a 0–100 cleanliness score with three bands — ≥ 85 clean, 60–84 spot edits, below 60 rewrite. The skill runs it before an audit and reports "was N, now M" after a rewrite, which makes the edit measurable instead of a matter of taste.

It needs Python 3 and two packages:

```
pip install razdel pymorphy3
```

Both are MIT, pure Python, and work offline — no API keys and nothing paid. The dictionary `pymorphy3` pulls in is about 8 MB.

Skip the install if you don't want it. The ruleset falls back to estimating the score by the same logic, which is exactly what it does on claude.ai where no shell exists. Nothing breaks either way.

There is no English equivalent — upstream doesn't ship one, so the English pass is model-only.

### Editing log (Russian only)

The Russian ruleset opens `skills/humanizer/edit-log.md` in its first step, before it touches the text. The file ships empty. Add an entry when a rewrite comes back wrong in a way the catalog doesn't cover, so the correction lands once instead of on every draft. Entries win over the catalog's defaults and lose to the hard bans, and the file is append-only: a rule you regret gets cancelled by a newer entry rather than edited away.

It sits inside the plugin directory, so a plugin update can replace it. Copy out anything you want to survive one.

### Voice calibration

Provide a writing sample inline or as a file path; the skill matches its rhythm, lexicon, and quirks instead of using its default voice. The sample's own language doesn't matter — it's used only as a style reference.

## Credits

This plugin **bundles two MIT-licensed upstream skills as vendored copies**:

- English ruleset — [blader/humanizer](https://github.com/blader/humanizer) by blader, MIT.
- Russian ruleset and its scanner (`skills/humanizer/scripts/`) — [ilyautov/humanizer-ru](https://github.com/ilyautov/humanizer-ru) by ilyautov, MIT.

The scanner is vendored byte-for-byte with no local changes, so a refresh is a straight overwrite. Routing logic and plugin scaffolding © 2026 Dmitry Yuhanov, MIT. Full attribution and pinned upstream commit SHAs in [`NOTICE`](./NOTICE); upstream license texts in [`skills/humanizer/references/`](./skills/humanizer/references/).

## Refreshing vendored content

When upstream releases changes worth pulling:

1. Get the new commit SHA:
   ```
   git ls-remote https://github.com/blader/humanizer HEAD
   git ls-remote https://github.com/ilyautov/humanizer-ru HEAD
   ```
2. Fetch the upstream source files — paths are recorded in [`NOTICE`](./NOTICE) and have
   moved before, so read them from there rather than assuming. List the upstream skill
   directory too: the Russian ruleset has split into more files once already, and a file
   we don't carry is content the model silently loses.
   ```
   gh api repos/ilyautov/humanizer-ru/contents/skills/humanizer-ru?ref=<tag> --jq '.[].path'
   gh api repos/blader/humanizer/contents/SKILL.md?ref=<tag> --jq .content | base64 -d
   ```
3. Diff against the current vendored body (skip the first 4 lines — those are our header),
   then replace the body: strip the upstream YAML frontmatter, keep our 4-line header, and
   update the SHA both in the header and in `NOTICE`. Mirror upstream's own layout when
   vendoring, so the paths its prompt names resolve unchanged from the skill root.
   `edit-log.md` is the exception to the overwrite rule — it holds local entries, so merge
   rather than replace it.
4. Refresh the Russian scanner under `skills/humanizer/scripts/` from
   `skills/humanizer-ru/scripts/` upstream. These carry no header, so overwrite them
   wholesale and confirm with `git hash-object` that each file still matches the upstream
   blob SHA. Then re-run `scan.py` on a sample to check it still works:
   ```
   python skills/humanizer/scripts/scan.py sample.txt
   ```
   On Windows, run it with `PYTHONIOENCODING=utf-8`; the report is Russian and a cp1251
   console dies on the first `≥`.
5. Bump the plugin version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`:
   - **MINOR** if upstream added new rules or sections
   - **PATCH** for typo / wording fixes
   - **MAJOR** if upstream removed sections we depend on
6. Add a `CHANGELOG.md` entry under a new version header.
