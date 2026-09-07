"""Keep the live session off screenshots and screen recordings where the OS allows it."""

from __future__ import annotations

import sys
import threading
import time
from collections.abc import Callable


_WATCH = (
    "screencapture",
    "screencaptureui",
    "Screenshot",
    "ScreenCaptureKit",
    "gnome-screenshot",
    "spectacle",
    "scrot",
    "flameshot",
    "xfce4-screenshooter",
    "SnippingTool",
    "ScreenClippingHost",
)


def block_os_capture() -> None:
    if sys.platform != "win32":
        return
    try:
        import ctypes

        hwnd = ctypes.windll.kernel32.GetConsoleWindow()
        if hwnd:
            # WDA_EXCLUDEFROMCAPTURE — window is black / missing in screenshots.
            ctypes.windll.user32.SetWindowDisplayAffinity(hwnd, 0x00000011)
    except Exception:
        pass


def release_os_capture() -> None:
    if sys.platform != "win32":
        return
    try:
        import ctypes

        hwnd = ctypes.windll.kernel32.GetConsoleWindow()
        if hwnd:
            ctypes.windll.user32.SetWindowDisplayAffinity(hwnd, 0)
    except Exception:
        pass


def _capture_tool_running() -> bool:
    try:
        import psutil  # type: ignore
    except Exception:
        psutil = None
    if psutil is not None:
        try:
            names = {p.name() for p in psutil.process_iter(["name"])}
            return any(any(w.lower() in n.lower() for w in _WATCH) for n in names)
        except Exception:
            pass
    if sys.platform == "win32":
        return False
    try:
        import subprocess

        out = subprocess.check_output(["ps", "-axo", "comm="], text=True, stderr=subprocess.DEVNULL)
        low = out.lower()
        return any(w.lower() in low for w in _WATCH)
    except Exception:
        return False


class CaptureWatch:
    def __init__(self, on_block: Callable[[], None], on_clear: Callable[[], None]) -> None:
        self._on_block = on_block
        self._on_clear = on_clear
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        block_os_capture()
        self._thread = threading.Thread(target=self._loop, name="lanchat-privacy", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        release_os_capture()

    def _loop(self) -> None:
        blocked = False
        while not self._stop.wait(0.08):
            now = _capture_tool_running()
            if now and not blocked:
                blocked = True
                try:
                    self._on_block()
                except Exception:
                    pass
            elif not now and blocked:
                blocked = False
                try:
                    self._on_clear()
                except Exception:
                    pass
        if blocked:
            try:
                self._on_clear()
            except Exception:
                pass
        time.sleep(0)
