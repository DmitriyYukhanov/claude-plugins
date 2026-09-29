---
name: tg-account
description: Read and write Telegram as the user through the local Telegram Desktop session (tdata), no login or QR: find chats, export messages to text, create groups, send and pin messages. E.g. "выгрузи чат", "создай группу в телеге".
---

# Telegram as the user, from local tdata

Reads the auth key from Telegram Desktop's `tdata` (opentele), builds an in-memory Telethon session and talks to Telegram as that account. Telegram Desktop may stay open. Works with Telegram Desktop (tdesktop) only, not the native macOS "Telegram" app.

## Rules

- **Never call `log_out()`** and never save the session to disk. The key belongs to the owner's real desktop session; `log_out` would kill it.
- **Reads are free, writes are gated.** Finding and exporting need no confirmation. Before any `tg_write.py` call, show the owner the account, the target chat or members, and the exact text, then wait for a clear yes. One yes covers the calls it described, nothing later.
- Write only through `tg_write.py`. Never delete, edit, leave, join, react or mark read unless the owner asked for exactly that.
- **One client per account at a time.** Parallel runs on the same key cause a storm of `MSGID_DECREASE_RETRY`.
- Exports can hold private conversations. Write them only where the user asked or to the default folder below, never into a git repo unless told so, and do not paste whole DMs into chat.
- If `connect()` hangs, Telegram is likely blocked on the network; ask the owner to bring up a VPN.

## Setup (once)

```bash
python3.12 "<skill dir>/scripts/setup.py"      # Windows: py -3.12 "<skill dir>/scripts/setup.py"
```

Creates `~/.tg-account/venv`, installs `opentele==1.15.1` + `telethon==1.45.0` and patches opentele for Telegram Desktop 7.x (unknown map key type 23 gives "No account has been loaded"; a recursion in the `api` setter). If setup says a patch target is not found, opentele changed; re-check both patches in `opentele/td/account.py`. Idempotent: if the venv python is missing, just run it again.

`tdata` defaults to the standard Telegram Desktop location (`%APPDATA%/Telegram Desktop/tdata`, `~/Library/Application Support/Telegram Desktop/tdata`, `~/.local/share/TelegramDesktop/tdata`). A portable install needs env `TG_TDATA` pointing at its `tdata` folder.

## Use

`PY` is `~/.tg-account/venv/Scripts/python.exe` on Windows, `~/.tg-account/venv/bin/python` elsewhere. `S` is this skill's `scripts/` folder. Call scripts by absolute path from any directory.

```bash
"$PY" "$S/tg_find.py"                              # accounts in tdata
"$PY" "$S/tg_find.py" alice "work chat"            # dialogs whose title or @username matches, with ids
"$PY" "$S/tg_export.py" @somechannel 2026-09-01 ~/Downloads/tg-exports/somechannel-2026-09-24
"$PY" "$S/tg_export.py" -1001234567890 2026-09-01 <out> <account id>
"$PY" "$S/tg_write.py" group "Project X" @alice 123456789 --account <id>   # prints group=<id>
"$PY" "$S/tg_write.py" send <group id> post.md --pin --account <id>         # prints message=<id> pinned
```

- **CHAT / MEMBER**: `@username`, `t.me/...` link, or a numeric id from `tg_find.py` (`-100...` for supergroups and channels, `-...` for basic groups, a positive id for a user). For a chat named in words ("чат с Васей"), run `tg_find.py` with a keyword first and take the id.
- **Account**: reads use the first account that can open the chat unless you pass one. Writes need `--account` when `tdata` holds more than one account, so a message never goes out from the wrong one.
- In PowerShell quote `'@name'`: a bare `@name` is splatting and the argument silently disappears.
- **Default export folder** when the user names no place: `~/Downloads/tg-exports/<chat>-<YYYY-MM-DD>/`.
- Big chats take a while (~78k messages in a few tens of minutes). Run long exports in the background and wait for the final line `messages=... days=... range=... skips=...`.

## Writing

- `send` reads the text from a UTF-8 file, so multi-line posts survive any shell. Telethon Markdown applies: `**bold**`, `__italic__`, `` `code` ``, `[text](url)`. Link previews are off.
- `--pin` pins silently (no notification to members). Pin several posts by sending each with `--pin`.
- `group` creates a basic group with the account and the listed members. Anyone whose privacy settings block invites is reported on stderr; send them an invite link by hand.
- Text for other people goes through the humanizer first if that skill is installed.

## Export output

`OUT/YYYY-MM-DD.txt`, one line per message, sorted by id, local time:

```
[14:02] #1234567 ->#1234501 Name Surname: text on one line
```

Text only: media without a caption becomes `[media]`, service messages are dropped, forum topics are merged into one stream. Grep it, or for a big chat filter first and hand the rest to agents.

## Why manual pagination

On big forums Telegram answers `MSGID_DECREASE_RETRY` for some offsets, and Telethon's `iter_messages` gives up after six tries. `tg_export.py` steps `offset_id` down by 7 and continues; each skip can lose up to 7 messages. 24 skips over 78k messages is normal. `tg_find.py` can hit the same error on `get_dialogs`; it prints "dialogs unavailable right now", just retry later.
