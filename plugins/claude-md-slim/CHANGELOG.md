# Changelog

All notable changes to the **claude-md-slim** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-07-21

### Added
- `slim-claude-md` skill — a six-phase workflow for restructuring an oversized or stale CLAUDE.md:
  measure, sort sections, pick the loading mechanism, extract verbatim, verify nothing was lost,
  confirm the rules actually load.
- `scripts/audit_claude_md.py` — measures the *loaded* size (HTML comments excluded, since they are
  stripped before loading) against the documented 200-line budget, ranks sections and marks the set
  whose removal gets the file under budget, and flags codebase-derivable content plus staleness
  hints. Exit 1 when over budget.
- `scripts/verify_extraction.py` — proves a split moved content rather than losing it, comparing
  named sections of the original against the files that now hold them. Exits 2 on an unmatched
  section selector so a typo cannot silently check nothing.
- `references/mechanics.md` — the loading behaviour that decides how to split: the four mechanisms
  and when each loads, path-scoped rule syntax and glob gotchas, hierarchy and load order,
  compaction, free HTML comments, and how to verify what actually loaded.

### Notes
- Complements `claude-md-management` (Anthropic) rather than replacing it: that plugin audits content
  quality against templates, this one fixes size and structure.
- Documents the `@import` trap explicitly — imports load eagerly at launch and save no context, so
  only `paths:`-scoped rules defer loading. This is the most common wrong turn when slimming a file.
