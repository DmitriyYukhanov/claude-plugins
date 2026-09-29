"""Export a Telegram chat to per-day text files.

Usage: tg_export.py CHAT SINCE OUT [ACCOUNT_ID]
  CHAT        @username, t.me link or numeric id (-100..., user id for a DM); see tg_find.py
  SINCE       first day to keep, YYYY-MM-DD (local time)
  OUT         output dir, one YYYY-MM-DD.txt per day
  ACCOUNT_ID  tdata account to read with; default: first account that can open CHAT

Line format, sorted by id, local time:  [HH:MM] #id ->#reply Name: text

Pagination is manual: on large forums Telegram answers MSGID_DECREASE_RETRY for some
offsets. Telethon's iter_messages gives up after 6 tries, so we step offset_id down by 7
and carry on. Each step can skip up to 7 messages; the skip count is printed at the end.
"""
import asyncio, collections, datetime as dt, os, sys
from telethon import errors
from telethon.tl.types import User
from tgsess import open_chat

if len(sys.argv) not in (4, 5):
    sys.exit(__doc__)
CHAT, SINCE, OUT = sys.argv[1:4]
ACC = sys.argv[4] if len(sys.argv) == 5 else None
since = dt.datetime.fromisoformat(SINCE).astimezone()
os.makedirs(OUT, exist_ok=True)


def name(s):
    if s is None:
        return "?"
    if isinstance(s, User):
        return " ".join(x for x in (s.first_name, s.last_name) if x) or s.username or "?"
    return getattr(s, "title", None) or "?"


async def main():
    c, ent, acc = await open_chat(CHAT, ACC)
    print(f"account {acc}: {name(ent)}", flush=True)
    days = collections.defaultdict(list)
    n = offset = skips = 0
    done = False
    while not done:
        try:
            batch = await c.get_messages(ent, limit=100, offset_id=offset)
        except (errors.RPCError, ValueError) as ex:
            if isinstance(ex, errors.RPCError) and "MSGID_DECREASE" not in str(ex) and "internal issues" not in str(ex):
                raise
            if not offset:
                offset = (await c.get_messages(ent, limit=1))[0].id + 1
            offset -= 7
            skips += 1
            await asyncio.sleep(1)
            continue
        if not batch:
            break
        for m in batch:
            t = m.date.astimezone()
            if t < since:
                done = True
                break
            txt = (m.message or "").replace("\n", " ").strip() or ("[media]" if m.media else "")
            if not txt:
                continue
            head = f"[{t:%H:%M}] #{m.id}"
            if m.reply_to and getattr(m.reply_to, "reply_to_msg_id", None):
                head += f" ->#{m.reply_to.reply_to_msg_id}"
            days[f"{t:%Y-%m-%d}"].append((m.id, f"{head} {name(m.sender)}: {txt}"))
            n += 1
        offset = batch[-1].id
        if n % 5000 < 100:
            print("...", n, f"{t:%Y-%m-%d %H:%M}", "skips", skips, flush=True)
        await asyncio.sleep(0.25)
    await c.disconnect()
    for d, lines in days.items():
        with open(os.path.join(OUT, d + ".txt"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(line for _, line in sorted(dict(lines).items())))
    rng = f"{min(days)}..{max(days)}" if days else "empty"
    print(f"messages={n} days={len(days)} range={rng} skips={skips}")

asyncio.run(main())
