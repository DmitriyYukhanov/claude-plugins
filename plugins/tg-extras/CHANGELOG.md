# Changelog

All notable changes to the **tg-extras** plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [2.0.0] - 2026-04-04

### Added
- Voice message transcription via PostToolUse hook on Telegram `download_attachment`
- Uses `faster-whisper` (local Whisper) for offline speech-to-text
- Configurable model size via `WHISPER_MODEL` env var (default: `base`)
- `voice-to-text-config` skill — guided setup for whisper installation, model download, and end-to-end verification

### Changed
- Rename plugin from `tg-alerts` to `tg-extras` to reflect broader Telegram utility scope
- Absorb `tg-alerts` skill into this plugin (unchanged)
- Voice hook only triggers for `.oga` files (Telegram voice messages), ignoring photos, documents, and other audio formats
- Hook detects missing `faster-whisper` or uncached model and outputs actionable guidance instead of silently failing

## [1.0.1] - 2026-04-03

### Added
- CHANGELOG.md with backfilled version history

## [1.0.0] - 2026-03-28

### Added
- `tg-alerts` skill with interactive 7-phase setup flow
- Step-by-step @BotFather and chat ID discovery guide (private chat, group, channel, forum topics)
- Reference implementations for Python async (FastAPI), Python sync (Django/Flask), and Node.js/TypeScript (Express/NestJS)
- Built-in deduplication, HTML formatting, graceful failure handling, and fire-and-forget delivery
- Framework-specific integration guidance for error handlers and logging bridges
