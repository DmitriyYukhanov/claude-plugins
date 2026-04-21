# Changelog

All notable changes to the **codex-collaboration** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.7.0] - 2026-04-21

### Fixed
- Broken companion script path replaced with Skill tool invocations (`/codex:status`, `/codex:result`, `/codex:cancel`, `/codex:rescue --fresh`) — the old `${CLAUDE_PLUGIN_ROOT}/../codex/scripts/...` path never resolved when the two plugins lived in different marketplace caches
- Preflight Check numbering — failure modes are now sub-items of step 1, not separate top-level steps
- Health-check wording normalized — all skills now point to `/codex:status` as the primary path, with companion script only mentioned in the explicit fallback section
- Connectivity test distinguishes dead runtime from Skill-gate errors — `disable-model-invocation` no longer misclassified as a dead connection
- Liveness probe capped at 90 seconds (down from unbounded); harmonized across prerequisites.md and collaborative-loop
- Direct CLI Fallback no longer discards stderr with `2>/dev/null` — runtime errors (sandbox failures, websocket errors, auth issues) are now merged into the output log so Monitor can see them
- `EXIT_CODE=` completion marker now appends to the same log file Monitor tails (previously echoed to terminal, making the marker unobservable)
- Internal contradiction removed — stale "poll every 5 minutes" guidance conflicted with the Polling Efficiency section that says to use Monitor without looped polls

### Added
- Distinct branch for Skill-gate rejection (user denies `/codex:rescue` or `/codex:review` at the permission prompt) covering both the validate phase (Step 4) and review phase (Step 6) — Auto-Retry Protocol no longer fires against a non-dispatched job; instead the user is offered Direct CLI Fallback and the decision stays with them
- Concrete Monitor filter examples with both Bash (tail -f + grep) and PowerShell (Get-Content -Wait + Select-String) variants, framed as a starting point to adapt per workflow
- PowerShell-native `codex exec` example for native Windows users — prior Bash-only snippet failed under PowerShell due to `$TMP`, stdin redirection, and `>>` append differences
- Windows sandbox reliability note — intermittent `CreateProcessWithLogonW failed: 1056` errors may occur and do not invalidate a review when context is inlined; only Monitor silence past the response-generation threshold signals a real stall
- Cross-platform temp file and timeout guidance — Unix/`$TMPDIR`, Windows/`$TEMP`, and documented that `timeout 600` requires GNU coreutils (not native Windows cmd/PowerShell)

## [1.6.0] - 2026-04-16

### Added
- Direct CLI Fallback — when companion retries fail, bypass the broker and run `codex exec` directly before giving up
- Session reliability tracking — after the first companion failure, lower patience thresholds and prefer CLI for complex tasks
- Code-level verification in cross-review — when Codex cross-validation fails, verify single-source findings against source code instead of marking them all "unverified"
- Graceful degradation for cross-validation — initial review still requires both models, but cross-validation can continue with partial results
- Polling efficiency guidance — use Monitor tool for waiting, limit manual bash checks to reduce context waste
- Explicit `codex:result` error handling — fall back to companion bash commands when Skill tool returns `disable-model-invocation`

### Changed
- Reduce response-generation max wait from 45 minutes to 15 minutes — session data shows silence >10 min is almost always a dead task
- In degraded sessions, reduce max wait further to 8 minutes and skip to CLI after one companion retry
- Runtime failure policy now requires CLI fallback attempt before stopping — "STOP and report" is the last resort, not the first
- Clarify that "both models required" applies to initial review; cross-validation can degrade gracefully

## [1.5.0] - 2026-04-15

### Changed
- Remove degraded mode from cross-review — both models are now required, same as collaborative-loop
- Replace PID-based liveness checks with companion task status checks — Windows CLI launcher exits immediately, making `tasklist` unreliable
- Increase starting-stuck threshold from 2 minutes to 5 minutes to reduce false positives
- Replace log-staleness timer with response-generation awareness (wait up to 45 min after tool calls go quiet)
- Increase max auto-retries from 1 to 2, with diagnostic check between retries
- Polling interval from 2 minutes to 5 minutes to reduce context waste

### Added
- Response-generation awareness — after tool calls go quiet, Codex is likely composing its response (10-30 min); do NOT cancel
- Diagnostic escalation protocol — run connectivity test and check companion status for errors before blindly retrying
- WebSocket connection limit guidance — detect and recover from OpenAI's 60-minute WebSocket TTL
- Common failure signature table with specific remediation steps

### Removed
- `tasklist` / `kill -0` PID liveness commands — replaced by companion status checks
- Degraded mode (Claude-only fallback) from cross-review — cross-review now ABORTs on Codex failure

## [1.4.0] - 2026-04-14

### Added
- Context gathering guidance for non-code artifacts — reviewers now read referenced source files before reviewing design/plan/architecture specs
- Cross-reference triage table showing which reviewers found each issue at what severity
- Fallback path when `/codex:status` Skill tool fails with `disable-model-invocation`
- Stale task dismissal step in auto-retry protocol to ignore late-arriving notifications from dead tasks

### Fixed
- Flow interruption after Codex setup — setup → dispatch is now explicitly uninterruptible
- Triage → cross-validation flow runs without stopping for user acknowledgment

## [1.3.0] - 2026-04-14

### Added
- PID liveness verification within 30 seconds of Codex dispatch to catch dead processes early
- Starting-stuck detection at 2-minute threshold (down from 9+ minutes in practice)
- Fresh `/codex:setup` re-invocation before each Codex dispatch to prevent pipe-mismatch zombie tasks
- Auto-retry protocol on dead process: re-setup then re-dispatch with max 1 retry

### Changed
- Hang detection is now two-tier: PID liveness (fast) then log staleness (slow)
- Stale-log monitor re-runs `/codex:setup` before retry to establish fresh runtime

## [1.2.0] - 2026-04-08

### Added
- Cross-validation step — each model verifies the other's findings before presenting to user
- Evidence-based dispute resolution — resolve disagreements via docs/code research instead of always asking the user
- Per-artifact-type domain agents for design, plan, and architecture reviews
- REFINE verdict — agree with an issue but adjust its severity or fix
- Fast-path exits for zero findings, full agreement, and degraded mode

### Changed
- Evidence-first resolution replaces immediate user escalation as core principle

## [1.1.0] - 2026-04-04

### Added
- Liveness check after preflight to catch zombie broker processes
- Stale-log monitor for hang detection with automatic single-retry

### Changed
- Codex monitoring uses log-staleness detection instead of hard timeouts

## [1.0.2] - 2026-04-03

### Fixed
- Add `--fresh` to all `/codex:rescue` invocations to prevent thread-resume prompts during automated workflows

## [1.0.1] - 2026-03-29

### Fixed
- Minor refinements to collaboration workflows

## [1.0.0] - 2026-03-29

### Added
- `collaborative-loop` skill — sequential drive/validate/act cycles between Claude and Codex
- `cross-review` skill — parallel dual review with independent analysis, cross-validation, and triage
- Unified plugin replacing separate collaborative-loop and cross-review plugins
