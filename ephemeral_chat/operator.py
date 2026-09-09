"""Operator master key. Private key never ships in the app or the installer."""

from __future__ import annotations

import os
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, NoEncryption, PrivateFormat, PublicFormat

from .crypto import from_hex, hex_of

# Verify-only. The matching private key stays on the owner's machine.
OPERATOR_PUB_HEX = "461249261b4fe9959811a8d90796b67581f4ecbf04bd7ec0b11f91ba918441f4"

_CLAIM_PREFIX = "lanchat-claim-v1"


def default_key_path() -> Path:
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA") or Path.home()) / "lanchat"
    else:
        xdg = os.environ.get("XDG_DATA_HOME")
        base = Path(xdg) / "lanchat" if xdg else Path.home() / ".local" / "share" / "lanchat"
    return base / "master.key"


def device_id() -> str:
    path = default_key_path().parent / "device.id"
    try:
        existing = path.read_text().strip()
        if len(existing) >= 16:
            return existing[:32]
    except OSError:
        pass
    import uuid

    value = uuid.uuid4().hex
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value + "\n")
        path.chmod(0o600)
    except OSError:
        pass
    return value


def _repo_key_path() -> Path:
    return Path(__file__).resolve().parent.parent / ".master.key"


def operator_pub() -> bytes:
    return from_hex(OPERATOR_PUB_HEX)


def _sk_from_hex(text: str) -> Ed25519PrivateKey | None:
    try:
        raw = from_hex(text)
        if len(raw) != 32:
            return None
        sk = Ed25519PrivateKey.from_private_bytes(raw)
        pub = sk.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
        if pub != operator_pub():
            return None
        return sk
    except Exception:
        return None


def save_operator_key(sk: Ed25519PrivateKey, path: Path | None = None) -> Path:
    dest = path or default_key_path()
    dest.parent.mkdir(parents=True, exist_ok=True)
    raw = sk.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    dest.write_text(hex_of(raw) + "\n")
    try:
        dest.chmod(0o600)
    except OSError:
        pass
    return dest


def load_operator_key() -> Ed25519PrivateKey | None:
    env = os.environ.get("LANCHAT_MASTER_KEY", "").strip()
    if env:
        sk = _sk_from_hex(env)
        if sk is not None:
            return sk
    for path in (default_key_path(), _repo_key_path()):
        try:
            if not path.is_file():
                continue
            sk = _sk_from_hex(path.read_text())
            if sk is None:
                continue
            if path != default_key_path():
                try:
                    save_operator_key(sk)
                except OSError:
                    pass
            return sk
        except OSError:
            continue
    return None


def import_operator_key(text: str) -> Ed25519PrivateKey | None:
    sk = _sk_from_hex(text)
    if sk is None:
        return None
    try:
        save_operator_key(sk)
    except OSError:
        pass
    return sk


def has_master_key() -> bool:
    return load_operator_key() is not None


def claim_message(room: str, peer_id: str, ts: int, dh_pk_hex: str) -> bytes:
    return f"{_CLAIM_PREFIX}|{room}|{peer_id}|{ts}|{dh_pk_hex}".encode("ascii")


def sign_claim(sk: Ed25519PrivateKey, room: str, peer_id: str, ts: int, dh_pk_hex: str) -> str:
    return hex_of(sk.sign(claim_message(room, peer_id, ts, dh_pk_hex)))


def verify_claim(room: str, peer_id: str, ts: int, dh_pk_hex: str, sig_hex: str) -> bool:
    try:
        pk = Ed25519PublicKey.from_public_bytes(operator_pub())
        pk.verify(from_hex(sig_hex), claim_message(room, peer_id, ts, dh_pk_hex))
        return True
    except Exception:
        return False
