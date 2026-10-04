# tg-essentials

Telegram toolkit for agents. Error alerts for your projects go out through a bot, and everything you do in Telegram as yourself (chats, exports, groups, posts, checklists) runs through your local Telegram Desktop session.

Renamed from `tg-alerts` in 2.0.0. If you had the old plugin, uninstall `tg-alerts` and install `tg-essentials`. The alerts skill is now `tg-essentials:tg-alerts`, so update any CLAUDE.md or AGENTS.md line that names `tg-alerts:tg-alerts`.

## Installation

```bash
/plugin install tg-essentials@dmitriy-claude-plugins
```

## Features

### Skill: `tg-alerts`

Interactive setup in seven phases:

1. Assess the project (language, framework, existing error handling)
2. Create a bot with @BotFather
3. Discover the chat, channel, or forum-topic ID
4. Generate the alert service code
5. Integrate with the framework
6. Wire environment variables
7. Test end to end

Reference implementations included for Python async (FastAPI), Python sync (Django/Flask), and Node.js/TypeScript (Express/NestJS). The generated service deduplicates repeated errors, formats messages as HTML, delivers fire-and-forget, and never crashes the host app when Telegram is unreachable.

### Skill: `tg-account`

Talks to Telegram as you, using the session Telegram Desktop already keeps on disk. You don't log in or scan a QR code.

- Find chats and export their history into one text file per day
- Include local transcripts of voice messages and video notes automatically
- Create a group, send, edit and pin posts, and set the group photo
- Post a native checklist that members can tick (sending one needs Telegram Premium)

Every write waits for your yes first. Requires Telegram Desktop and Python 3.12. Run the skill's setup script once; a portable Telegram install also needs `TG_TDATA` pointing at its `tdata` folder.

Normal exports include voice messages and video notes on their original message lines. On the first note without a cached transcript, the exporter installs any missing transcription dependencies and downloads Whisper `small` (about 500 MB). One local CPU process handles recognition without an API key or agent tokens. Successful transcripts are cached inside the export's `.transcripts` folder; temporary media files are deleted after processing. Keep that folder private along with the exported chat. Failures stay visible and retry on the next export. Use `--no-transcribe` only when you want to skip speech.

## Usage

```text
Add Telegram error alerts to this project
Export last week of the work chat
Create a Telegram group with @alice, pin the agenda and a checklist
```

## License

MIT
