---
name: tg-alerts
description: Use when adding Telegram error notifications to any project. Guides through bot creation with @BotFather, chat/channel/forum-topic ID discovery, alert service implementation with deduplication and graceful failure, and framework-specific integration for Python (async/sync) and Node.js.
---

# Telegram Error Alerts

Adds operational error alerts to any project via a dedicated Telegram bot. Alerts go to a private channel, group, or forum topic — not to end users. Battle-tested pattern with deduplication, HTML formatting, and crash-proof error handling.

## When to Use

- User asks to add error notifications, Telegram alerts, or operational monitoring
- Setting up a new deployment and want to know when things break
- NOT for: user-facing bot messages or interactive Telegram features

## Setup Flow

This skill is **interactive**. Each phase involves asking the user questions or guiding them through Telegram actions.

```dot
digraph flow {
    rankdir=LR;
    "Assess\nProject" -> "Create\nBot" -> "Get\nChat ID" -> "Generate\nCode" -> "Integrate" -> "Test";
}
```

---

### Phase 1: Assess Project

Detect from codebase or ASK:
1. **Language** — Python / Node.js / TypeScript / other
2. **Framework** — FastAPI, Django, Flask, Express, NestJS, Hono, etc.
3. **Async or sync** — determines implementation variant
4. **Already has a Telegram bot?** — alert bot MUST be separate from any main bot

---

### Phase 2: Create Alert Bot

Guide the user through these Telegram steps:

> 1. Open Telegram, find **@BotFather**
> 2. Send `/newbot`
> 3. Name: something like **"MyApp Alerts"**
> 4. Username: something like `myapp_alerts_bot`
> 5. BotFather replies with a token — **copy it**
> 6. Save as `ALERT_BOT_TOKEN` in `.env`

ASK the user to confirm they have the token before proceeding.

---

### Phase 3: Get Chat ID

**ASK:** "Where should alerts go?"

| Target | Best for | Complexity |
|--------|----------|------------|
| **Private chat** | Solo dev | Easiest |
| **Group** | Small team | Easy |
| **Channel** | Read-only broadcast | Medium |
| **Forum topic** | Organized by category | Medium |

Guide based on their choice:

#### Option A: Private Chat

> 1. Open Telegram, find your new alert bot
> 2. Send it any message (e.g., "hello")
> 3. Run in terminal:

```bash
curl -s "https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates" | python3 -m json.tool
```

> 4. Find `"chat": {"id": 123456789}` — that positive number is your `ALERT_CHAT_ID`

#### Option B: Group

> 1. Create a Telegram group (or use existing)
> 2. Add the alert bot to the group
> 3. Send any message in the group
> 4. Run the `getUpdates` curl above
> 5. Find `chat.id` — **negative number** like `-1001234567890`

#### Option C: Channel

> 1. Create a channel (or use existing)
> 2. Add the alert bot as **administrator** (needs "Post Messages" permission)
> 3. Post any message in the channel
> 4. Run `getUpdates`
> 5. Find `"channel_post"` -> `"chat"` -> `"id"` — negative, starts with `-100`

#### Option D: Forum Topic

> 1. Create a group -> Settings -> enable **Topics**
> 2. Add the bot to the group
> 3. Create a topic (e.g., "Errors")
> 4. Send a message **inside that topic**
> 5. Run `getUpdates`
> 6. Find TWO values:
>    - `chat.id` -> `ALERT_CHAT_ID`
>    - `message_thread_id` -> `ALERT_THREAD_ID`

#### Verify IDs

**Always test** before writing code:

```bash
curl -s -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
  -d chat_id=<CHAT_ID> -d "text=Test alert" -d parse_mode=HTML
```

For forum topics, add `-d message_thread_id=<THREAD_ID>`.

If the message appears in Telegram, proceed to Phase 4.

**Troubleshooting empty `getUpdates`:**
- Send another message, then run curl immediately (updates expire)
- For channels: bot must be **admin**, not just member
- For groups: send `/setprivacy` to @BotFather -> set to **Disabled**

---

### Phase 4: Generate Alert Service

Use the appropriate reference implementation from this skill's directory:

| Stack | Reference File |
|-------|---------------|
| Python async (FastAPI, aiohttp) | `references/alert_service_async.py` |
| Python sync (Django, Flask) | `references/alert_service_sync.py` |
| Node.js / TypeScript | `references/alert_service_node.ts` |

Read the reference file and **adapt** to the project:
- Match code style, naming conventions, import patterns
- Use the project's existing HTTP client if available
- Place where services/utils live in the project structure
- Add env vars to the project's config system

---

### Phase 5: Framework Integration

Wire alert service into the project's error handling. The pattern:

1. **Initialize on startup** (only if env vars present)
2. **Attach logging handler** to root logger (captures all `logger.error()` / `console.error()`)
3. **Add unhandled exception handler** specific to the framework
4. **Send lifecycle alert** on startup and shutdown

| Framework | Unhandled Exception Hook | Startup Hook |
|-----------|------------------------|-------------|
| FastAPI | `@app.exception_handler(Exception)` | `lifespan` context manager |
| Django | Custom middleware + 500 handler | `AppConfig.ready()` |
| Flask | `@app.errorhandler(Exception)` | App factory / `before_first_request` |
| Express | `app.use((err, req, res, next) => ...)` | After `app.listen()` |
| NestJS | `@Catch()` exception filter | `onModuleInit()` |

---

### Phase 6: Environment Variables

Add to `.env` and `.env.example`:

```env
# Telegram operational alerts (optional)
# ALERT_BOT_TOKEN=123456:ABC-DEF...
# ALERT_CHAT_ID=-1001234567890
# ALERT_THREAD_ID=42
```

Ensure the config treats these as **optional** — alerting gracefully disables when not configured:
```
alerting_enabled = bool(ALERT_BOT_TOKEN and ALERT_CHAT_ID)
```

---

### Phase 7: Test

1. Start the app with alert env vars set
2. Check for **startup lifecycle alert** in Telegram
3. Trigger an intentional error (e.g., hit a broken endpoint)
4. Verify **error alert** appears with traceback
5. Trigger **same error again** — verify dedup blocks the duplicate
6. Stop the app — verify **shutdown alert**

---

## Alert Message Format

Consistent across all stacks — use Telegram HTML parse mode:

```
🔴 <b>Error</b>
<pre>Env: production
Error: ValueError
Context: [module.name] error message

Traceback (most recent call last):
  ...</pre>

🟡 <b>Warning</b>
<pre>Env: production
Some warning message</pre>

🟢
<pre>Application started
Env: production</pre>
```

---

## Critical Design Rules

Non-negotiable for every implementation:

1. **Alert failures NEVER crash the app** — wrap all sending in try/except or try/catch
2. **Log alert failures at DEBUG** — ERROR would trigger the handler again -> infinite loop
3. **Deduplicate by exception location** — key: `{ExcType}:{lineno}@{filename}`. One alert per crash site
4. **Truncate to 3500 chars** — Telegram limit is 4096; stay well under
5. **HTML-escape all dynamic content** — tracebacks contain `<>&` breaking Telegram HTML
6. **Separate bot** — never reuse the main app bot for alerts
7. **Include environment** — every alert shows dev/staging/prod
8. **Make alerting optional** — app runs normally without alert env vars
9. **Fire-and-forget** — async: `create_task()`, sync: daemon thread. Never block requests
10. **Cap dedup set at ~10k** — clear when full to prevent unbounded memory growth

## Common Mistakes

| Mistake | Consequence | Fix |
|---------|-------------|-----|
| Same bot for app + alerts | Alerts fail when app bot is down | Separate bot token |
| No dedup | Hundreds of identical alerts | Dedup by exc type + location |
| `await send_alert()` in request path | Slow requests if Telegram lags | Fire-and-forget |
| Log send failure at ERROR | Infinite alert loop | Log at DEBUG |
| No truncation | Telegram silently drops message | Truncate to 3500 chars |
| Raw HTML in traceback | Broken formatting | `html.escape()` all content |
| Alert required for startup | App won't start without Telegram | Optional via `alerting_enabled` |
| `getUpdates` returns empty | Can't find chat ID | Send message first, curl immediately |
