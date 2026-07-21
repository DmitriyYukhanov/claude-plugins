# claude-md-slim

Shrink an oversized or stale `CLAUDE.md` by moving subsystem detail into path-scoped
`.claude/rules/` files, and prove the move lost nothing.

## Why

`CLAUDE.md` loads in full on every session. Anthropic's guidance is to **target under 200 lines**,
because longer files cost context on every request *and* reduce adherence — instructions get ignored
precisely because there are too many of them. The diagnostic from the docs: *"If Claude keeps doing
something you don't want despite having a rule against it, the file is probably too long and the rule
is getting lost."*

A second failure mode arrives with size: nobody prunes a long file, so claims rot in place. A stale
sentence is worse than a verbose one, because it is confidently wrong.

## What it does

`/slim-claude-md`, or just ask to slim, audit, or restructure a CLAUDE.md.

1. **Measure** — loaded size (HTML comments excluded, they are free), sections ranked by size, and
   which set to move to get under budget. Also flags codebase-derivable content and staleness hints.
2. **Sort** — what must load every session (safety rules, repo-wide conventions) versus what only
   matters inside one subsystem, versus what the docs say to delete outright.
3. **Choose the mechanism** — the part most people get wrong: `@import` loads **eagerly at launch**
   and saves no context. Only `.claude/rules/*.md` with `paths:` frontmatter defers loading.
4. **Extract verbatim** — whole sections, byte-for-byte, with a pointer left behind so nothing
   becomes silently unreachable.
5. **Verify** — a script compares the moved sections against the files that now hold them and fails
   loudly on anything that vanished. A diff cannot tell you this: a dropped paragraph looks exactly
   like an intentional trim.
6. **Confirm it loads** — `/context`, an actual read of a matching file, `/doctor`.

## Scripts

Both are standalone and usable without the skill.

```bash
# measure; exit 1 when over budget
python scripts/audit_claude_md.py CLAUDE.md [--budget 200] [--json]

# prove the extraction lost nothing; exit 1 on loss, 2 on an unmatched section name
python scripts/verify_extraction.py --original-git HEAD:CLAUDE.md \
    --section "Billing" --now .claude/rules/billing.md
```

## Relationship to claude-md-management

Anthropic's `claude-md-management` plugin audits CLAUDE.md **content quality** against templates and
captures session learnings. This plugin fixes **size and structure**. They compose: audit the content
with theirs, then restructure with this one.

## Reference

`skills/slim-claude-md/references/mechanics.md` caches the loading behaviour that governs the split
(mechanism comparison, `paths:` syntax and glob gotchas, hierarchy, compaction, verification),
verified against <https://code.claude.com/docs/en/memory> on 2026-07-21. It is a cache, not the source
of truth — if behaviour disagrees, re-read the docs and update it.
