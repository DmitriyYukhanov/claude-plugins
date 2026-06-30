---
name: analyze
description: Reads input artifact(s) — codebase, planning session, refactor plan, or generic doc — and writes a tour-spec.json describing sections, embedded sources, cross-refs, quizzes, and external link maps. Use when the user wants a fresh learning guide built from source material; auto-hands-off to learning-guide:render. Trigger phrases — "create a learning guide for X", "make an interactive tour", "generate onboarding doc", "build a learning module".
---

# Analyze — Tour Spec Authoring

Read input artifact(s) and write a `tour-spec.json` that the renderer consumes. Hand off to `learning-guide:render` at the end.

## Trigger phrases

- "create a learning guide for X"
- "make an interactive tour"
- "generate onboarding doc"
- "build a learning module from this session"

## Inputs to collect from the user

1. **Source artifact path(s)** — required. One or more files/folders.
2. **Output directory** — default `<input-parent>/learning/`.
3. **Archetype hint** — optional; auto-detect with these rules:
   - Filename ends `.observations.md` OR YAML frontmatter contains `session_date:` → `planning-session`.
   - Input is a directory of source files with no obvious doc layer → `codebase`.
   - Input contains "Phase 1", "Phase 2", "rollout", "blockers" structure → `refactor-plan`.
   - Otherwise → `generic`.
4. **Language** — auto-detect from input text dominance; require >80% single-locale tokens to commit, otherwise default `en`. Always state the detected language and offer an override before drafting.

## Flow

1. **Resolve inputs.** Confirm path(s) and output dir before reading anything large. Reject non-existent paths.
2. **Pick archetype.** Auto-detect, state the choice, ask the user to confirm or override.
3. **Load archetype reference.** Read `references/archetype-<name>.md`.
4. **Survey the input.**
   - Codebase: structured exploration — entry points, module map, control flow.
   - Doc: top-to-bottom read.
   - Session: lift decisions, blockers, files-touched.
5. **Discover embedded sources.** Look for user-authored markdown referenced from the input (links, frontmatter `artifacts:` lists, sibling `.md` files). If none found AND archetype is `codebase` or `generic`, plan to synthesize `tour-companion.md` per `references/synthesis-contract.md`.
6. **Discover external link tokens.** Scan input for ticket/issue patterns. Ask the user for URL templates (e.g., `TICKET-` → `https://tracker.example.com/browse/TICKET-{id}`). Templates must start with `http://`, `https://`, or `mailto:` and contain `{id}` — the renderer rejects other schemes.
7. **Discover cross-ref patterns.** Per `references/cross-ref-design.md`. Propose only token-shaped patterns; bare words are forbidden. Show the user the proposed list, get confirmation.
8. **Draft the tour spec.** Follow the archetype's section outline. Each section gets a markdown body, optional inline quiz. Synthesize `tour-companion.md` if planned in step 5. Use `references/spec-authoring.md` for `body_md` style.
9. **Quality gates.** Before handoff, verify:
   - Every section has non-empty `body_md`.
   - Every section with `level >= 2` has a `parent` (the renderer rejects a spec that violates this — the JSON Schema only hints it for editors).
   - Every cross-ref pattern uses a non-bare-word token shape, names an existing source, AND its `anchor_format` resolves to a heading in that source. Heading anchors are bare slugs with no `section-` prefix (see `references/cross-ref-design.md`).
   - Every `external_links` template starts with an allowed scheme (`http(s)://` / `mailto:`) and contains `{id}`.
   - Every quiz `answer_index` is in `[0, options.length-1]`.
   - Mermaid blocks parse as valid (best-effort regex on the first non-blank line).
10. **Hand off to render.** Invoke `learning-guide:render` with the spec path. No "shall I render?" gate — render is cheap and idempotent.

## Re-invocation behavior

If `tour-spec.json` already exists at the target path, ask:

> "Existing spec found. Update it (preserve your edits), regenerate from scratch, or just re-render?"

- **Update mode** — preserve `sections[].body_md`, `sections[].quiz`, `final_quiz`, `glossary` verbatim. Refresh `embedded_sources`, `external_links`, `cross_ref_patterns` only when input artifacts have changed since the spec's `mtime`. All other top-level fields refresh. Conflicts are surfaced as a numbered list before write.
- **Regenerate** — delete the existing spec, re-run from step 1.
- **Re-render only** — invoke `learning-guide:render`; skip analyze entirely.

## References

- `references/archetype-codebase.md`, `references/archetype-planning-session.md`, `references/archetype-refactor-plan.md`, `references/archetype-generic.md`
- `references/spec-authoring.md` — `body_md` style and field rules.
- `references/cross-ref-design.md` — pattern shapes and slug algorithm.
- `references/synthesis-contract.md` — `tour-companion.md` skeleton.
