"""Local voice/video-note transcription with an export-scoped success cache."""
import asyncio
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


class Transcriber:
    def __init__(self, cache_dir):
        self.cache_dir = Path(cache_dir) / "small"
        self.model = None

    def _recognize(self, path):
        if self.model is None:
            from faster_whisper import WhisperModel
            self.model = WhisperModel("small", device="cpu", compute_type="int8", local_files_only=True)
        segments, _ = self.model.transcribe(str(path), beam_size=5, vad_filter=True)
        return " ".join(" ".join(segment.text.split()) for segment in segments).strip()

    async def transcribe(self, client, message):
        cache = self.cache_dir / f"{message.document.id}.txt"
        try:
            text = cache.read_text(encoding="utf-8").strip()
            if text:
                return " ".join(text.split())
        except (OSError, UnicodeError):
            pass
        with TemporaryDirectory(prefix="tg-transcribe-") as tmp:
            suffix = ".ogg" if message.voice else ".mp4"
            path = await client.download_media(message, file=str(Path(tmp) / ("media" + suffix)))
            if not path:
                raise FileNotFoundError("Telegram did not return a media file")
            recognition = asyncio.create_task(asyncio.to_thread(self._recognize, path))
            try:
                text = await asyncio.shield(recognition)
            except asyncio.CancelledError:
                # The decoder may still hold the file open, especially on Windows.
                completion = asyncio.gather(recognition, return_exceptions=True)
                while not completion.done():
                    try:
                        await asyncio.shield(completion)
                    except asyncio.CancelledError:
                        pass
                raise
        if text:
            try:
                self.cache_dir.mkdir(parents=True, exist_ok=True)
                with TemporaryDirectory(dir=self.cache_dir, prefix=".write-") as tmp:
                    pending = Path(tmp) / "transcript.txt"
                    pending.write_text(text, encoding="utf-8")
                    pending.replace(cache)
            except OSError as ex:
                print(f"Transcript cache write failed ({type(ex).__name__}); keeping text in the export.", file=sys.stderr)
        return text
