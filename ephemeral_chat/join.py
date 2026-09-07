"""Encode a LAN IP+port as a short join code. No internet."""

from __future__ import annotations

ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
_INDEX = {ch: i for i, ch in enumerate(ALPHABET)}


def new_room_code() -> str:
    import random

    return "".join(random.choice(ALPHABET) for _ in range(6))


def encode_join(ip: str, port: int) -> str:
    parts = ip.split(".")
    if len(parts) != 4:
        raise ValueError("need IPv4")
    a, b, c, d = (int(x) for x in parts)
    n = (a << 40) | (b << 32) | (c << 24) | (d << 16) | (port & 0xFFFF)
    chars: list[str] = []
    for _ in range(10):
        chars.append(ALPHABET[n & 31])
        n >>= 5
    raw = "".join(reversed(chars))
    return f"{raw[0:4]}-{raw[4:8]}-{raw[8:10]}"


def decode_join(code: str) -> tuple[str, int]:
    raw = "".join(ch for ch in code.upper() if ch in _INDEX)
    if len(raw) != 10:
        raise ValueError("bad code")
    n = 0
    for ch in raw:
        n = (n << 5) | _INDEX[ch]
    port = n & 0xFFFF
    d = (n >> 16) & 0xFF
    c = (n >> 24) & 0xFF
    b = (n >> 32) & 0xFF
    a = (n >> 40) & 0xFF
    if port == 0 or a == 0:
        raise ValueError("bad code")
    return f"{a}.{b}.{c}.{d}", port


def parse_target(raw: str) -> tuple[str, int]:
    text = raw.strip()
    if ":" in text and "." in text.split(":")[0]:
        host, port_s = text.rsplit(":", 1)
        return host.strip(), int(port_s)
    return decode_join(text)
