"""Direct TCP mesh between discovered peers. Length-limited NDJSON, RAM only."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass, field
from typing import Callable

from .crypto import open_chat, seal_chat
from .util import new_message_id

MAX_LINE = 16384

OnChat = Callable[[str, str, str, str], None]
OnPeer = Callable[[str, str], None]
OnLeave = Callable[[str, str], None]
OnTyping = Callable[[str, bool], None]


@dataclass
class Peer:
    peer_id: str
    nick: str
    reader: asyncio.StreamReader
    writer: asyncio.StreamWriter
    task: asyncio.Task[None] | None = field(default=None, repr=False)

    def close(self) -> None:
        try:
            self.writer.close()
        except Exception:
            pass


def _pack(payload: dict) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def _unpack(line: bytes) -> dict | None:
    if not line or len(line) > MAX_LINE:
        return None
    try:
        data = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


class Mesh:
    def __init__(
        self,
        peer_id: str,
        nick: str,
        on_chat: OnChat,
        on_join: OnPeer,
        on_leave: OnLeave,
        on_nick: OnPeer,
        on_typing: OnTyping,
        room: str = "",
        dh_pk_hex: str = "",
        get_room_key: Callable[[], bytes | None] | None = None,
    ) -> None:
        self.peer_id = peer_id
        self.nick = nick
        self.room = room
        self.dh_pk_hex = dh_pk_hex
        self.get_room_key = get_room_key
        self.on_chat = on_chat
        self.on_join = on_join
        self.on_leave = on_leave
        self.on_nick = on_nick
        self.on_typing = on_typing
        self._peers: dict[str, Peer] = {}
        self._pending: set[str] = set()
        self._lock = asyncio.Lock()
        self._server: asyncio.AbstractServer | None = None
        self._closing = False

    @property
    def peers(self) -> list[Peer]:
        return list(self._peers.values())

    async def start(self) -> int:
        self._server = await asyncio.start_server(self._accept, "0.0.0.0", 0)
        sockets = self._server.sockets or []
        if not sockets:
            raise RuntimeError("TCP server failed to bind")
        return int(sockets[0].getsockname()[1])

    async def connect(self, peer_id: str, _nick: str, host: str, port: int) -> None:
        if self._closing or peer_id == self.peer_id:
            return
        async with self._lock:
            if peer_id in self._peers or peer_id in self._pending:
                return
            self._pending.add(peer_id)
        try:
            try:
                reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 4)
            except (OSError, asyncio.TimeoutError):
                return
            await self._session(reader, writer)
        finally:
            async with self._lock:
                self._pending.discard(peer_id)

    async def connect_host(self, host: str, port: int) -> bool:
        """Dial an address when we do not know the peer id yet (join code / beacon)."""
        if self._closing:
            return False
        marker = f"addr:{host}:{port}"
        async with self._lock:
            if marker in self._pending:
                return False
            self._pending.add(marker)
        before = set(self._peers)
        try:
            try:
                reader, writer = await asyncio.wait_for(asyncio.open_connection(host, port), 5)
            except (OSError, asyncio.TimeoutError):
                return False
            task = asyncio.create_task(self._session(reader, writer))
            for _ in range(25):
                await asyncio.sleep(0.1)
                if set(self._peers) - before:
                    return True
                if task.done():
                    return False
            return bool(set(self._peers) - before)
        finally:
            async with self._lock:
                self._pending.discard(marker)

    def _chat_body(self, text: str, mid: str) -> dict:
        return {"t": "chat", "id": self.peer_id, "nick": self.nick, "text": text, "mid": mid}

    async def broadcast_chat(self, text: str) -> str:
        mid = new_message_id()
        key = self.get_room_key() if self.get_room_key else None
        if key is None:
            return mid
        blob = seal_chat(self._chat_body(text, mid), self.room, key)
        await self._broadcast({"t": "box", "b": blob})
        return mid

    async def announce_nick(self, nick: str) -> None:
        self.nick = nick
        await self._broadcast({"t": "nick", "id": self.peer_id, "nick": nick})

    async def broadcast_typing(self, active: bool) -> None:
        key = self.get_room_key() if self.get_room_key else None
        if key is None:
            return
        blob = seal_chat(
            {"t": "typing", "id": self.peer_id, "nick": self.nick, "on": active},
            self.room,
            key,
        )
        await self._broadcast({"t": "box", "b": blob})

    async def close(self) -> None:
        self._closing = True
        if self._server is not None:
            self._server.close()
            await self._server.wait_closed()
            self._server = None
        async with self._lock:
            peers = list(self._peers.values())
            self._peers.clear()
        for peer in peers:
            peer.close()
            if peer.task and peer.task is not asyncio.current_task():
                peer.task.cancel()
        await asyncio.gather(
            *(peer.writer.wait_closed() for peer in peers),
            return_exceptions=True,
        )

    async def _broadcast(self, payload: dict) -> None:
        blob = _pack(payload)
        async with self._lock:
            targets = list(self._peers.values())
        stale: list[Peer] = []
        for peer in targets:
            try:
                peer.writer.write(blob)
                await peer.writer.drain()
            except (OSError, ConnectionError):
                stale.append(peer)
        for peer in stale:
            await self._drop(peer.peer_id)

    async def _accept(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        if self._closing:
            writer.close()
            return
        await self._session(reader, writer)

    async def _session(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        peer: Peer | None = None
        try:
            writer.write(
                _pack(
                    {
                        "t": "hello",
                        "id": self.peer_id,
                        "nick": self.nick,
                        "room": self.room,
                        "pk": self.dh_pk_hex,
                    }
                )
            )
            await writer.drain()
            raw = await asyncio.wait_for(reader.readline(), 5)
            hello = _unpack(raw)
            if not hello or hello.get("t") != "hello":
                writer.close()
                return
            peer_id = str(hello.get("id") or "")
            nick = str(hello.get("nick") or "peer")[:24]
            if not peer_id or peer_id == self.peer_id:
                writer.close()
                return
            async with self._lock:
                if peer_id in self._peers:
                    writer.close()
                    return
                peer = Peer(peer_id=peer_id, nick=nick, reader=reader, writer=writer)
                peer.task = asyncio.current_task()
                self._peers[peer_id] = peer
            self.on_join(peer_id, nick)
            await self._read_loop(peer)
        except (OSError, ConnectionError, asyncio.TimeoutError, asyncio.CancelledError):
            pass
        finally:
            if peer is not None:
                await self._drop(peer.peer_id)
            else:
                try:
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    pass

    async def _read_loop(self, peer: Peer) -> None:
        while not self._closing:
            raw = await peer.reader.readline()
            if not raw:
                break
            msg = _unpack(raw)
            if not msg:
                continue
            kind = msg.get("t")
            if kind == "box":
                key = self.get_room_key() if self.get_room_key else None
                if key is None:
                    continue
                inner = open_chat(str(msg.get("b") or ""), self.room, key)
                if not inner:
                    continue
                kind = inner.get("t")
                msg = inner
            if kind == "chat":
                text = str(msg.get("text") or "")
                nick = str(msg.get("nick") or peer.nick)[:24]
                mid = str(msg.get("mid") or "")
                if text:
                    peer.nick = nick
                    self.on_chat(nick, text, mid, peer.peer_id)
            elif kind == "nick":
                nick = str(msg.get("nick") or "")[:24]
                if nick:
                    peer.nick = nick
                    self.on_nick(peer.peer_id, nick)
            elif kind == "typing":
                nick = str(msg.get("nick") or peer.nick)[:24]
                self.on_typing(nick, bool(msg.get("on")))

    async def _drop(self, peer_id: str) -> None:
        async with self._lock:
            peer = self._peers.pop(peer_id, None)
        if peer is None:
            return
        nick = peer.nick
        peer.close()
        try:
            await peer.writer.wait_closed()
        except Exception:
            pass
        if not self._closing:
            self.on_leave(peer_id, nick)
