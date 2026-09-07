"""Short high 'ting' for incoming messages. Synthesized in memory — not a file."""

from __future__ import annotations

import io
import math
import os
import struct
import subprocess
import sys
import tempfile
import threading
import wave

# Bright little bell: E7 + B7 + E8, ~120ms, fast decay.
_RATE = 22050
_DURATION = 0.12


def _ting_wav() -> bytes:
    n = int(_RATE * _DURATION)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(_RATE)
        frames = bytearray()
        for i in range(n):
            t = i / _RATE
            env = math.exp(-t * 32)
            if t < 0.0015:
                env *= t / 0.0015
            sample = (
                0.62 * math.sin(2 * math.pi * 2637.0 * t)
                + 0.28 * math.sin(2 * math.pi * 3951.0 * t)
                + 0.10 * math.sin(2 * math.pi * 5274.0 * t)
            )
            value = int(max(-1.0, min(1.0, sample * env * 0.7)) * 32767)
            frames += struct.pack("<h", value)
        wav.writeframes(bytes(frames))
    return buf.getvalue()


_WAV = _ting_wav()


def play_ping() -> None:
    threading.Thread(target=_play, daemon=True).start()


def _play() -> None:
    try:
        if sys.platform == "win32":
            import winsound

            winsound.PlaySound(_WAV, winsound.SND_MEMORY)
            return
        path = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                tmp.write(_WAV)
                path = tmp.name
            if sys.platform == "darwin":
                subprocess.run(
                    ["afplay", "-v", "0.55", path],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                    check=False,
                )
            else:
                _play_linux(path)
        finally:
            if path:
                try:
                    os.unlink(path)
                except OSError:
                    pass
    except Exception:
        pass


def _play_linux(path: str) -> None:
    for cmd in (
        ["paplay", path],
        ["pw-play", path],
        ["aplay", "-q", path],
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path],
    ):
        try:
            subprocess.run(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=2,
                check=False,
            )
            return
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    sys.stdout.write("\a")
    sys.stdout.flush()
