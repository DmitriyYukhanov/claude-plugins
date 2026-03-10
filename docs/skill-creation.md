# Skill Creation Best Practices

Supplement to the official docs: https://docs.anthropic.com/en/docs/claude-code/skills

Do not restate large parts of those docs inside a new skill. Keep the skill itself focused on what Claude will actually need at runtime.

## Metadata

- `name`: short hyphen-case, match the folder name exactly, under 64 characters.
- Prefer verb-led names that make triggering obvious. Avoid overloaded or reserved names.
- `description` is always in context, so keep it tight. Write in third person or imperative. Avoid first person.
- Include likely user trigger phrases in `description`, not just abstract capability text.
- Only add optional frontmatter (`model`, `allowed-tools`, `argument-hint`, `user-invocable`, `disable-model-invocation`, `context`, `agent`, `hooks`) when the skill's behavior actually depends on it.
- Treat `allowed-tools` and `user-invocable` as least-privilege controls: restrict tool access and invocation surface to the minimum the skill needs.

## SKILL.md Body

- Keep `SKILL.md` lean and procedural. Target under 500 lines; complex multi-phase workflows may exceed this if each section is individually lean.
- Assume Claude is already competent. Add only task-specific workflow, constraints, and references.
- Give one clear default path first. Do not present a menu of equivalent options unless the choice is genuinely important.
- Use step or phase ordering for fragile workflows.
- Call out stop conditions, failure branches, and which steps can run in parallel.
- For skills that perform live mutations (file deletions, API writes, git operations), require explicit safety gates: read-before-write, dry-run confirmation, or user approval before destructive actions. Design mutation flows to be idempotent where possible.
- Use progressive disclosure: keep variants, long examples, schemas, and domain detail in referenced files, not in the main body. When loading reference files, read only the relevant section rather than the entire file.
- Link referenced files directly from `SKILL.md`; avoid deep reference chains.
- Use forward slashes in paths and examples, even on Windows.

## Bundled Resources

- Put deterministic or repeated logic in `scripts/` instead of large inline code blocks. Validate scripts directly: check argument handling, exit codes, and stdout/stderr contracts.
- `references/` and `assets/` are available for heavy reference material and output templates, but add them only if you have material that does not belong in `scripts/` or the SKILL.md body.
- Some skills contain an `agents/` subdirectory with OpenAI-format agent config files (e.g., for Codex). These are tool-specific config files, not Claude Code subagents.
- Do not create extra files like `README.md`, `CHANGELOG.md`, or setup notes inside a skill unless the skill truly needs them at runtime.
- Do not duplicate the same guidance across `SKILL.md` and `references/`.

## Path Resolution

- Resolve paths dynamically. Do not hardcode absolute paths.
- In SKILL.md body text, use `${CLAUDE_PLUGIN_ROOT}` to reference the plugin's root directory (e.g., `bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-something.sh"`).
- In standalone shell scripts that may be invoked from different directories, derive the plugin root relative to the script location:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
  ```

## Shell Scripts

- Use `set -euo pipefail`, validate required args with `${1:?...}`, write diagnostics to `stderr`, and keep structured output on `stdout`.
- Always double-quote shell variable expansions (`"$VAR"`, `"${1}"`). Never interpolate user-supplied values into `eval`, backticks, or unquoted command positions.
- Never interpolate shell variables directly into inline Python/Ruby/etc. string literals. Pass non-secret data via positional arguments or environment variables; pass secrets via stdin or file descriptors.
- Never hardcode or log API tokens or secrets. Read credentials from environment variables; never echo them to stdout.
- Run `shellcheck` on skill scripts as part of validation.

## Temp Files

- Scope temp files under a skill-specific directory and clean them up.
- Use `trap 'rm -rf "$SKILL_TMPDIR"' EXIT` for automatic cleanup on all exit paths. Use a descriptive variable name — do not shadow the POSIX `TMPDIR` variable.
- For scripts that do not need repo-scoped temp files, `mktemp -d` is also acceptable.

## Subagents

- For skills that spawn subagents via the Agent tool, specify `subagent_type` consistently and document the expected model in the prompt.
- Apply least-privilege to spawned agents: restrict their tool access and mutation scope to what the subtask requires. Do not let a restricted skill bypass its own controls by delegating to an unrestricted subagent.
- Limit fan-out: avoid spawning one agent per file or item. Batch work into a bounded number of agents to prevent scalability issues.

## Validation

- Start from a few real prompts before writing the skill. Author against realistic triggers, not idealized examples.
- Test negative and ambiguous triggers to verify the skill does not over-trigger or misroute.
- Run the skill end to end at least twice — once for the happy path, once for rerun/idempotency. For skills with side effects, also test interrupted and retry scenarios.
- Check explicitly: trigger quality, instruction clarity, script reliability, and security (hostile input, credential handling, mutation safety).
- If a section in the skill duplicates the official docs, cut it and keep only the project-specific delta.
