# Prerequisites

Both skills share this preflight check. Read this file and execute the steps before any workflow.

## Preflight Check

1. **Check codex plugin** — invoke `/codex:setup`. Two failure modes:

   - **Command not recognized** (plugin not installed) — print install instructions and ABORT:
     ```
     The codex-collaboration plugin requires the Codex plugin for Claude Code.

     Install it:
     1. /plugin marketplace add openai/codex-plugin-cc
     2. /plugin install codex@openai-codex
     3. /reload-plugins
     4. Run /codex:setup to verify Codex CLI authentication

     Then re-run this skill.
     ```

   - **Setup reports failure** (plugin installed but CLI missing or auth expired) — report the specific issue and ABORT:
     ```
     Codex plugin is installed but setup failed: <specific error from /codex:setup>

     Fix it:
     - CLI not found: npm install -g @openai/codex
     - Auth expired: codex auth login
     - Then re-run this skill.
     ```

2. **On success** — proceed with the workflow.

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
2. Attempt Direct CLI Fallback before stopping (see section below)
3. Only stop and report the failure if both companion and CLI fallback fail
4. Suggest remediation (e.g., re-run `/codex:setup`, check auth, check OpenAI API status)

## Runtime Health Checks

These checks are used by both skills **at dispatch time**, not just during preflight. The Codex runtime endpoint (named pipe on Windows, socket on Unix) can change between preflight and dispatch if the user opens Codex from another terminal, the desktop app restarts, or the runtime process crashes.

### Fresh Setup Before Dispatch

**Before each Codex dispatch**, re-invoke `/codex:setup` to verify the runtime is still alive and capture the current endpoint. Do NOT reuse the preflight result from Step 1 — minutes may have passed, and any user interaction with Codex can restart the app server on a new pipe, orphaning tasks dispatched to the old one.

This takes ~5 seconds and prevents the entire class of pipe-mismatch zombie tasks.

### Task Health Verification

After dispatching a Codex task, verify it is making progress **within 60 seconds**. Check task status via `/codex:status` (Skill tool) — if the task has a phase (`starting`, `running`) and shows log entries, it is alive.

**Do NOT use PID-based liveness checks on Windows.** The Codex CLI launcher process exits immediately after dispatching work to the shared runtime server via a named pipe. `tasklist /FI "PID eq <PID>"` will always show the launcher PID as dead, even when the task is running normally. The actual work happens in the runtime server process, which is a different PID.

**Instead, verify health through Skill tools:**

Use `/codex:status` (Skill tool) — it returns task phase and recent log activity without touching the companion script directly. Only fall back to the raw companion script when the Skill tool errors (see "Skill-tool Fallback" below).

A task is healthy if:
- Phase is `starting` or `running`
- Log file exists and has been modified recently (check timestamp)
- Log shows tool calls, file reads, or other activity

A task is likely dead if:
- `/codex:status` reports it as `failed` or `cancelled`
- Phase is `starting` with zero log entries for >5 minutes
- The Codex runtime pipe endpoint no longer exists

### Starting-Stuck Detection

If a task's phase remains `starting` for **>5 minutes** without advancing to `running` or showing any log entries:

1. Check task status (via `/codex:status`) for error messages
2. Run the Diagnostic Escalation procedure (see below) to check for connection errors
3. If diagnostics reveal a connection issue (WebSocket limit, 403, etc.) → report to user with specific remediation
4. If no diagnostic clue → trigger Auto-Retry Protocol

### Response-Generation Awareness

Codex tasks have two distinct phases of apparent inactivity:

1. **Reasoning phase** — Codex is thinking before its first tool call. Usually <2 minutes.
2. **Response generation phase** — after finishing all tool calls, Codex composes its final response. This can take **10-30 minutes** for complex reviews with many findings. During this time, the log shows no new tool calls but the task is still active.

**Do NOT cancel a task that has been actively making tool calls and then goes quiet.** Check the log: if the last entries are tool calls (file reads, searches), the task is likely generating its response. Only consider it stuck if:
- The task was in `starting` phase and never made any tool calls (starting-stuck)
- `/codex:status` reports it as `failed`
- Diagnostics reveal a connection error

**When in doubt, wait.** A premature cancellation wastes 10-30 minutes of completed Codex work and forces a full restart. A false-positive "hang" wastes only waiting time.

**Maximum wait:** If the task has been in response generation (no new tool calls) for **>15 minutes**, run Diagnostic Escalation. Session data shows that tasks silent for 10-15 minutes are almost always dead (pipe crash or API hang), not generating. At that point, escalate to Direct CLI Fallback rather than continuing to wait.

### Diagnostic Escalation

When a Codex task fails or appears stuck, check deeper before retrying blindly. These diagnostics often reveal the root cause immediately:

**1. Check task status for error details:** invoke `/codex:status` via the Skill tool. Look for error messages, failure reasons, or `failed` status in the output.

**2. Quick connectivity test** — verify the runtime can actually reach the API: invoke `/codex:rescue --fresh` with a trivial prompt like "Reply with OK". Cap the wait at **90 seconds** for this probe specifically (the 15-min response-generation threshold does not apply — a probe that can't echo "OK" in 90s is dead). If the user has already denied `/codex:rescue` earlier this session, skip the probe and go straight to Direct CLI Fallback — re-asking permission for a diagnostic just to diagnose around the denial is a dead end. Interpret the result:

- **Task dispatched but hangs >90 seconds or returns an empty/runtime error** → the runtime connection is dead (WebSocket TTL, pipe crash); continue with the remediation table below
- **Skill-tool-level error on `/codex:rescue` dispatch** (`disable-model-invocation`, permission denial, or the Skill gate rejects the invocation) → this is NOT a dead connection; do NOT run dead-runtime remediation. Route as follows:
  - **Permission denial at the Skill gate** → inform the user, then offer Direct CLI Fallback (`codex exec`). Wait for the user's explicit choice before dispatching — denial is the user exercising control. The top-level skills (collaborative-loop Step 4 / Step 6, cross-review Step 3) document this as "Skill-gate Rejection"
  - **`disable-model-invocation` or similar non-user errors** → go directly to Direct CLI Fallback (below); the Skill tool is unavailable but the underlying runtime may still work

**3. Common failure signatures and remediation:**

| Symptom | Likely Cause | Remediation |
|---------|-------------|-------------|
| Task stuck in `starting`, connectivity test hangs | OpenAI 60-minute WebSocket TTL expired | User must restart Codex app/CLI for fresh connection |
| `403 Forbidden` in `/codex:status` output | API access blocked (rate limit, auth, or network) | Check auth (`codex auth login`), VPN, or wait and retry |
| Connectivity test returns empty/error | Stale runtime pipe — server crashed but pipe persists | User must close all Codex instances and restart |
| `/codex:status` reports `failed` with no details | Transient API error | Re-run `/codex:setup` and retry |

**4. Report diagnostics to the user** with the specific symptom and remediation step. Do NOT silently retry when the root cause is a connection issue — retrying against a dead WebSocket just wastes time.

### WebSocket Connection Limit

OpenAI's API enforces a **60-minute WebSocket TTL** on the shared app server connection. When this limit is hit:

- The Codex CLI (interactive) still works because it creates a **fresh connection each time**
- The companion dispatch fails because it routes through the **shared app server**, which holds a stale WebSocket
- Tasks get stuck in `starting` or fail with `websocket_connection_limit_reached`

**Detection:** If a task fails and the user confirms the interactive Codex CLI works fine, the shared app server's WebSocket is almost certainly stale.

**Recovery:** The user must restart the Codex desktop app or close and reopen the Codex CLI to reset the app server. Then re-run `/codex:setup` and retry.

### Session Reliability Tracking

Track companion reliability within the current session. After the **first companion failure** (pipe crash, hanging task, or runtime death), mark the session as degraded. In a degraded session:

- After a single companion retry failure, skip directly to Direct CLI Fallback instead of exhausting the retry budget
- Prefer CLI fallback for complex tasks (cross-validation prompts, multi-finding reviews) even before the companion fails on them

The 15-minute response-generation threshold stays flat — session data showed the prior "drop to 8 min in degraded" rule produced inconsistent escalation timing depending on which file was last read. Session reliability affects *retry budget and CLI preference*, not the silence threshold.

This prevents the pattern observed in real usage: companion works for a short initial review, then fails repeatedly on longer cross-validation tasks, wasting 30+ minutes of retries before the user manually suggests CLI.

### Auto-Retry Protocol

When a task failure is detected:

1. Cancel/kill the stale task entry
2. **Run Diagnostic Escalation** — check logs for connection errors before blindly retrying
3. If diagnostics reveal a connection issue → report to user with specific remediation, do NOT retry (retrying against a dead connection is pointless)
4. If no connection issue found → re-run `/codex:setup` and re-dispatch the same task
5. **Dismiss stale task artifacts** — ignore late-arriving notifications from the original dead task
6. **Max 2 auto-retries via companion** — if the second retry also fails, escalate to Direct CLI Fallback (see below). Do NOT stop entirely until CLI fallback has also been attempted.

### Direct CLI Fallback

When companion retries are exhausted (or immediately in a degraded session for complex tasks), bypass the companion broker entirely and run Codex via the CLI directly. This creates a fresh connection per invocation and avoids the pipe/WebSocket issues that plague the shared app server.

**Why this works:** The companion routes tasks through a shared app server with a persistent WebSocket. When that connection dies (pipe crash, 60-min TTL, Windows pipe backpressure), all tasks fail. Direct `codex exec` creates a **fresh connection each time**, which is why it succeeds when the companion doesn't.

**How to invoke (cross-platform):**

Resolve a temp directory that works on the current platform:
- Unix/macOS/Linux: `$TMPDIR` (fallback: `/tmp`)
- Windows (Git Bash / WSL): `$TEMP` (usually `C:/Users/<user>/AppData/Local/Temp`)
- Windows PowerShell / cmd: `$env:TEMP` / `%TEMP%`

Write the prompt to a temp file to avoid shell escaping issues, then run `codex exec` capturing **combined stdout+stderr** so the Monitor tool can see runtime errors (not just model output):

```bash
# Unix / Git Bash / WSL
TMP="${TMPDIR:-/tmp}"
cat > "$TMP/codex-prompt.txt" << 'PROMPT_EOF'
<your full prompt here, including all context inline>
PROMPT_EOF

# Capture stdout AND stderr — stderr carries sandbox errors Monitor needs to see.
# Append the exit code to the SAME log file Monitor tails, so the completion marker is observable.
codex exec --model gpt-5.4 --full-auto < "$TMP/codex-prompt.txt" > "$TMP/codex-output.txt" 2>&1
echo "EXIT_CODE=$?" >> "$TMP/codex-output.txt"
```

**Do NOT discard stderr with `2>/dev/null`.** Codex emits reliability signals (`CreateProcessWithLogonW failed: 1056`, `websocket`, `403`, `stream error`) on stderr. The Monitor tool can only react to what reaches the output file. Use `2>&1` to merge streams into the same log that Monitor tails.

**Critical: inline all context.** Unlike companion tasks, `codex exec` may not have reliable file access in all sandbox configurations — Windows especially can hit intermittent `CreateProcessWithLogonW failed: 1056` errors on PowerShell tool calls. Include the full artifact content, codebase context, and structured output contracts directly in the prompt text. With context inlined, these sandbox errors may occur but do NOT invalidate the review — progress continues on other tool calls. Only treat them as fatal if Monitor reports silence past the response-generation threshold.

**Prompt construction for CLI fallback:**
1. Take the same prompt you would send via `/codex:rescue`
2. Inline any file contents that were previously referenced by path
3. Keep the XML-tagged structure (`<task>`, `<context>`, `<structured_output_contract>`)
4. Include `validation-format.md` or `verdict-format.md` content inline

**Arming Monitor on the output file:**

The Monitor tool streams output without burning context on polling. Filter for status markers, error signatures, AND progress indicators so silence is distinguishable from a stuck task. The exact filter depends on the structured output contract used in the prompt — adapt as needed. A working starting point:

```bash
# Bash / Git Bash / WSL
tail -f "$TMP/codex-output.txt" 2>/dev/null | grep -E --line-buffered \
  "## Status|## Findings|## Summary|APPROVED|MINOR_ISSUES|CHANGES_REQUESTED|VALIDATED|PARTIALLY_VALIDATED|REJECTED|EXIT_CODE=|Error|ERROR|403|401|websocket|timeout|Killed|OOM|stream error|disconnected|authentication|CreateProcessWithLogonW|tokens used"
```

```powershell
# Native Windows PowerShell — Get-Content -Wait is the tail -f equivalent
Get-Content "$env:TEMP\codex-output.txt" -Wait | Select-String -Pattern '## Status|## Findings|## Summary|APPROVED|MINOR_ISSUES|CHANGES_REQUESTED|VALIDATED|PARTIALLY_VALIDATED|REJECTED|EXIT_CODE=|Error|ERROR|403|401|websocket|timeout|Killed|OOM|stream error|disconnected|authentication|CreateProcessWithLogonW|tokens used'
```

**Silence is not success** — if your filter would stay silent on a crash, broaden it. Cover every terminal verdict your structured-output contract emits, every runtime failure signature you'd act on, and at least one progress marker (`tokens used`, `thinking`) so alive-but-slow is distinguishable from dead.

**Timeout:** `timeout 600` requires GNU coreutils — not available on native Windows PowerShell/cmd. On Git Bash or WSL it works; on native Windows, omit the `timeout` wrapper and rely on Monitor's response-generation threshold (15 min silence → escalate). The Bash tool's own timeout parameter is a portable alternative when invoking `codex exec` from within Claude Code.

```bash
# Bash / Git Bash / WSL with GNU coreutils
timeout 600 codex exec --model gpt-5.4 --full-auto < "$TMP/codex-prompt.txt" > "$TMP/codex-output.txt" 2>&1
echo "EXIT_CODE=$?" >> "$TMP/codex-output.txt"

# Bash / Git Bash / WSL without timeout — rely on Monitor
codex exec --model gpt-5.4 --full-auto < "$TMP/codex-prompt.txt" > "$TMP/codex-output.txt" 2>&1
echo "EXIT_CODE=$?" >> "$TMP/codex-output.txt"
```

```powershell
# Native Windows PowerShell — no timeout, rely on Monitor
$prompt = Join-Path $env:TEMP 'codex-prompt.txt'
$log    = Join-Path $env:TEMP 'codex-output.txt'
Get-Content $prompt | codex exec --model gpt-5.4 --full-auto *> $log
"EXIT_CODE=$LASTEXITCODE" | Add-Content $log
```

**When CLI fallback also fails:** NOW stop and report to user with full diagnostics:
```
Codex failed via both companion (N retries) and direct CLI.
This indicates an API-level issue, not a local runtime problem.

Diagnostics: <specific findings>
Remediation: Check OpenAI API status, verify auth (codex auth login), check network connectivity.
```

### Skill-tool Fallback

The Skill tool invocations (`/codex:status`, `/codex:result`, `/codex:cancel`) are the primary way to interact with an active Codex job. Only when a Skill tool errors (e.g., `disable-model-invocation`) should you fall back to shelling out to the companion script directly — and in that case the script lives in the **codex plugin's** cache, not in codex-collaboration's cache. Do NOT hardcode `${CLAUDE_PLUGIN_ROOT}/../codex/scripts/codex-companion.mjs` — that path is wrong when codex and codex-collaboration come from different marketplaces, which is the default installation layout.

Resolve the companion path at runtime by listing the cache:

```bash
COMPANION=$(ls -t "$HOME/.claude/plugins/cache"/*/codex/*/scripts/codex-companion.mjs 2>/dev/null | head -1)
node "$COMPANION" status
```

On Windows PowerShell:
```powershell
$companion = Get-ChildItem -Path "$HOME/.claude/plugins/cache" -Recurse -Filter codex-companion.mjs | Select-Object -First 1
node $companion.FullName status
```

If no companion script is found, the codex plugin is not installed — report and abort.

### Polling Efficiency

Excessive status polling wastes conversation context (20-30 bash commands observed in real sessions). Follow these rules:

1. **Use the Monitor tool** for waiting on task completion — it streams events without burning context
2. **One manual health check** at 60 seconds post-dispatch (Task Health Verification)
3. **One manual check** if Monitor times out or reports an unexpected event, and one immediately before retrieving results
4. **Do NOT poll in a loop** with repeated bash commands — this is the single largest source of context waste in observed sessions
