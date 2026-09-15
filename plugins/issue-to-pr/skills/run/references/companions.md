# Capabilities and optional companions

Use the tools and skills exposed by the current host, not another agent's installed-plugin list.
Read a companion before invoking it; use it only when its runtime requirements are met. A missing
tool changes the mechanism, never the required check. Report a fallback once; if the check cannot
actually be performed, report it as blocked, never passed.

## Host tools

- Questions: the host's question tool, otherwise chat. An unanswered asynchronous question is
  still open; count user checkpoints, not tool calls.
- Delegation: native subagents (Claude Code's `Agent`, Codex's collaboration tools). Research and
  review are read-only, one implementation writer, and everything they need is passed explicitly
  rather than inherited from a hook. Without delegation the same checks run sequentially, disclosed.

## Companions

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Written plan (Step 4) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Design critique (Step 2, complex) | `codex-collaboration:cross-review` when its Claude-to-Codex runtime is available | Have an independent reviewer critique the design against the code, then revise; without delegation, self-critique and disclose it. |
| Humanizing human-facing text | `humanizer:humanizer` | Self-edit the text to drop AI-tell phrasing. |
| Lazy design and build (Steps 2–4) | `ponytail:ponytail`, preserving the active level or using `full` when unset | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Grilling the design (Step 3, `--grill` only) | `mattpocock-skills:grilling` over the design you just built | Discuss the design and open `asked` items in the same checkpoint, continuing until the user confirms the design. |
| Deletion lens (Step 6) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |

Step 6's four checks — review, security review, simplification, runtime verification — get no
row, because a fallback table has nothing to say about a capability the host either has or does
not. In Claude Code they are `code-review`, `/security-review`, `simplify` and `verify`: bare
names, no install, no `if installed` branch. On a host without them, run the check directly — a
read-only reviewer over the diff, its callers and its tests; the trust boundaries, authorization
and secret exposure of the changed flow; the surviving code made simpler without behaviour
change; the built change driven past its happy path. The mechanism is the host's; the check is
not optional.

`codex-collaboration` currently orchestrates Codex from Claude Code; installing it in Codex does
not supply a second model. Use the design-critique fallback there. Deep research is optional
user-supplied context, never a prerequisite or a command the pipeline assumes it can start.
