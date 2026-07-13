# tg-voice

Transcribe Telegram voice messages with local Whisper. A PostToolUse hook picks up `.oga` voice files downloaded via the Telegram channel plugin and turns the audio into text automatically.

## Installation

```bash
/plugin install tg-voice@dmitriy-claude-plugins
```

## Requirements

- `faster-whisper`: `pip install faster-whisper`
- The Telegram channel plugin for Claude Code (the hook fires on its `download_attachment` tool)

## Features

### Hook: automatic transcription

Fires after `download_attachment` from the Telegram plugin and runs `scripts/transcribe-voice.py` on `.oga` voice messages (120-second timeout).

### Skill: `/voice-to-text-config`

Guided setup: checks the faster-whisper installation, downloads the Whisper model you pick, and verifies the hook end to end.

## Configuration

Model size comes from the `WHISPER_MODEL` env var. Options: `tiny` (~40MB, fastest), `base` (~75MB, default), `small` (~250MB), `medium` (~750MB, most accurate on CPU).

## License

MIT
