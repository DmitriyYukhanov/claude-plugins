"""List tdata accounts and, per account, the dialogs whose title or @username contains any keyword.

Usage: tg_find.py [keyword ...]      (no keywords = accounts only)
"""
import asyncio, sys
from telethon import errors
from tgsess import accounts, client_for

KW = [k.lower().lstrip("@") for k in sys.argv[1:]]


async def main():
    for a in accounts():
        print(f"account {a.UserId} (dc {a.MainDcId})")
        if not KW:
            continue
        c = client_for(a.UserId)
        await c.connect()
        try:
            async for d in c.iter_dialogs():
                e = d.entity
                user = getattr(e, "username", None)
                if any(k in f"{d.name} {user or ''}".lower() for k in KW):
                    print(f"  {d.id}  {d.name!r}  {'@' + user if user else ''}{'  forum' if getattr(e, 'forum', False) else ''}")
        except errors.RPCError as ex:  # e.g. MSGID_DECREASE_RETRY outlasting Telethon's retries
            print(f"  dialogs unavailable right now: {ex}; retry later")
        finally:
            await c.disconnect()

asyncio.run(main())
