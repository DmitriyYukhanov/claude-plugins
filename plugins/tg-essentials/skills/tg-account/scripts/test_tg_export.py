"""Run with python -m unittest discover -s this_folder."""
import contextlib
import asyncio
import datetime as dt
import io
import pathlib
import subprocess
import sys
import threading
import unittest
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from telethon.tl import types
import tg_export


DATE = dt.datetime(2026, 10, 4, 12, tzinfo=dt.timezone.utc)


def message(mid, kind=None, docid=None, caption=""):
    attributes = {
        "voice": types.DocumentAttributeAudio(duration=5, voice=True),
        "video_note": types.DocumentAttributeVideo(duration=5, w=240, h=240, round_message=True),
        "video": types.DocumentAttributeVideo(duration=5, w=640, h=480),
        "audio": types.DocumentAttributeAudio(duration=5, voice=False),
    }
    media = None
    if kind:
        document = types.Document(
            id=docid or mid, access_hash=0, file_reference=b"", date=DATE,
            mime_type="audio/ogg" if kind in ("voice", "audio") else "video/mp4",
            size=10, dc_id=2, attributes=[attributes[kind]],
        )
        media = types.MessageMediaDocument(document=document)
    return types.Message(id=mid, peer_id=types.PeerUser(42), date=DATE, message=caption, media=media)


class Client:
    def __init__(self, messages, download_error=False, missing_media=False):
        self.messages = sorted(messages, key=lambda m: m.id, reverse=True)
        self.download_error = download_error
        self.missing_media = missing_media
        self.downloads = []
        self.disconnected = False

    async def get_messages(self, entity, limit, offset_id=0):
        return [m for m in self.messages if not offset_id or m.id < offset_id][:limit]

    async def download_media(self, m, file):
        self.downloads.append(pathlib.Path(file))
        if self.download_error:
            raise OSError("private download error")
        if self.missing_media:
            return None
        pathlib.Path(file).write_text(str(m.document.id), encoding="utf-8")
        return str(file)

    async def disconnect(self):
        self.disconnected = True


class ExportTranscription(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.out = pathlib.Path(self.temp.name)
        self.model_loads = 0
        self.speech = True
        self.inference_error = False

        def whisper_model(*args, **kwargs):
            self.model_loads += 1

            def transcribe(path, **options):
                if self.inference_error:
                    raise RuntimeError("private inference error")
                docid = pathlib.Path(path).read_text(encoding="utf-8")
                segments = [SimpleNamespace(text=f"Transcript\n{docid}")] if self.speech else []
                return iter(segments), SimpleNamespace(language="en")

            return SimpleNamespace(transcribe=transcribe)

        self.whisper = SimpleNamespace(WhisperModel=whisper_model)

    async def export(self, messages, transcribe=True, account=1, peer=None, **client_options):
        client = Client(messages, **client_options)
        output = io.StringIO()
        entity = peer or types.User(id=42, first_name="Example")
        with patch("tgsess.open_chat", AsyncMock(return_value=(client, entity, account))), \
                patch.dict(sys.modules, {"faster_whisper": self.whisper}), \
                patch.object(tg_export.asyncio, "sleep", AsyncMock()), contextlib.redirect_stdout(output):
            await tg_export.main("example", "2026-10-04", self.out, transcribe=transcribe)
        files = list(self.out.glob("????-??-??.txt"))
        text = files[0].read_text(encoding="utf-8") if files else ""
        return text, client, output.getvalue()

    async def test_text_only_keeps_media_and_caption_without_whisper(self):
        messages = [message(2, "voice"), message(1, "video_note", caption="Caption\nline")]
        text, client, output = await self.export(messages, transcribe=False)
        self.assertIn("#1 ?: Caption line\n", text)
        self.assertTrue(text.endswith("#2 ?: [media]"))
        self.assertEqual(client.downloads, [])
        self.assertEqual(self.model_loads, 0)
        self.assertNotIn("transcribed=", output)

    async def test_voice_and_video_note_keep_ids_replies_and_captions(self):
        video = message(2, "video_note", caption="Caption")
        video.reply_to = types.MessageReplyHeader(reply_to_msg_id=1)
        text, client, output = await self.export([message(1, "voice"), video])
        self.assertIn("#1 ?: [voice] Transcript 1", text)
        self.assertIn("#2 ->#1 ?: Caption [video note] Transcript 2", text)
        self.assertEqual(self.model_loads, 1)
        self.assertTrue(all(not path.exists() for path in client.downloads))
        self.assertIn("transcribed=2", output)

    async def test_success_cache_avoids_download_and_model_on_rerun(self):
        await self.export([message(1, "voice")])
        self.model_loads = 0
        text, client, _ = await self.export([message(1, "voice")])
        self.assertIn("Transcript 1", text)
        self.assertEqual(client.downloads, [])
        self.assertEqual(self.model_loads, 0)

    async def test_cache_separates_account_chat_type_and_replaced_document(self):
        await self.export([message(1, "voice", docid=7)])
        for account, peer, docid in (
            (2, types.User(id=42), 7),
            (1, types.Chat(id=42, title="Group", photo=types.ChatPhotoEmpty(), participants_count=2, date=DATE, version=1), 7),
            (1, types.User(id=42), 8),
        ):
            with self.subTest(account=account, peer=type(peer).__name__, docid=docid):
                text, client, _ = await self.export([message(1, "voice", docid=docid)], account=account, peer=peer)
                self.assertIn(f"Transcript {docid}", text)
                self.assertEqual(len(client.downloads), 1)

    async def test_download_failure_is_visible_and_retried(self):
        text, client, output = await self.export([message(1, "voice")], download_error=True)
        self.assertIn("[voice: transcription failed", text)
        self.assertNotIn("private download error", text)
        self.assertIn("transcription_failures=1", output)
        self.assertTrue(client.disconnected)
        text, client, _ = await self.export([message(1, "voice")])
        self.assertIn("Transcript 1", text)
        self.assertEqual(len(client.downloads), 1)

    async def test_missing_media_is_visible(self):
        text, _, _ = await self.export([message(1, "video_note")], missing_media=True)
        self.assertIn("[video note: transcription failed", text)

    async def test_inference_failure_deletes_media_and_continues(self):
        self.inference_error = True
        text, client, _ = await self.export([message(1, "voice"), message(2, caption="Plain text")])
        self.assertIn("[voice: transcription failed", text)
        self.assertIn("#2 ?: Plain text", text)
        self.assertNotIn("private inference error", text)
        self.assertTrue(all(not path.exists() for path in client.downloads))

    async def test_no_speech_is_visible_and_not_cached(self):
        self.speech = False
        text, _, _ = await self.export([message(1, "voice")])
        self.assertIn("[voice: no speech detected]", text)
        self.speech = True
        text, client, _ = await self.export([message(1, "voice")])
        self.assertIn("Transcript 1", text)
        self.assertEqual(len(client.downloads), 1)

    async def test_regular_audio_video_and_old_notes_are_not_downloaded(self):
        old = message(1, "voice")
        old.date = DATE - dt.timedelta(days=1)
        text, client, _ = await self.export([old, message(2, "audio"), message(3, "video")])
        self.assertNotIn("#1", text)
        self.assertEqual(text.count("[media]"), 2)
        self.assertEqual(client.downloads, [])
        self.assertEqual(self.model_loads, 0)

    async def test_corrupt_cache_is_rebuilt(self):
        await self.export([message(1, "voice")])
        cache = next((self.out / ".transcripts").rglob("1.txt"))
        cache.write_bytes(b"\xff")
        text, client, _ = await self.export([message(1, "voice")])
        self.assertIn("Transcript 1", text)
        self.assertEqual(len(client.downloads), 1)
        self.assertEqual(cache.read_text(encoding="utf-8"), "Transcript 1")

    async def test_cache_write_failure_preserves_recognized_text(self):
        with patch.object(pathlib.Path, "replace", side_effect=OSError("private disk error")), \
                contextlib.redirect_stderr(io.StringIO()) as warnings:
            text, client, output = await self.export([message(1, "voice")])
        self.assertIn("[voice] Transcript 1", text)
        self.assertIn("transcription_failures=0", output)
        self.assertIn("cache", warnings.getvalue().lower())
        self.assertNotIn("private disk error", warnings.getvalue())
        self.assertTrue(all(not path.exists() for path in client.downloads))

    async def test_history_error_disconnects_client(self):
        client = Client([])
        with patch("tgsess.open_chat", AsyncMock(return_value=(client, types.User(id=42), 1))), \
                patch.object(client, "get_messages", AsyncMock(side_effect=OSError("history unavailable"))), \
                contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(OSError):
                await tg_export.main("example", "2026-10-04", self.out)
        self.assertTrue(client.disconnected)

    async def test_cancel_waits_for_decoder_before_deleting_media(self):
        started, release = threading.Event(), threading.Event()
        readable = []

        def transcribe(path, **options):
            with open(path, "rb"):
                started.set()
                release.wait(timeout=3)
                readable.append(pathlib.Path(path).exists())
            return iter([SimpleNamespace(text="Speech")]), SimpleNamespace(language="en")

        self.whisper.WhisperModel = lambda *a, **k: SimpleNamespace(transcribe=transcribe)
        task = asyncio.create_task(self.export([message(1, "voice")]))
        try:
            self.assertTrue(await asyncio.to_thread(started.wait, 3))
            task.cancel()
            yielded = asyncio.get_running_loop().create_future()
            asyncio.get_running_loop().call_soon(yielded.set_result, None)
            await yielded
            task.cancel()
            asyncio.get_running_loop().call_later(0.05, release.set)
            with self.assertRaises(asyncio.CancelledError):
                await task
        finally:
            release.set()
        self.assertEqual(readable, [True])


class ExportCLI(unittest.TestCase):
    def test_help_exits_successfully_without_connecting(self):
        result = subprocess.run(
            [sys.executable, str(pathlib.Path(__file__).with_name("tg_export.py")), "--help"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
