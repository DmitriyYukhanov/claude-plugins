# Capabilities and optional companions

Use the tools and skills exposed by the current host, not another agent's installed-plugin list.
Read a companion before invoking it; use it only when its runtime requirements are met. A missing
tool changes the mechanism, never the required check. Report a fallback once; if the check cannot
actually be performed, report it as blocked, never passed.

## Host tools

- Questions: use the host's question tool when available in the current mode, otherwise ask in
  chat. An unanswered asynchronous question is still pending; continue only independent work.
  Count user checkpoints, not tool calls, and honor approval already given for this task.
- Delegation: use native subagents (Claude Code's Agent or Codex's available collaboration tools).
  Bound concurrency, make research/review read-only, and keep one implementation writer. Pass the
  issue, paths, output contract and active constraints explicitly; do not depend on a hook to
  carry them. Without delegation, do the same checks sequentially and disclose self-review.
- Skills: Claude Code uses its skill invocations; Codex loads the installed skill instructions
  through its own catalog. Never send a slash command to the shell or invent an unavailable tool.

## Companions

| Capability | Preferred (if installed) | Inline fallback |
|---|---|---|
| Written plan (Step 4) | `superpowers:writing-plans` | Write a short ordered plan (files to touch, test-first steps, gates) before coding. |
| Design critique (Step 2, complex) | `codex-collaboration:cross-review` when its Claude-to-Codex runtime is available | Have an independent reviewer critique the design against the code, then revise; without delegation, self-critique and disclose it. |
| Humanizing human-facing text | `humanizer:humanizer` | Self-edit the text to drop AI-tell phrasing. |
| Lazy design and build (Steps 2–4) | `ponytail:ponytail`, preserving the active level or using `full` when unset | Design and build against the same ladder by hand: does this need to exist, does the stdlib or the platform already do it, can it be one line. |
| Grilling the design (Step 3, `--grill` only) | `mattpocock-skills:grilling` over the design you just built | Discuss the design and open `asked` items in the same checkpoint, continuing until the user confirms the design. |
| Deletion lens (Step 6) | `ponytail:ponytail-review` over the run's diff | Re-read the diff hunting only for what to delete: reinvented stdlib, one-caller abstractions, config nobody sets, flags nobody passes. |
| Code review (Step 6) | The host's review capability, such as `code-review` in Claude Code | Use a read-only reviewer when available, otherwise self-review; check the diff, callers and tests for regressions, failure paths and missing coverage. |
| Security review (Step 6, when triggered) | An available security-review skill or reviewer | Trace trust boundaries, authorization, secret exposure and the relevant abuse cases through the changed flow. |
| Simplification (Step 6) | The host's simplification capability, such as `simplify` | Simplify the surviving code without changing its behavior. |
| Runtime verification (Step 6) | The host's verification capability, such as `verify` | Build and exercise the changed surface, including an error or boundary case; retain command/browser evidence. |

`codex-collaboration` currently orchestrates Codex from Claude Code; installing it in Codex does
not supply a second model. Use the design-critique fallback there. Deep research is optional
user-supplied context, never a prerequisite or a command the pipeline assumes it can start.
