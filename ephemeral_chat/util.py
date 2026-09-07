"""Local IPv4 helpers. Never talks to the public internet."""

from __future__ import annotations

import ipaddress
import socket
import uuid


def new_peer_id() -> str:
    return uuid.uuid4().hex


def new_message_id() -> str:
    return uuid.uuid4().hex[:12]


def local_ipv4_all() -> list[tuple[str, str]]:
    """Return (ip, broadcast) for every usable IPv4 interface. No internet."""
    private: list[tuple[str, str]] = []
    other: list[tuple[str, str]] = []
    seen: set[str] = set()
    try:
        import ifaddr

        adapters = ifaddr.get_adapters()
    except Exception:
        return _fallback_ips()
    for adapter in adapters:
        for ip in adapter.ips:
            if not isinstance(ip.ip, str):
                continue
            try:
                parsed = ipaddress.ip_address(ip.ip)
            except ValueError:
                continue
            if parsed.version != 4 or parsed.is_loopback or parsed.is_link_local:
                continue
            prefix = getattr(ip, "network_prefix", 24) or 24
            try:
                net = ipaddress.IPv4Network(f"{ip.ip}/{prefix}", strict=False)
                broadcast = str(net.broadcast_address)
            except ValueError:
                broadcast = ""
            if ip.ip in seen:
                continue
            seen.add(ip.ip)
            row = (ip.ip, broadcast)
            if parsed.is_private:
                private.append(row)
            else:
                other.append(row)
    return private + other or _fallback_ips()


def _fallback_ips() -> list[tuple[str, str]]:
    try:
        ip = socket.gethostbyname(socket.gethostname())
        parsed = ipaddress.ip_address(ip)
        if parsed.version == 4 and not parsed.is_loopback:
            return [(ip, "")]
    except Exception:
        pass
    return [("127.0.0.1", "")]


def local_ipv4() -> str:
    ips = local_ipv4_all()
    return ips[0][0] if ips else "127.0.0.1"


def default_nick() -> str:
    import getpass
    import os

    for key in ("USER", "USERNAME"):
        value = os.environ.get(key)
        if value:
            return value[:24]
    try:
        return getpass.getuser()[:24]
    except Exception:
        return "anon"


def instance_name(peer_id: str) -> str:
    return f"ephemeral-{peer_id[:12]}"
