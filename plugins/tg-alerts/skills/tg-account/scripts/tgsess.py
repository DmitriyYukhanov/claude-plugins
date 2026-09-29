"""Telethon client built from the local Telegram Desktop tdata.

The auth key lives only in memory (StringSession, never saved). Never call log_out():
it would terminate the owner's real desktop session.
"""
import os, pathlib, sys
from opentele.td import TDesktop
from opentele.api import API
from telethon import TelegramClient, errors
from telethon.sessions import StringSession
from telethon.crypto import AuthKey


def _default_tdata():
    home = pathlib.Path.home()
    if sys.platform == "win32":
        return pathlib.Path(os.environ.get("APPDATA", home)) / "Telegram Desktop" / "tdata"
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / "Telegram Desktop" / "tdata"
    return home / ".local" / "share" / "TelegramDesktop" / "tdata"


TDATA = os.environ.get("TG_TDATA") or str(_default_tdata())
DC = {1: "149.154.175.53", 2: "149.154.167.51", 3: "149.154.175.100", 4: "149.154.167.91", 5: "91.108.56.130"}


def accounts():
    if not os.path.isdir(TDATA):
        raise SystemExit(f"no tdata at {TDATA}; set TG_TDATA to the Telegram Desktop tdata folder")
    return TDesktop(TDATA).accounts


def client_for(user_id):
    acc = next((a for a in accounts() if a.UserId == int(user_id)), None)
    if acc is None:
        raise SystemExit(f"account {user_id} not in {TDATA}; run tg_find.py to list accounts")
    s = StringSession()
    s.set_dc(acc.MainDcId, DC[acc.MainDcId], 443)
    s.auth_key = AuthKey(acc.authKey.key)
    # Same api_id as the desktop app that created the key.
    api = API.TelegramDesktop
    return TelegramClient(s, api.api_id, api.api_hash, device_model=api.device_model,
                          system_version=api.system_version, app_version=api.app_version,
                          lang_code=api.lang_code, system_lang_code=api.system_lang_code)


def peer(ref):
    """@username / t.me link stay strings, numeric ids become ints."""
    return int(ref) if ref.lstrip("-").isdigit() else ref


async def open_chat(chat, acc=None):
    """Connect as ACC, or as the first account that can open CHAT. Returns (client, entity, account id)."""
    target = peer(chat)
    for a in [acc] if acc else [x.UserId for x in accounts()]:
        c = client_for(a)
        await c.connect()
        try:
            if isinstance(target, int):  # numeric ids resolve only from the dialog cache
                try:
                    await c.get_dialogs()
                except (ValueError, errors.RPCError):
                    pass
            return c, await c.get_entity(target), a
        except (ValueError, errors.RPCError) as ex:
            print(f"account {a}: cannot open {chat}: {ex}")
            await c.disconnect()
    raise SystemExit("no account can open " + chat)
