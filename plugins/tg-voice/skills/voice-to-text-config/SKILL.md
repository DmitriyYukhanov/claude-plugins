---
name: voice-to-text-config
description: Set up Telegram voice message transcription — checks faster-whisper installation, downloads the Whisper model, and verifies the hook works end-to-end. Use when the user asks to "set up voice transcription", "configure whisper", "fix voice messages", or when the transcription hook reports that whisper is missing or the model isn't downloaded.
user-invocable: true
---

# Voice-to-Text Configuration

Set up local Whisper-based transcription for Telegram voice messages.

## Steps

Run each step sequentially. Report status clearly after each one.

### 1. Check faster-whisper installation

```bash
python -c "import faster_whisper; print(f'faster-whisper {faster_whisper.__version__} installed')" 2>&1
```

- **If installed**: print the version, move to step 2.
- **If ImportError**: tell the user and install it:
  ```bash
  pip install faster-whisper
  ```
  Verify the install succeeded before continuing.

### 2. Check / download Whisper model

The default model is controlled by the `WHISPER_MODEL` env var (default: `base`).
Available sizes: `tiny` (~40MB, fastest), `base` (~75MB, good balance), `small` (~250MB), `medium` (~750MB, most accurate for CPU).

Ask the user which model size they want if they haven't specified one. Then check if it's cached:

```bash
python -c "
import os, sys
from huggingface_hub import try_to_load_from_cache
model = os.environ.get('WHISPER_MODEL', 'base')
cached = try_to_load_from_cache(f'Systran/faster-whisper-{model}', 'model.bin')
if cached:
    print(f'Model \"{model}\" is cached at: {cached}')
else:
    print(f'Model \"{model}\" is NOT cached yet — needs download')
    sys.exit(1)
" 2>&1
```

If not cached, download it:

```bash
python -c "
import os, sys
model = os.environ.get('WHISPER_MODEL', 'base')
print(f'Downloading whisper model \"{model}\"... (this may take a minute)')
from faster_whisper import WhisperModel
m = WhisperModel(model, device='cpu', compute_type='int8')
print(f'Model \"{model}\" downloaded and ready.')
" 2>&1
```

**Important**: This download can take 1-3 minutes on first run. Let the user know progress is happening.

### 3. End-to-end test

If there's a voice file in the Telegram inbox, test transcription against it:

```bash
python -c "
import glob, os, sys
from faster_whisper import WhisperModel
inbox = os.path.expanduser(r'~\.claude\channels\telegram\inbox')
files = sorted(glob.glob(os.path.join(inbox, '*.oga')), key=os.path.getmtime, reverse=True)
if not files:
    print('No .oga voice files found in inbox to test against.')
    sys.exit(0)
f = files[0]
print(f'Testing transcription on: {os.path.basename(f)}')
model_size = os.environ.get('WHISPER_MODEL', 'base')
model = WhisperModel(model_size, device='cpu', compute_type='int8')
segments, info = model.transcribe(f, beam_size=5)
text = ' '.join(seg.text.strip() for seg in segments)
lang = getattr(info, 'language', 'unknown')
prob = getattr(info, 'language_probability', 0)
print(f'Language: {lang} ({prob:.0%})')
print(f'Transcription: {text}')
" 2>&1
```

### 4. Verify hook is registered

Check that the transcription hook exists in the plugin:

```bash
cat "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/hooks/hooks.json" 2>/dev/null || cat "${CLAUDE_PLUGIN_ROOT}/hooks/hooks.json" 2>/dev/null
```

Confirm it targets `mcp__plugin_telegram_telegram__download_attachment`.

### 5. Report

Summarize:
- faster-whisper version
- Model size and cache status
- Test transcription result (if available)
- Hook registration status

If everything passed, tell the user: "Voice transcription is ready. Send a voice message on Telegram to test it live."

If the user wants a different model size, they can set `WHISPER_MODEL` in their environment (e.g., in `.claude/settings.json` env section or system env vars).
