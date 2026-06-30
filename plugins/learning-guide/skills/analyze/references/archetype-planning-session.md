# Archetype: planning-session

Use when the input is a single document summarizing a planning/working session — typical signals: `session_date:` frontmatter, `.observations.md` filename, decisions/blockers/files-touched headings.

## Section outline (suggested order)

1. **Introduction** — date, scope, who was in the session.
2. **Decisions** — bullet list of decisions taken, with cross-refs to related artifacts.
3. **Open blockers / questions** — items that gate downstream work, with owners.
4. **Files touched / changes summary** — table of files with action (new/rewritten/deleted/modified).
5. **Risks** — concerns surfaced; severity if available.
6. **Lessons** — process-level observations worth carrying forward.

## What to look for

- Frontmatter `artifacts:` list — embed those as side-panel sources.
- Trackable IDs (TICKET-, JIRA-, project-prefix-) — populate `external_links` and ask the user for URL templates.
- Section anchors in any embedded source — propose `cross_ref_patterns` so tokens like `§3.5` resolve.

## Quizzes that work for planning-session

- "Which decision was deferred to next phase?"
- "Who owns blocker N?"
- "Which file was rewritten vs newly created?"

## Tone

Match the session's tone (terse and factual). Strip any in-document version markers ("(NEW 2026-…)", "after meeting", etc.) — final-snapshot semantics.
