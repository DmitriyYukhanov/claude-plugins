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

## Usage

```text
Add Telegram error alerts to this project
```

## License

MIT
