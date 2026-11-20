#!/usr/bin/env python3
"""Fetch the pinned, unmodified, OFL-licensed Korean UI font for local/CI build.
No credentials or external service; verify exact upstream Git blob and byte count.
The accompanying source and license notice must ship with exported games.
"""
from pathlib import Path
import hashlib
import urllib.request
import urllib.error
import time

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "assets/fonts/NotoSansCJKkr-Regular.otf"
URL = "https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/Sans/OTF/Korean/NotoSansCJKkr-Regular.otf"
SIZE = 16433112
BLOB = "dc4a7c65e6f450bf17c10a2405250b620eb78703"

def valid(data):
    return len(data) == SIZE and hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest() == BLOB

if not TARGET.exists() or not valid(TARGET.read_bytes()):
    # Network failures are transient; never relax the pinned integrity check.
    for attempt in range(3):
        try:
            with urllib.request.urlopen(URL, timeout=60) as response:
                data = response.read(SIZE + 1)
            break
        except (OSError, urllib.error.URLError) as exc:
            if attempt == 2:
                raise
            print(f"ZT_FONT_RETRY {attempt + 1}/2: {exc}", flush=True)
            time.sleep(2 ** (attempt + 1))
    if not valid(data):
        raise SystemExit("Noto font size or pinned Git blob mismatch")
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    temporary = TARGET.with_suffix(".otf.tmp")
    temporary.write_bytes(data)
    temporary.replace(TARGET)
print("ZT_FONT_OK", SIZE, BLOB)

# Verify the adopted compressed master before Godot import. No rendering dependency.
SCORE = ROOT / "assets/audio/Before_the_Shutters_Cadence_v36.ogg"
SCORE_SHA256 = "d220b6ddfa9e9270d9abc17f8cc880b6a6217e678302704c01e0ac41c1eb11e2"
if not SCORE.is_file() or hashlib.sha256(SCORE.read_bytes()).hexdigest() != SCORE_SHA256:
    raise SystemExit("Cadence v3.6 score missing or hash mismatch")
print("ZT_OST_MASTER_OK", SCORE_SHA256)
