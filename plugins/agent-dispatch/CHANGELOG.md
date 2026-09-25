# Changelog

All notable changes to the **agent-dispatch** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-25

### Added
- Label an issue `agent` and a scheduled tick on your machine runs issue-to-pr on it headless, under your own Claude Code or Codex login.
- Reply on the issue or its PR and the next tick picks the run back up; only your own comments and labels count.
- A run that hangs is stopped after four hours, and a run that dies is marked failed with a pointer to its local log.
- A logged-out or rate-limited CLI pauses dispatching instead of failing every queued issue.
- A setup skill that checks the machine and prints the labels, repo list and scheduler entry for Windows, macOS or Linux.
