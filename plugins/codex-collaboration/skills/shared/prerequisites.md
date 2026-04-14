# Prerequisites

Both skills share this preflight check. Read this file and execute the steps before any workflow.

## Preflight Check

1. **Check codex plugin** — invoke `/codex:setup`. Two failure modes:

2. **Command not recognized** (plugin not installed) — print install instructions and ABORT:
   ```
   The codex-collaboration plugin requires the Codex plugin for Claude Code.

   Install it:
   1. /plugin marketplace add openai/codex-plugin-cc
   2. /plugin install codex@openai-codex
   3. /reload-plugins
   4. Run /codex:setup to verify Codex CLI authentication

   Then re-run this skill.
   ```

3. **Setup reports failure** (plugin installed but CLI missing or auth expired) — report the specific issue and ABORT:
   ```
   Codex plugin is installed but setup failed: <specific error from /codex:setup>

   Fix it:
   - CLI not found: npm install -g @openai/codex
   - Auth expired: codex auth login
   - Then re-run this skill.
   ```

4. **On success** — proceed with the workflow.

## Recommended Codex Config

Informational, not blocking:

```toml
# ~/.codex/config.toml
model = "gpt-5.4"
model_reasoning_effort = "xhigh"
[features]
multi_agent = true
```

## Runtime Failure Policy

The collaborative loop requires BOTH collaborators. If Codex fails at runtime:

1. Do NOT fall back to a Claude subagent as reviewer — self-review defeats the purpose
2. Stop immediately and report the failure clearly
3. Suggest remediation (e.g., re-run `/codex:setup`, check auth)

## Runtime Health Checks

These checks are used by both skills **at dispatch time**, not just during preflight. The Codex runtime endpoint (named pipe on Windows, socket on Unix) can change between preflight and dispatch if the user opens Codex from another terminal, the desktop app restarts, or the broker process crashes.

### Fresh Setup Before Dispatch

**Before each Codex dispatch**, re-invoke `/codex:setup` to verify the runtime is still alive and capture the current endpoint. Do NOT reuse the preflight result from Step 1 — minutes may have passed, and any user interaction with Codex can restart the app server on a new pipe, orphaning tasks dispatched to the old one.

This takes ~5 seconds and prevents the entire class of pipe-mismatch zombie tasks.

### PID Liveness Verification

After dispatching a Codex task, verify the task's process is alive **within 30 seconds**:

```bash
# Windows
tasklist /FI "PID eq <PID>" /NH 2>/dev/null | grep -q "<PID>"

# Unix
kill -0 <PID> 2>/dev/null
```

Extract the PID from the companion's task record (job status output). If the PID does not exist, the task was dispatched to a dead or restarted runtime — trigger the Auto-Retry Protocol.

### Starting-Stuck Detection

If a task's phase remains `starting` for **>2 minutes** without advancing to `running` or showing file reads / tool invocations in the log:

1. **Check PID liveness immediately** — do not wait for the 5-minute log-staleness threshold
2. If PID is dead → trigger Auto-Retry Protocol
3. If PID is alive → continue with normal stale-log monitoring (the task may be in a long reasoning phase)

This catches "process died at launch" within 2 minutes instead of 9+.

### Auto-Retry Protocol (Dead Process)

When a dead PID or starting-stuck condition with dead PID is detected:

1. Cancel/kill the stale task entry
2. Re-run `/codex:setup` (establishes fresh runtime on new pipe)
3. Re-dispatch the same Codex task
4. Verify the new task's PID is alive within 30 seconds
5. **Max 1 auto-retry** — if the retry's PID also dies, STOP and report:
   ```
   Codex process died twice. The runtime may be unstable.
   Remediation: close all Codex instances, re-run /codex:setup, then re-invoke this skill.
   ```
