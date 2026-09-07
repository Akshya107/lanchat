"""LAN-only UDP beacons so peers find each other with no internet and no mDNS."""

from __future__ import annotations

import asyncio
import socket
import struct
from collections.abc import Callable
from typing import Any

from .util import local_ipv4_all

BEACON_PORT = 48721
_MAGIC = b"EC01"
_STRUCT = struct.Struct("!4s16s24sH")

OnBeacon = Callable[[str, str, str, int], None]


def _pack(peer_id: str, nick: str, port: int) -> bytes:
    pid = bytes.fromhex(peer_id[:32].ljust(32, "0"))[:16]
    name = nick.encode("utf-8")[:24].ljust(24, b"\0")
    return _STRUCT.pack(_MAGIC, pid, name, port)


def _unpack(data: bytes) -> tuple[str, str, int] | None:
    if len(data) < _STRUCT.size:
        return None
    try:
        magic, pid, name, port = _STRUCT.unpack(data[: _STRUCT.size])
    except struct.error:
        return None
    if magic != _MAGIC or not (1 <= port <= 65535):
        return None
    peer_id = pid.hex()
    nick = name.split(b"\0", 1)[0].decode("utf-8", "replace")[:24] or "peer"
    return peer_id, nick, int(port)


class _Protocol(asyncio.DatagramProtocol):
    def __init__(self, peer_id: str, on_beacon: OnBeacon) -> None:
        self.peer_id = peer_id
        self.on_beacon = on_beacon
        self.transport: asyncio.DatagramTransport | None = None

    def connection_made(self, transport: asyncio.BaseTransport) -> None:
        self.transport = transport  # type: ignore[assignment]

    def datagram_received(self, data: bytes, addr: tuple[str | Any, int]) -> None:
        parsed = _unpack(data)
        if parsed is None:
            return
        peer_id, nick, port = parsed
        if peer_id == self.peer_id:
            return
        host = str(addr[0])
        if host.startswith("127."):
            return
        self.on_beacon(peer_id, nick, host, port)


class Beacon:
    def __init__(self, peer_id: str, nick: str, tcp_port: int, on_beacon: OnBeacon) -> None:
        self.peer_id = peer_id
        self.nick = nick
        self.tcp_port = tcp_port
        self.on_beacon = on_beacon
        self._transport: asyncio.DatagramTransport | None = None
        self._task: asyncio.Task[None] | None = None
        self._running = False

    async def start(self) -> None:
        loop = asyncio.get_running_loop()
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
            except OSError:
                pass
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.bind(("0.0.0.0", BEACON_PORT))
        sock.setblocking(False)
        transport, _proto = await loop.create_datagram_endpoint(
            lambda: _Protocol(self.peer_id, self.on_beacon),
            sock=sock,
        )
        self._transport = transport
        self._running = True
        self._task = loop.create_task(self._announce())

    async def stop(self) -> None:
        self._running = False
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except (asyncio.CancelledError, Exception):
                pass
            self._task = None
        if self._transport is not None:
            self._transport.close()
            self._transport = None

    async def _announce(self) -> None:
        payload = _pack(self.peer_id, self.nick, self.tcp_port)
        while self._running:
            self._broadcast(payload)
            try:
                await asyncio.sleep(1.2)
            except asyncio.CancelledError:
                return

    def _broadcast(self, payload: bytes) -> None:
        if self._transport is None:
            return
        targets = {"255.255.255.255"}
        for _ip, broadcast in local_ipv4_all():
            if broadcast:
                targets.add(broadcast)
        for host in targets:
            try:
                self._transport.sendto(payload, (host, BEACON_PORT))
            except OSError:
                continue
