# Archetype: codebase

Use when the input is a directory of source files (any language) and there is no obvious user-authored doc layer covering the architecture.

## Section outline (suggested order)

1. **Overview** — purpose of the project, language/runtime, top-level shape.
2. **Map** — entry points, module boundaries, key interfaces. Use click-to-copy file paths.
3. **Control flow** — pick one or two important paths and walk them step by step.
4. **Extension points** — where users typically plug in new behavior; interfaces, registries, plugin points.
5. **Gotchas** — non-obvious invariants, accidental coupling, surprising performance characteristics.
6. **Mental model** — a short paragraph that lets the reader hold the project in their head.

## What to look for during step 4 of analyze

- Public types and their dependencies (favor reading interfaces before implementations).
- Build/runtime configuration files (manifest, package.json, *.csproj, Cargo.toml, go.mod, etc.).
- Tests as documentation: which behaviors are pinned by tests vs which are implicit.

## Quizzes that work for codebase

- "Which file is the public entry point?"
- "What does X depend on?" (multiple choice)
- "What changes if you swap implementation Y for Z?"

## Synthesis

If no user-authored markdown exists in the input, plan to generate `tour-companion.md` per `synthesis-contract.md`.

## Code in body_md

NEVER inline source code in `body_md`. Reference files via `[label](path:LINE)` only. Code is read on demand by clicking the path. Windows backslash paths work — the renderer normalizes them to forward slashes — but prefer forward slashes when authoring.
