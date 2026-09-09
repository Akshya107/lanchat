"""AES-256-GCM chat plus X25519 wrap. Byte-compatible with mobile/lib/net/crypto.dart."""

from __future__ import annotations

import base64
import json
import os

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

WRAP_SALT = b"lanchat-wrap-v1"
WRAP_INFO = b"room-key"
WRAP_VERSION = 1


def new_x25519() -> tuple[bytes, bytes]:
    sk = X25519PrivateKey.generate()
    pk = sk.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    raw = sk.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    return raw, pk


def x25519_public(sk: bytes) -> bytes:
    return (
        X25519PrivateKey.from_private_bytes(sk)
        .public_key()
        .public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    )


def new_room_key() -> bytes:
    return os.urandom(32)


def _hkdf(shared: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=WRAP_SALT, info=WRAP_INFO).derive(shared)


def wrap_room_key(room_key: bytes, recipient_pk: bytes) -> str:
    eph = X25519PrivateKey.generate()
    eph_pk = eph.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    shared = eph.exchange(X25519PublicKey.from_public_bytes(recipient_pk))
    nonce = os.urandom(12)
    ct = AESGCM(_hkdf(shared)).encrypt(nonce, room_key, None)
    return base64.b64encode(bytes([WRAP_VERSION]) + eph_pk + nonce + ct).decode("ascii")


def unwrap_room_key(box_b64: str, recipient_sk: bytes) -> bytes | None:
    try:
        raw = base64.b64decode(box_b64)
        if len(raw) < 1 + 32 + 12 + 16 or raw[0] != WRAP_VERSION:
            return None
        eph_pk = raw[1:33]
        nonce = raw[33:45]
        ct = raw[45:]
        sk = X25519PrivateKey.from_private_bytes(recipient_sk)
        shared = sk.exchange(X25519PublicKey.from_public_bytes(eph_pk))
        key = AESGCM(_hkdf(shared)).decrypt(nonce, ct, None)
        return key if len(key) == 32 else None
    except Exception:
        return None


def _dumps(payload: dict) -> bytes:
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def seal_chat(payload: dict, room: str, room_key: bytes) -> str:
    nonce = os.urandom(12)
    aad = f"ec/v2/{room}/m".encode("ascii")
    ct = AESGCM(room_key).encrypt(nonce, _dumps(payload), aad)
    return base64.b64encode(nonce + ct).decode("ascii")


def open_chat(blob: str | bytes, room: str, room_key: bytes) -> dict | None:
    try:
        if isinstance(blob, str):
            data = base64.b64decode(blob)
        else:
            try:
                data = base64.b64decode(blob)
            except Exception:
                data = blob
        if len(data) < 12 + 16:
            return None
        nonce, ct = data[:12], data[12:]
        aad = f"ec/v2/{room}/m".encode("ascii")
        raw = AESGCM(room_key).decrypt(nonce, ct, aad)
        obj = json.loads(raw.decode("utf-8"))
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def hex_of(data: bytes) -> str:
    return data.hex()


def from_hex(text: str) -> bytes:
    clean = "".join(ch for ch in text.strip().lower() if ch in "0123456789abcdef")
    if len(clean) % 2:
        raise ValueError("odd hex")
    return bytes.fromhex(clean)
