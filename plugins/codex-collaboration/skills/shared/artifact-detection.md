# Artifact Detection

Classify target files to determine artifact type and review focus areas.

## Detection Order

1. **Explicit flag** — if user passes `--type code|plan|architecture|design`, use it
2. **File extension matching:**
   - Source code (`.ts`, `.py`, `.js`, `.jsx`, `.tsx`, `.go`, `.rs`, `.cs`, `.java`, `.rb`, `.cpp`, `.c`, `.h`) → **code**
   - `*-plan*`, `*-tasks*`, `*implementation-plan*` → **plan**
   - `*-architecture*`, `*-spec*` → **architecture**
   - Other `.md` in `docs/` or `plans/` → **design**
3. **Mixed targets** — default to **code**

## Target File Detection

When target files are not explicitly provided:

1. `git diff <base>...HEAD --name-only` (branch diff)
2. Auto-detect base branch from `git remote show origin` or fall back to `main`
3. Bare invocation (no args, no branch diff): ask user what to review
