"""Orchestrate discovery, TCP mesh, in-memory store, and the TUI."""

from __future__ import annotations

import argparse
import asyncio
import logging
import signal
import sys
import time
from collections.abc import Sequence

from . import __version__
from .beacon import Beacon
from .camouflage import fake_line, jitter_delay, seed_uptime
from .crypto import LAN_ROOM, lan_aes_key, new_x25519, room_aes_key
from .discovery import Discovery
from .hello import boot_sequence
from .join import encode_join, new_room_code, parse_target
from .net import Mesh
from .sound import play_ping
from .store import MemoryStore
from .ui import ChatUI
from .util import default_nick, local_ipv4, local_ipv4_all, new_peer_id
from .policy import require_accept
from .wan import WanRoom

HELP = "slash: /join /room /code /clear /peers /nick NAME /mute /quit"


class ChatApp:
    def __init__(self, nick: str, sound: bool = True) -> None:
        self.peer_id = new_peer_id()
        self.nick = nick[:24] or default_nick()
        self.local_ip = local_ipv4()
        self.sound = sound
        self.store = MemoryStore()
        self._dh_sk, _dh_pk = new_x25519()
        self.mesh = Mesh(
            peer_id=self.peer_id,
            nick=self.nick,
            on_chat=self._on_chat,
            on_join=self._on_join,
            on_leave=self._on_leave,
            on_nick=self._on_nick,
            on_typing=self._on_typing,
            room=LAN_ROOM,
            dh_pk_hex=_dh_pk.hex(),
            get_room_key=lan_aes_key,
        )
        self.discovery: Discovery | None = None
        self.beacon: Beacon | None = None
        self.wan: WanRoom | None = None
        self.room = new_room_code()
        self.tcp_port = 0
        self._last_typing_sent = 0.0
        self._typing_on = False
        self.ui = ChatUI(
            store=self.store,
            status=self._status,
            on_submit=self._on_submit,
            on_clear=self.clear_history,
            on_quit=self._request_exit,
            on_typing=self._on_local_typing,
        )
        self._loop: asyncio.AbstractEventLoop | None = None
        self._log_task: asyncio.Task[None] | None = None
        self._running = True
        self._boot = seed_uptime()

    def _join_code(self) -> str:
        try:
            return encode_join(self.local_ip, self.tcp_port)
        except Exception:
            return ""

    def _status(self) -> str:
        n = len(self.mesh.peers) + 1
        token = self._join_code().replace("-", "")
        extra = f"  token={token}" if token else ""
        extra += f"  room={self.room}"
        return (
            f"api-gateway  {self.local_ip}  workers={n}  "
            f"tail=/var/log/api/access.log  {self._boot}{extra}"
        )

    def _on_submit(self, raw: str) -> None:
        if self._loop is None:
            return
        self._loop.create_task(self._handle_line(raw))

    def _request_exit(self) -> None:
        self.ui.exit()

    def clear_history(self) -> None:
        self.store.clear()
        self.ui.invalidate()

    def _note(self, text: str) -> None:
        self.store.system(text)
        self.ui.invalidate()

    def _on_chat(self, nick: str, text: str, mid: str, peer_id: str = "") -> None:
        if self.store.chat(nick, text, own=False, mid=mid):
            self.ui.invalidate()
            if self.sound:
                play_ping()

    def _on_join(self, _peer_id: str, nick: str) -> None:
        self.store.system(f"node={nick} event=register region=local")
        self.ui.invalidate()

    def _on_leave(self, peer_id: str, nick: str) -> None:
        self.ui.set_typing(nick, False)
        self.store.system(f"node={nick} event=drain region=local")
        self.ui.invalidate()

    def _on_typing(self, nick: str, active: bool) -> None:
        self.ui.set_typing(nick, active)

    def _on_local_typing(self, active: bool) -> None:
        now = time.time()
        if active and self._typing_on and now - self._last_typing_sent < 0.4:
            return
        if not active and not self._typing_on:
            return
        self._typing_on = active
        self._last_typing_sent = now
        if self._loop is None:
            return
        self._loop.create_task(self._emit_typing(active))

    async def _emit_typing(self, active: bool) -> None:
        try:
            await self.mesh.broadcast_typing(active)
        except Exception:
            pass
        if self.wan is not None:
            self.wan.publish_chat({"t": "typing", "on": active})

    def _on_nick(self, _peer_id: str, _nick: str) -> None:
        self.ui.invalidate()

    def _on_peer_up(self, peer_id: str, nick: str, host: str, port: int, room: str = "") -> None:
        if self._loop is None:
            return
        self._loop.create_task(self.mesh.connect(peer_id, nick, host, port))

    def _on_peer_down(self, _peer_id: str) -> None:
        return

    async def _handle_line(self, raw: str) -> None:
        text = raw.strip()
        if not text:
            return
        lower = text.lower()
        if lower in {"/clear", "/cls", "cls"}:
            self.clear_history()
            return
        if lower in {"/quit", "/exit", "/q"}:
            self._request_exit()
            return
        if lower in {"/help", "/?"}:
            self._note(HELP)
            return
        if lower == "/peers":
            peers = self.mesh.peers
            if not peers:
                self._note("workers=1  same Wi-Fi will show up here")
            else:
                listing = ", ".join(f"{p.nick}" for p in peers)
                self._note(f"workers={listing}")
            return
        if lower in {"/code", "/listen"}:
            self._show_codes()
            return
        if lower.startswith("/join"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self._note("usage: /join LAN-CODE   or  /join 192.168.1.10:1234")
                return
            await self._join_target(parts[1].strip())
            return
        if lower.startswith("/room"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self._note(f"room {self.room}   friend on another network: /room {self.room}")
                return
            await self._set_room(parts[1].strip())
            return
        if lower in {"/mute", "/quiet"}:
            self.sound = False
            self._note("Ping muted")
            return
        if lower in {"/unmute", "/sound"}:
            self.sound = True
            self._note("Ping on")
            return
        if lower.startswith("/nick"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self._note("Usage: /nick NAME")
                return
            new_nick = parts[1].strip()[:24]
            old = self.nick
            self.nick = new_nick
            await self.mesh.announce_nick(new_nick)
            if self.discovery is not None:
                await self.discovery.set_nick(new_nick)
            if self.wan is not None:
                self.wan.set_nick(new_nick)
            self._note(f"{old} is now {new_nick}")
            return
        if text.startswith("/"):
            self._note(f"Unknown command {text.split()[0]}. Try /help")
            return
        text = text[:2000]
        mid = await self.mesh.broadcast_chat(text)
        if self.wan is not None:
            self.wan.publish_chat({"t": "chat", "text": text, "mid": mid})
        self.store.chat(self.nick, text, own=True, mid=mid)
        self.ui.invalidate()

    def _show_codes(self) -> None:
        if not self.tcp_port:
            return
        for ip, _broadcast in local_ipv4_all():
            try:
                code = encode_join(ip, self.tcp_port)
            except Exception:
                continue
            self.store.add("own", "*", f"same Wi-Fi: just open lanchat  backup /join {code}")
        self.store.add("own", "*", f"other network: /room {self.room}")
        self.ui.invalidate()

    async def _join_target(self, raw: str) -> None:
        compact = "".join(ch for ch in raw.upper() if ch.isalnum())
        if 4 <= len(compact) <= 8 and ":" not in raw and "." not in raw:
            await self._set_room(compact)
            return
        try:
            host, port = parse_target(raw)
        except Exception:
            self.store.add("own", "*", "bad join code")
            self.ui.invalidate()
            return
        ok = await self.mesh.connect_host(host, port)
        if ok:
            self.store.add("own", "*", f"joined {host}:{port}")
        else:
            self.store.add("own", "*", f"join failed {host}:{port}  same Wi-Fi/hotspot?")
        self.ui.invalidate()

    async def _set_room(self, code: str) -> None:
        room = WanRoom._norm(code)
        if len(room) < 4:
            self.store.add("own", "*", "room code too short")
            self.ui.invalidate()
            return
        if self.wan is not None:
            self.wan.close()
            self.wan = None
        self.room = room
        if self.beacon is not None:
            self.beacon.room = room
        if self.discovery is not None:
            await self.discovery.set_room(room)
        self.wan = WanRoom(self.peer_id, self.nick, self.room, self._on_wan)
        ok = await self.wan.start()
        if not ok:
            self.wan = None
            self.store.add("own", "*", "internet room offline  same Wi-Fi still works")
            self.ui.invalidate()
            return
        self.wan.set_room_key(room_aes_key(self.room))
        self.store.add("own", "*", f"room {self.room}  internet on")
        self.ui.invalidate()

    def _on_wan(self, payload: dict, channel: str = "signal") -> None:
        kind = str(payload.get("t") or "")
        nick = str(payload.get("nick") or "peer")[:24]
        if channel == "chat":
            if kind == "chat":
                self._on_chat(nick, str(payload.get("text") or ""), str(payload.get("mid") or ""))
            elif kind == "typing":
                self._on_typing(nick, bool(payload.get("on")))
            return
        if kind == "bye":
            self.ui.set_typing(nick, False)
            self.store.system(f"node={nick} event=drain region=wan")
            self.ui.invalidate()

    async def run(self) -> None:
        self._loop = asyncio.get_running_loop()
        self.tcp_port = await self.mesh.start()
        self.local_ip = local_ipv4()
        self.discovery = Discovery(
            peer_id=self.peer_id,
            nick=self.nick,
            port=self.tcp_port,
            local_ip=self.local_ip,
            on_up=self._on_peer_up,
            on_down=self._on_peer_down,
        )
        try:
            await self.discovery.start()
        except Exception:
            try:
                await self.discovery.stop()
            except Exception:
                pass
            self.discovery = None
        self.beacon = Beacon(self.peer_id, self.nick, self.tcp_port, self._on_peer_up, room=self.room)
        try:
            await self.beacon.start()
        except Exception:
            self.beacon = None
        self._loop.create_task(self._opening())
        try:
            await self.ui.run()
        finally:
            await self._shutdown()

    async def _opening(self) -> None:
        for kind, line in boot_sequence(self.nick):
            if not self._running:
                return
            self.store.add(kind, "", line)
            self.ui.invalidate()
            await asyncio.sleep(0.22)
        play_ping()
        self._show_codes()
        await self._set_room(self.room)
        if not self._running:
            return
        self._log_task = self._loop.create_task(self._pump_logs()) if self._loop else None

    async def _pump_logs(self) -> None:
        while self._running:
            try:
                await asyncio.sleep(jitter_delay())
            except asyncio.CancelledError:
                return
            if not self._running:
                return
            self.store.log(fake_line())
            self.ui.invalidate()

    async def _shutdown(self) -> None:
        self._running = False
        if self._log_task is not None:
            self._log_task.cancel()
            try:
                await self._log_task
            except (asyncio.CancelledError, Exception):
                pass
            self._log_task = None
        if self.discovery is not None:
            try:
                await self.discovery.stop()
            except Exception:
                pass
            self.discovery = None
        if self.beacon is not None:
            try:
                await self.beacon.stop()
            except Exception:
                pass
            self.beacon = None
        if self.wan is not None:
            try:
                self.wan.close()
            except Exception:
                pass
            self.wan = None
        try:
            await self.mesh.close()
        except Exception:
            pass
        self.store.clear()


def _silence_libraries() -> None:
    logging.disable(logging.CRITICAL)


def _install_signal_handlers(app: ChatApp) -> None:
    if sys.platform == "win32":
        return

    def _stop(*_args: object) -> None:
        app._request_exit()

    try:
        loop = asyncio.get_running_loop()
        loop.add_signal_handler(signal.SIGINT, _stop)
        loop.add_signal_handler(signal.SIGTERM, _stop)
    except (NotImplementedError, RuntimeError):
        pass


async def _async_main(nick: str, sound: bool) -> None:
    app = ChatApp(nick, sound=sound)
    _install_signal_handlers(app)
    await app.run()


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(
        prog="lanchat",
        description="Peer-to-peer ephemeral LAN chat. Type lanchat and press Enter to start.",
    )
    parser.add_argument("-n", "--name", default=default_nick(), help="Display name (default: login name)")
    parser.add_argument("--mute", action="store_true", help="Disable the incoming-message ting")
    parser.add_argument("--no-update", action="store_true", help="Do not pull the latest GitHub build on launch")
    parser.add_argument("-V", "--version", action="version", version=f"lanchat {__version__}")
    args = parser.parse_args(list(argv) if argv is not None else None)

    _silence_libraries()
    if not args.no_update:
        from .update import maybe_update

        maybe_update(list(argv) if argv is not None else sys.argv[1:])
    require_accept()
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    try:
        asyncio.run(_async_main(args.name, sound=not args.mute))
    except KeyboardInterrupt:
        pass
    finally:
        print("session closed.")
