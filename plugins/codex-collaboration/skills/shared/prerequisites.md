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
