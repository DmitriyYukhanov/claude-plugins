# Changelog

All notable changes to the **agent-dispatch** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-26

### Added
- Run issue-to-pr headless on a scheduled tick whenever you label an issue `agent`, under your own Claude Code or Codex login.
- Resume a parked run when you reply on its issue or PR; only your own comments and labels count.
- Hold an issue whose title or body someone else edited after you labelled it `agent`, until you label it `agent` again.
- Stop a hung run after four hours and mark a dead run failed with a pointer to its local log.
- Pause dispatching on a logged-out or rate-limited CLI instead of failing every queued issue.
- Add a setup skill that checks the machine and prints the labels, repo list and scheduler entry for Windows, macOS or Linux.
