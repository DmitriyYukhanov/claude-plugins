"""Write to Telegram as a tdata account: create a group, send a message, pin it.

Every call acts as the account owner and is seen by everyone in the chat. Show the owner
the exact target and text and get a yes before running it.

Usage:
  tg_write.py group TITLE MEMBER [MEMBER ...] [--account ID]   create a group, print its id
  tg_write.py send CHAT FILE [--pin] [--account ID]           send FILE (UTF-8, Markdown), print message id

MEMBER and CHAT: @username, t.me link or numeric id from tg_find.py.
--account is required when tdata holds more than one account.
"""
import argparse, asyncio, pathlib, sys
from telethon import functions
from tgsess import accounts, client_for, open_chat, peer

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
sub = p.add_subparsers(dest="cmd", required=True)
g = sub.add_parser("group")
g.add_argument("title")
g.add_argument("members", nargs="+")
s = sub.add_parser("send")
s.add_argument("chat")
s.add_argument("file")
s.add_argument("--pin", action="store_true")
for x in (g, s):
    x.add_argument("--account")
a = p.parse_args()

if a.account is None:
    ids = [x.UserId for x in accounts()]
    if len(ids) != 1:
        sys.exit(f"tdata holds accounts {ids}; pass --account to pick who writes")
    a.account = ids[0]


async def group():
    c = client_for(a.account)
    await c.connect()
    try:
        await c.get_dialogs()  # numeric member ids resolve only from the dialog cache
        users = [await c.get_entity(peer(m)) for m in a.members]
        r = await c(functions.messages.CreateChatRequest(users=users, title=a.title))
        chat = getattr(r, "updates", r).chats[0]
        for m in getattr(r, "missing_invitees", []):
            print(f"not added (their privacy settings): user {m.user_id}", file=sys.stderr)
        print(f"group={-chat.id} title={chat.title!r}")
    finally:
        await c.disconnect()


async def send():
    text = pathlib.Path(a.file).read_text(encoding="utf-8").strip()
    c, ent, _ = await open_chat(a.chat, a.account)
    try:
        m = await c.send_message(ent, text, link_preview=False)
        if a.pin:
            await c.pin_message(ent, m, notify=False)
        print(f"message={m.id}{' pinned' if a.pin else ''}")
    finally:
        await c.disconnect()

asyncio.run(group() if a.cmd == "group" else send())
