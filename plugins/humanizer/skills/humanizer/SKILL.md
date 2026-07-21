---
name: humanizer
description: |
  Use when removing AI-generation patterns from text in English or Russian.
  Auto-detects language by Cyrillic ratio and applies the matching ruleset.
  Trigger phrases: "humanize this", "remove AI patterns", "make this sound human",
  "очеловечить текст", "убрать признаки нейросети", "сделай текст живым".
  Honors explicit overrides like "humanize as English" / "обработай как русский".
  For mixed-language text, asks which ruleset to apply.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
  - AskUserQuestion
---

# Humanizer (EN + RU auto-routing)

Remove AI-generation patterns from text. This skill bundles two MIT-licensed
upstream rulesets and routes the input to the right one based on language.

This file is a router. The actual humanization rules live in
`references/humanizer-en.md` and `references/humanizer-ru.md` and are
authoritative. Do not paraphrase, summarise, or "improve" them — load and follow.

## Process

### Step 1 — Receive input

Accept the text to humanize as: a pasted block, a file path (use `Read`), or the
current selection. If the input is unclear, ask the user once.

### Step 2 — Honour explicit override

Scan the user's request (case-insensitive) for an explicit language directive:

- **EN override** — the request contains any of: `as english`, `english only`,
  `humanize in english`, `на английском`, `обработай как английский`.
- **RU override** — the request contains any of: `as russian`, `russian only`,
  `humanize in russian`, `на русском`, `обработай как русский`.

If an override is present, skip step 3 and jump to step 4 with the chosen language.

### Step 3 — Detect language

Count letters in the input (ignore digits, punctuation, whitespace):

- `cyr` = number of letters matching `[А-Яа-яЁё]`
- `lat` = number of letters matching `[A-Za-z]`
- `total = cyr + lat`

Decide:

- **`total < 20`** (input too short to classify reliably) → use `AskUserQuestion`
  with options "English", "Russian".
- **`cyr / total >= 0.6`** → Russian.
- **`cyr / total <= 0.1`** → English.
- **Otherwise** (mixed, Cyrillic ratio between 10 % and 60 % exclusive) → use `AskUserQuestion` with options
  "Apply Russian rules", "Apply English rules", "Run both passes (RU then EN)".

### Step 4 — Load the chosen ruleset

- For English: `Read references/humanizer-en.md`
- For Russian: `Read references/humanizer-ru.md`
- For "both passes": load both. Execute RU first, then EN on the RU output.

The loaded file is authoritative. Treat its instructions as if they were yours.

### Step 4b — Russian only: locate the scanner

The Russian ruleset ships a deterministic scanner and tells you to run it before
auditing. It refers to that scanner as `<папка скилла>/scripts/scan.py`. In this
plugin the path is `scripts/scan.py` relative to *this* file — not relative to
`references/`. Resolve it that way and otherwise follow the ruleset verbatim,
including its fallbacks when Python or the packages are missing.

There is no English counterpart; upstream does not ship one. Skip this step for EN.

### Step 5 — Execute

Apply the diagnostic, rewrite, and audit process described in the loaded
reference verbatim. Do not skip the audit pass. Do not invent new rules.

If the user provided a writing sample for voice calibration, pass it through to
the chosen ruleset's voice-calibration section as-is, regardless of sample
language.

### Step 6 — Output

Use the output format specified by the loaded reference (typically:
draft → audit → final → list of changes). Do not change the format.

## Rules of the road

- The router never edits the rulesets or `scripts/`. Both are vendored verbatim;
  refresh from upstream is a separate procedure documented in `../../../README.md`.
- The router never invents new patterns or merges English/Russian rules.
- The scanner is advisory. Its score never overrides the ruleset's own judgement,
  and a missing Python or a failed run never blocks the pass.
- "Both passes" runs RU first because RU's hard bans include em-dash removal
  (which already covers EN pattern #14) — running EN first would let dashes
  re-enter via RU's rewrites.

## Attribution

This skill bundles MIT-licensed work by
[blader](https://github.com/blader/humanizer) (English ruleset) and
[ilyautov](https://github.com/ilyautov/humanizer-ru) (Russian ruleset).
See `../../../NOTICE` for full attribution and pinned upstream commits.
