"""Create the venv in ~/.tg-account/venv and patch opentele for Telegram Desktop 7.x tdata. Idempotent.

The venv lives outside the plugin so plugin updates do not wipe it.
Run with Python 3.12: python setup.py [--transcribe]
"""
import argparse, pathlib, subprocess, sys, venv

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--transcribe", action="store_true", help="Install local voice/video-note transcription")
args = parser.parse_args()

VENV = pathlib.Path.home() / ".tg-account" / "venv"
PY = VENV / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")

# (old, new) pairs in opentele/td/account.py, opentele 1.15.1
PATCHES = [
    # tdesktop 7.x writes map key types opentele does not know (23 on 7.2.9).
    # The map is not needed for the auth key, so keep going to readMtpData.
    ("        except OpenTeleException:\n            return False\n\n        self.readMtpData()",
     "        except OpenTeleException:\n            pass  # tdesktop 7.x: unknown map key types, auth key does not need the map\n\n        self.readMtpData()"),
    # `!=` on API objects recurses through the owner's setter forever.
    ("        if self.owner.api != self.api:", "        if self.owner.api is not value:"),
]

if not PY.exists():
    venv.create(VENV, with_pip=True)
subprocess.check_call([str(PY), "-m", "pip", "install", "-q", "opentele==1.15.1", "telethon==1.45.0"])

site = subprocess.check_output([str(PY), "-c", "import opentele,os;print(os.path.dirname(opentele.__file__))"], text=True).strip()
f = pathlib.Path(site) / "td" / "account.py"
src = f.read_text(encoding="utf-8").replace("\r\n", "\n")
for old, new in PATCHES:
    if new in src:
        continue
    if old not in src:
        sys.exit(f"patch target not found in {f}, opentele changed: {old[:60]!r}")
    src = src.replace(old, new)
f.write_text(src, encoding="utf-8", newline="\n")
if args.transcribe:
    print("Preparing Whisper small for local transcription (first download is about 500 MB)...", flush=True)
    subprocess.check_call([str(PY), str(pathlib.Path(__file__).with_name("tg_transcribe.py")), "--prepare"])
print("ok:", PY)
