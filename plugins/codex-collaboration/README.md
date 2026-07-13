# codex-collaboration

Cross-model collaboration between Claude and Codex CLI. Two workflows: a sequential drive/validate loop where both models must agree before any action, and a parallel dual review where findings are resolved by evidence and auto-applied.

## Installation

Requires the [Codex plugin for Claude Code](https://github.com/openai/codex-plugin-cc) first:

```bash
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/codex:setup
```

Then install this plugin:

```bash
/plugin install codex-collaboration@dmitriy-claude-plugins
```

## Skills

### `collaborative-loop`

Sequential drive/validate/act cycles. Claude produces an analysis with numbered findings, Codex validates each finding (CONFIRM/REJECT), Claude re-evaluates, and only findings both models agree on get implemented. After fixes, Codex reviews the changes and the loop repeats until clean or max rounds.

```text
/collaborative-loop [--max-rounds N] [--type code|plan|architecture|design] [target files...]
```

Trigger phrases: "collaborate with codex", "have codex review my changes", "collaborative loop".

### `cross-review`

Parallel dual review. Both models review the same artifact independently, then findings go through triage, cross-validation (each model verifies the other's findings), and evidence research. Findings backed by agreement, cross-validation, or evidence are applied automatically each round; only genuinely inconclusive disagreements reach you.

```text
/cross-review [--max-rounds N] [--type code|plan|architecture|design] [target files...]
```

Trigger phrases: "cross-review", "dual review", "get a second opinion".

## Defaults and requirements

- Both workflows review the branch diff against the base branch when no target files are given.
- The default Codex model is `gpt-5.6-sol` (requires Codex CLI 0.143.0 or newer); if unavailable it falls back to `gpt-5.5`, then `gpt-5.4`.
- Both models are always required: if Codex is down, the workflows attempt a direct `codex exec` fallback and stop rather than degrade to a Claude-only review.

## License

MIT
