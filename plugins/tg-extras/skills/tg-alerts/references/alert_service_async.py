"""Telegram alert service — async variant (FastAPI, aiohttp, etc.).

Reference implementation. Adapt to your project's style and structure.
Dependencies: httpx (or use aiohttp if already in deps).
"""

from __future__ import annotations

import asyncio
import html
import logging
import os
import traceback

import httpx

logger = logging.getLogger(__name__)

_ENV = os.environ.get("ENVIRONMENT", "development")
_alert_service: AlertService | None = None


def get_alert_service() -> AlertService | None:
    return _alert_service


def init_alert_service(
    bot_token: str, chat_id: str, *, thread_id: int | None = None,
) -> AlertService:
    global _alert_service  # noqa: PLW0603
    _alert_service = AlertService(bot_token, chat_id, thread_id=thread_id)
    return _alert_service


class AlertService:
    """Sends operational alerts to a Telegram chat/channel.

    All public methods swallow exceptions — alert failures must never
    affect the main application.
    """

    _MAX_DEDUP_KEYS = 10_000

    def __init__(
        self, bot_token: str, chat_id: str, *, thread_id: int | None = None,
    ) -> None:
        self._chat_id = chat_id
        self._thread_id = thread_id
        self._client = httpx.AsyncClient(timeout=10.0)
        self._seen: set[str] = set()
        self._url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # -- Public API --------------------------------------------------------

    async def send_alert(self, text: str, *, dedup_key: str | None = None) -> None:
        """Send an alert. If *dedup_key* was already sent, skip silently."""
        try:
            if dedup_key is not None:
                if dedup_key in self._seen:
                    return
                if len(self._seen) >= self._MAX_DEDUP_KEYS:
                    self._seen.clear()
                self._seen.add(dedup_key)

            payload: dict[str, object] = {
                "chat_id": self._chat_id,
                "text": text,
                "parse_mode": "HTML",
                "disable_web_page_preview": True,
            }
            if self._thread_id is not None:
                payload["message_thread_id"] = self._thread_id

            await self._client.post(self._url, json=payload)
        except Exception:  # noqa: BLE001
            # DEBUG — not ERROR — to prevent infinite recursion via the
            # logging handler that forwards ERROR+ to this service.
            logger.debug("Failed to send alert", exc_info=True)

    async def send_error_alert(
        self, exc: BaseException, context: str = "",
    ) -> None:
        """Format and send an error alert with dedup by exception location."""
        tb = traceback.extract_tb(exc.__traceback__)
        if tb:
            last = tb[-1]
            dedup_key = f"{type(exc).__name__}:{last.lineno}@{last.filename}"
        else:
            dedup_key = f"{type(exc).__name__}:unknown"

        tb_text = "".join(
            traceback.format_exception(type(exc), exc, exc.__traceback__),
        )
        if len(tb_text) > 3200:
            tb_text = tb_text[:3200] + "\n... (truncated)"

        ctx_line = f"Context: {context}\n" if context else ""
        block = f"Env: {_ENV}\nError: {type(exc).__name__}\n{ctx_line}\n{tb_text}"
        text = f"\U0001f534 <b>Error</b>\n<pre>{html.escape(block)}</pre>"
        await self.send_alert(text, dedup_key=dedup_key)

    async def send_warning_alert(
        self, message: str, *, dedup_key: str | None = None,
    ) -> None:
        block = f"Env: {_ENV}\n{message}"
        text = f"\U0001f7e1 <b>Warning</b>\n<pre>{html.escape(block[:3500])}</pre>"
        await self.send_alert(text, dedup_key=dedup_key)

    async def send_lifecycle_alert(self, event: str) -> None:
        """Startup/shutdown — no dedup (always sent)."""
        block = f"{event}\nEnv: {_ENV}"
        text = f"\U0001f7e2\n<pre>{html.escape(block)}</pre>"
        await self.send_alert(text)

    async def close(self) -> None:
        try:
            await self._client.aclose()
        except Exception:  # noqa: BLE001
            logger.debug("Failed to close alert HTTP client", exc_info=True)


# -- Logging bridge --------------------------------------------------------


class TelegramAlertHandler(logging.Handler):
    """Forwards ERROR+ log records to AlertService via fire-and-forget task.

    Bridges sync ``logging`` to async by scheduling on the running loop.
    """

    def __init__(self) -> None:
        super().__init__(level=logging.ERROR)

    def emit(self, record: logging.LogRecord) -> None:
        service = get_alert_service()
        if service is None:
            return

        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            return  # no event loop (e.g. during shutdown)

        msg = record.getMessage()

        if isinstance(record.exc_info, tuple) and record.exc_info[1] is not None:
            exc = record.exc_info[1]
            context = f"[{record.name}] {msg}"
            loop.create_task(service.send_error_alert(exc, context))
        else:
            source = f"{os.path.basename(record.pathname)}:{record.lineno}"
            dedup_key = f"log:{record.name}:{msg[:200]}"
            block = (
                f"Env: {_ENV}\nLogger: {record.name}\n"
                f"Source: {source}\n\n{msg}"
            )
            text = (
                f"\U0001f534 <b>Error</b>\n"
                f"<pre>{html.escape(block[:3500])}</pre>"
            )
            loop.create_task(service.send_alert(text, dedup_key=dedup_key))


# -- Integration example ---------------------------------------------------
#
# In your app startup (e.g. FastAPI lifespan, aiohttp on_startup):
#
#   from your_config import settings  # your env var loader
#
#   if settings.alert_bot_token and settings.alert_chat_id:
#       svc = init_alert_service(
#           settings.alert_bot_token,
#           settings.alert_chat_id,
#           thread_id=settings.alert_thread_id,  # optional
#       )
#       logging.getLogger().addHandler(TelegramAlertHandler())
#       await svc.send_lifecycle_alert("Application started")
#
# In your app shutdown:
#
#   svc = get_alert_service()
#   if svc:
#       await svc.send_lifecycle_alert("Application shutting down")
#       await svc.close()
#
# FastAPI unhandled exception handler:
#
#   @app.exception_handler(Exception)
#   async def _unhandled(request, exc):
#       logger.error("Unhandled: %s %s", request.method, request.url.path,
#                    exc_info=exc)
#       return JSONResponse({"detail": "Internal server error"}, 500)
