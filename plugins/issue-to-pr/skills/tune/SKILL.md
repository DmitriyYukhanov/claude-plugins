---
name: tune
description: >-
  Process the issue-to-pr friction log into concrete skill/script improvements.
  Reads .claude/issue-to-pr/friction.log, proposes batched edits with evidence, and
  applies them on your approval. Run it when the log has built up.
when_to_use: When the user runs /issue-to-pr:tune, or the friction log exceeds ~10 lines.
argument-hint: "[--dry-run]"
user-invocable: true
disable-model-invocation: true
---

# tune — turn friction into fixes

The issue-to-pr pipeline no longer has an always-on "improve this skill" step. Instead
each run appends one line to `.claude/issue-to-pr/friction.log` (repo-local,
gitignored) whenever a step genuinely fought back — a stop that should not have
happened, an unclear instruction, a missed detection, a script that surprised the
model. This skill batches that evidence into real changes.

## Steps

1. **Read the log.** `.claude/issue-to-pr/friction.log` (from the repo root). Each
   line is a dated, one-sentence friction note with the step it hit. If the file is
   absent or empty, say so and stop — nothing to tune.
2. **Cluster.** Group the lines by root cause, not by surface symptom. Three notes
   about the same confusing exit code are one fix, not three.
3. **Propose the cheapest fix that holds.** For each cluster work down this ladder and
   stop at the first rung that answers the friction, quoting the lines as evidence. A
   change with no evidence line does not belong here.
   1. **Delete the behaviour** when nothing depends on it.
   2. **Require explicit input** where the pipeline was guessing.
   3. **Clarify the prose** so the model has what it needs to decide.
   4. **Add enforcement**: an exit code, a hook, a test. Only at a boundary where being
      wrong costs something irreversible.

   Rung 4 is the expensive one, since it adds code to maintain and test. Reach for it
   last, and say in the proposal why the rungs above do not answer the friction.
4. **Confirm, then apply.** Show the batched proposal and ask for a go-ahead. On
   approval, make the edits (bump the plugin version + changelog per repo rules),
   run the gates (`tests/run-tests.sh`), and — if the changed area is behavioral —
   note that a fresh dogfood run should confirm it. With `--dry-run`, stop after the
   proposal.
5. **Prune.** After applying, remove the addressed lines from the friction log (keep
   any not yet acted on) so the log reflects only open friction.

Never apply blind: every edit traces to a friction line, and the human approves the
batch. This keeps the skill improving from real use, not speculation.
