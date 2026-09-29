# tg-alerts

Add operational error alerts to any project via a dedicated Telegram bot. Alerts go to a private channel, group, or forum topic, not to end users.

## Installation

```bash
/plugin install tg-alerts@dmitriy-claude-plugins
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
- Create a group, send a post and pin it. Every write waits for your yes first

Requires Telegram Desktop and Python 3.12. Run the skill's setup script once; a portable Telegram install also needs `TG_TDATA` pointing at its `tdata` folder.

## Usage

```text
Add Telegram error alerts to this project
Export last week of the work chat
Create a Telegram group with @alice and pin the agenda
```

## License

MIT
