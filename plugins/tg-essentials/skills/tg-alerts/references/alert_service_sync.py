"""Telegram alert service — sync variant (Django, Flask, etc.).

Reference implementation. Adapt to your project's style and structure.
Dependencies: requests.
"""

from __future__ import annotations

import html
import logging
import os
import threading
import traceback
from concurrent.futures import ThreadPoolExecutor

import requests

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
    """Sends operational alerts to a Telegram chat/channel (sync).

    All public methods swallow exceptions — alert failures must never
    affect the main application.
    """

    _MAX_DEDUP_KEYS = 10_000

    def __init__(
        self, bot_token: str, chat_id: str, *, thread_id: int | None = None,
    ) -> None:
        self._chat_id = chat_id
        self._thread_id = thread_id
        self._session = requests.Session()
        self._seen: set[str] = set()
        self._lock = threading.Lock()
        self._pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="tg-alert")
        self._url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # -- Public API --------------------------------------------------------

    def send_alert(self, text: str, *, dedup_key: str | None = None) -> None:
        """Send an alert. If *dedup_key* was already sent, skip silently."""
        try:
            if dedup_key is not None:
                with self._lock:
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

            self._session.post(self._url, json=payload, timeout=10)
        except Exception:  # noqa: BLE001
            logger.debug("Failed to send alert", exc_info=True)

    def send_alert_background(self, text: str, *, dedup_key: str | None = None) -> None:
        """Fire-and-forget via thread pool — never blocks the caller."""
        self._pool.submit(self.send_alert, text, dedup_key=dedup_key)

    def send_error_alert(
        self, exc: BaseException, context: str = "",
    ) -> None:
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
        self.send_alert_background(text, dedup_key=dedup_key)

    def send_warning_alert(
        self, message: str, *, dedup_key: str | None = None,
    ) -> None:
        block = f"Env: {_ENV}\n{message}"
        text = f"\U0001f7e1 <b>Warning</b>\n<pre>{html.escape(block[:3500])}</pre>"
        self.send_alert_background(text, dedup_key=dedup_key)

    def send_lifecycle_alert(self, event: str) -> None:
        block = f"{event}\nEnv: {_ENV}"
        text = f"\U0001f7e2\n<pre>{html.escape(block)}</pre>"
        self.send_alert(text)  # blocking — startup/shutdown can wait

    def close(self) -> None:
        try:
            self._pool.shutdown(wait=True, cancel_futures=False)
            self._session.close()
        except Exception:  # noqa: BLE001
            logger.debug("Failed to close alert HTTP session", exc_info=True)


# -- Logging bridge --------------------------------------------------------


class TelegramAlertHandler(logging.Handler):
    """Forwards ERROR+ log records to AlertService via thread pool.

    Uses fire-and-forget to avoid blocking the request.
    """

    def __init__(self) -> None:
        super().__init__(level=logging.ERROR)

    def emit(self, record: logging.LogRecord) -> None:
        service = get_alert_service()
        if service is None:
            return

        msg = record.getMessage()

        if isinstance(record.exc_info, tuple) and record.exc_info[1] is not None:
            exc = record.exc_info[1]
            context = f"[{record.name}] {msg}"
            service.send_error_alert(exc, context)  # already fire-and-forget
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
            service.send_alert_background(text, dedup_key=dedup_key)


# -- Integration examples --------------------------------------------------
#
# === Django ===
#
# In settings.py or AppConfig.ready():
#
#   ALERT_BOT_TOKEN = os.environ.get("ALERT_BOT_TOKEN")
#   ALERT_CHAT_ID = os.environ.get("ALERT_CHAT_ID")
#   ALERT_THREAD_ID = int(t) if (t := os.environ.get("ALERT_THREAD_ID")) else None
#
# In AppConfig.ready():
#
#   if settings.ALERT_BOT_TOKEN and settings.ALERT_CHAT_ID:
#       svc = init_alert_service(
#           settings.ALERT_BOT_TOKEN, settings.ALERT_CHAT_ID,
#           thread_id=settings.ALERT_THREAD_ID,
#       )
#       logging.getLogger().addHandler(TelegramAlertHandler())
#       svc.send_lifecycle_alert("Application started")
#
# Custom 500 handler (views.py):
#
#   def handler500(request):
#       # Django already logs the exception — TelegramAlertHandler will
#       # catch it via the logging bridge. No extra code needed.
#       return render(request, "500.html", status=500)
#
# === Flask ===
#
# In create_app():
#
#   if app.config.get("ALERT_BOT_TOKEN") and app.config.get("ALERT_CHAT_ID"):
#       svc = init_alert_service(
#           app.config["ALERT_BOT_TOKEN"], app.config["ALERT_CHAT_ID"],
#           thread_id=app.config.get("ALERT_THREAD_ID"),
#       )
#       logging.getLogger().addHandler(TelegramAlertHandler())
#       svc.send_lifecycle_alert("Application started")
#
#   @app.errorhandler(Exception)
#   def handle_exception(exc):
#       logger.error("Unhandled: %s", request.path, exc_info=exc)
#       return "Internal server error", 500
