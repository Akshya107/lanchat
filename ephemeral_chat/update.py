"""Pull the latest GitHub build into a curl-installed venv, then relaunch."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

_OWNER = os.environ.get("LANCHAT_GH_OWNER", "Akshya107")
_REPO = os.environ.get("LANCHAT_GH_REPO", "lanchat")
_BRANCH = os.environ.get("LANCHAT_GH_BRANCH", "main")
_PAYLOAD = f"https://raw.githubusercontent.com/{_OWNER}/{_REPO}/{_BRANCH}/install/src.tgz.b64"


def _data_dir() -> Path:
    prefix = Path(sys.prefix).resolve()
    if prefix.name.lower() in {"venv", ".venv"}:
        return prefix.parent
    if os.name == "nt":
        return Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "lanchat"
    xdg = os.environ.get("XDG_DATA_HOME")
    return Path(xdg) / "lanchat" if xdg else Path.home() / ".local" / "share" / "lanchat"


def _in_git_checkout() -> bool:
    root = Path(__file__).resolve().parent.parent
    return (root / ".git").is_dir()


def _sha_path() -> Path:
    return _data_dir() / "update.sha"


def _online() -> bool:
    import socket

    try:
        socket.create_connection(("github.com", 443), timeout=1.5).close()
        return True
    except OSError:
        return False


def maybe_update(argv: list[str]) -> None:
    if os.environ.get("LANCHAT_NO_UPDATE") or os.environ.get("LANCHAT_UPDATED"):
        return
    if "--no-update" in argv or "-V" in argv or "--version" in argv:
        return
    if _in_git_checkout():
        return
    if not _online():
        return
    try:
        _pull_and_reexec(argv)
    except Exception:
        return


def _pull_and_reexec(argv: list[str]) -> None:
    import urllib.request

    req = urllib.request.Request(_PAYLOAD, headers={"User-Agent": "lanchat-update"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        b64 = resp.read()
    if not b64.strip():
        return
    digest = hashlib.sha256(b64).hexdigest()
    last = ""
    try:
        last = _sha_path().read_text().strip()
    except OSError:
        pass
    if digest == last:
        return
    raw = __import__("base64").b64decode(b64)
    tmp = Path(tempfile.mkdtemp(prefix="lanchat-up-"))
    try:
        tgz = tmp / "src.tgz"
        tgz.write_bytes(raw)
        with tarfile.open(tgz) as tar:
            try:
                tar.extractall(tmp / "src", filter="data")
            except TypeError:
                tar.extractall(tmp / "src")
        src = tmp / "src"
        if not (src / "pyproject.toml").is_file():
            inner = next((p for p in src.iterdir() if (p / "pyproject.toml").is_file()), None)
            if inner is None:
                return
            src = inner
        print("lanchat: installing latest from GitHub…", file=sys.stderr)
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "-q", str(src)],
            timeout=180,
        )
        _sha_path().parent.mkdir(parents=True, exist_ok=True)
        _sha_path().write_text(digest + "\n")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    env = os.environ.copy()
    env["LANCHAT_UPDATED"] = "1"
    os.execvpe(sys.executable, [sys.executable, "-m", "ephemeral_chat", *argv], env)
