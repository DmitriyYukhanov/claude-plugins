# Instruction-loading mechanics

The subset of Claude Code's memory behaviour that decides how to split a CLAUDE.md. Read the section
you need, not the whole file.

Verified against <https://code.claude.com/docs/en/memory> on 2026-07-21 (CLI 2.1.216). If observed
behaviour disagrees, re-read that page and fix this file: it is a cache, not the source of truth.

## Size budget

Official: **"target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce
adherence."** The diagnostic for a bloated file: *"If Claude keeps doing something you don't want
despite having a rule against it, the file is probably too long and the rule is getting lost."*

The per-line test the docs give: **"Would removing this cause Claude to make mistakes? If not, cut
it."**

Note this is an adherence budget, not a hard limit. CLAUDE.md is always loaded in full regardless of
length. (The 200-line/25KB *hard* truncation belongs to auto-memory's `MEMORY.md`, a different
system Claude writes for itself. Don't conflate the two.)

## Where to put an instruction

| Mechanism | Loads | Use for |
| --- | --- | --- |
| `CLAUDE.md` | every session, in full | facts needed in *every* session: build commands, always-do rules, conventions |
| `.claude/rules/*.md` **without** `paths:` | every session, same priority as `.claude/CLAUDE.md` | same as above, split by topic for humans; **no context saving** |
| `.claude/rules/*.md` **with** `paths:` | only when Claude reads a matching file | subsystem detail: the deep knowledge that only matters while editing that area |
| Skills (`.claude/skills/*/SKILL.md`) | on invocation, or when Claude judges them relevant | multi-step procedures and workflows |
| Hooks | deterministically, at a lifecycle event | anything that must happen *every* time with no exceptions |

Two consequences worth internalising:

**Only `paths:`-scoped rules actually save context.** Unscoped rules load at launch just like
CLAUDE.md.

**CLAUDE.md is advisory, not enforcement.** Official: *"Claude treats them as context, not enforced
configuration. To block an action regardless of what Claude decides, use a PreToolUse hook instead."*
If a rule keeps getting violated and it truly must never be violated, it belongs in a hook.

## The `@import` trap

`@path/to/file` works, but **imports do not reduce context**: *"Splitting into `@path` imports helps
organization but doesn't reduce context, since imported files load at launch."*

This is the single most common wrong turn when slimming a file, because splitting into imports
*looks* like it should help. It only reorganises. Use `paths:`-scoped rules when the goal is context.

Other import details: relative paths resolve against **the file containing the import**, not the
working directory; recursion is capped at **four hops**; parsing skips code spans and fences, so
`` `@README` `` stays literal while `@README` imports. An import resolving outside the working
directory is "external" and triggers a one-time approval dialog in project-level files; declining
disables it permanently.

## Path-scoped rules: syntax

```markdown
---
paths:
  - "src/api/**/*.ts"
  - "lib/**/*.{ts,tsx}"
---

# API rules

- All endpoints validate input.
```

- Files live in `.claude/rules/`, discovered **recursively**, so subdirectories are fine.
- A rule with no `paths:` key loads unconditionally.
- Rules trigger when Claude **reads a matching file**, not on every tool use.
- Glob treats `[` as a bracket expression. A malformed one (`photos [2024/**`) matches nothing;
  escape a literal bracket as `photos \[2024/**`.
- `~/.claude/rules/` holds personal rules for every project; they load *before* project rules, so
  project rules win a conflict.
- Symlinks are supported, including into a shared rules directory.

## Load order and hierarchy

Broadest to most specific, all **concatenated** rather than overriding:

1. Managed policy (org-wide, cannot be excluded)
2. `~/.claude/CLAUDE.md` (you, all projects)
3. `./CLAUDE.md` or `./.claude/CLAUDE.md` (team, in source control)
4. `./CLAUDE.local.md` (you, this project; gitignore it)

Claude walks **up** from the working directory, so a file closer to where you launched is read last.
Files in subdirectories **below** the cwd are not loaded at launch; they load when Claude reads a
file in that directory. That is the monorepo mechanism.

`CLAUDE.local.md` is **not deprecated** as of 2026-07 despite a mid-2025 docs inconsistency that said
so. Its one real limitation: being gitignored, it exists only in the worktree where it was created.
To share personal instructions across worktrees, import from home instead:
`@~/.claude/my-project-instructions.md`.

`claudeMdExcludes` (glob, any settings layer) skips ancestor CLAUDE.md files you don't want, for
monorepos. Managed policy files can never be excluded.

## Free tokens: HTML comments

Block-level `<!-- ... -->` comments are stripped before the content reaches the model. Notes to human
maintainers cost nothing and stay visible when the file is opened with the Read tool. Comments inside
fenced code blocks are preserved (and therefore do cost tokens).

## Compaction

Project-root CLAUDE.md is re-read from disk and re-injected after `/compact`. Nested CLAUDE.md files
are **not** re-injected automatically; they reload the next time Claude reads a file in that
directory. Anything stated only in conversation is lost.

## Verifying what actually loaded

- `/context` lists the files under **Memory files**. If a file isn't there, Claude cannot see it.
- `/memory` opens and edits them.
- The `InstructionsLoaded` hook logs exactly which instruction files loaded and why. This is the
  reliable way to confirm a `paths:` glob is matching, rather than assuming.
- `/doctor` (CLI 2.1.206+) proposes trims for a checked-in CLAUDE.md: it cuts what Claude can derive
  from the codebase (directory layouts, dependency lists, architecture overviews) and keeps pitfalls,
  rationale, and non-default conventions.

## What the docs say to exclude

Anything Claude can work out by reading the code; standard language conventions; detailed API docs
(link instead); information that changes frequently; long explanations and tutorials; file-by-file
descriptions of the codebase; self-evident advice like "write clean code".
