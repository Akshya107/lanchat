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
from .crypto import from_hex, new_x25519
from .discovery import Discovery
from .hello import boot_sequence
from .join import encode_join, new_room_code, parse_target
from .net import Mesh
from .operator import device_id, has_master_key, import_operator_key, load_operator_key
from .roomctl import Member, RoomCtl
from .sound import play_ping
from .spam import BAN_SEC
from .store import MemoryStore
from .ui import ChatUI
from .util import default_nick, local_ipv4, local_ipv4_all, new_peer_id
from .policy import require_accept
from .wan import WanRoom

HELP = (
    "slash: /join /room /lock [ROOM|lan] /open /admit NAME /deny NAME /kick NAME /waiting "
    "/claim KEY /master /host /code /clear /peers /nick NAME /mute /quit"
)


class ChatApp:
    def __init__(self, nick: str, sound: bool = True) -> None:
        self.peer_id = new_peer_id()
        self.did = device_id()
        self.nick = nick[:24] or default_nick()
        self.local_ip = local_ipv4()
        self.sound = sound
        self.store = MemoryStore()
        self._dh_sk, _dh_pk = new_x25519()
        self.ctl: RoomCtl | None = None
        self.mesh = Mesh(
            peer_id=self.peer_id,
            nick=self.nick,
            on_chat=self._on_chat,
            on_join=self._on_join,
            on_leave=self._on_leave,
            on_nick=self._on_nick,
            on_typing=self._on_typing,
            dh_pk_hex=_dh_pk.hex(),
            get_room_key=self._room_key,
            on_signal=self._on_lan_signal,
        )
        self.discovery: Discovery | None = None
        self.beacon: Beacon | None = None
        self.wan: WanRoom | None = None
        self.room = new_room_code()
        self.mesh.room = self.room
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
        self._host_task: asyncio.Task[None] | None = None
        self._knock_task: asyncio.Task[None] | None = None
        self._running = True
        self._boot = seed_uptime()
        self._hinted: set[str] = set()
        self._lan_rooms: dict[str, str] = {}

    def _room_key(self) -> bytes | None:
        if self.ctl is None:
            return None
        return self.ctl.room_key

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
        role = "host" if self.ctl and self.ctl.is_host else "guest"
        mode = self.ctl.mode if self.ctl else "open"
        wait_n = len(self.ctl.waiting) if self.ctl else 0
        extra += f"  {role}  {mode}  waiting={wait_n}"
        if self.ctl and not self.ctl.admitted:
            extra += "  lobby"
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
        if self.ctl is not None and not self.ctl.admitted:
            return
        if self.ctl is not None and self.ctl.is_host and peer_id and peer_id != self.peer_id:
            if self.ctl.spam.note(peer_id, text):
                self._spam_kick(peer_id, nick)
                return
        if self.store.chat(nick, text, own=False, mid=mid):
            self.ui.invalidate()
            if self.sound:
                play_ping()

    def _spam_kick(self, peer_id: str, nick: str) -> None:
        if self.ctl is None or not self.ctl.is_host:
            return
        payloads = self.ctl.kick_payloads(peer_id or nick, spam=True)
        if not payloads:
            return
        self._sync_key()
        for payload in payloads:
            self._signal(payload)
        self._note(f"kicked {nick}  spam  wait {BAN_SEC}s")

    def _on_join(self, _peer_id: str, nick: str) -> None:
        self.store.system(f"node={nick} event=register region=local")
        self.ui.invalidate()

    def _on_leave(self, peer_id: str, nick: str) -> None:
        self.ui.set_typing(nick, False)
        if self.ctl is not None and peer_id:
            self.ctl.waiting.pop(peer_id, None)
            self.ctl.members.pop(peer_id, None)
        self.store.system(f"node={nick} event=drain region=local")
        self.ui.invalidate()

    def _on_typing(self, nick: str, active: bool) -> None:
        if self.ctl is not None and not self.ctl.admitted:
            return
        self.ui.set_typing(nick, active)

    def _on_local_typing(self, active: bool) -> None:
        if self.ctl is None or not self.ctl.admitted:
            return
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
        if room:
            self._lan_rooms[peer_id] = WanRoom._norm(room)
        if self._loop is None:
            return
        self._loop.create_task(self.mesh.connect(peer_id, nick, host, port))

    def _on_peer_down(self, _peer_id: str) -> None:
        return

    def _host_only(self) -> bool:
        if self.ctl is not None and self.ctl.is_host:
            return True
        self._note("host only")
        return False

    def _lan_other_rooms(self) -> list[str]:
        seen: list[str] = []
        for room in self._lan_rooms.values():
            if room and room != self.room and room not in seen:
                seen.append(room)
        return seen

    async def _operator_lock(self, raw: str) -> None:
        has_key = (self.ctl is not None and self.ctl.operator_sk is not None) or has_master_key()
        is_host = self.ctl is not None and self.ctl.is_host
        if not has_key and not is_host:
            self._note("master key or host only")
            return
        code = raw.strip()
        if code.lower() in {"lan", "wifi", "local"}:
            code = ""
        target = WanRoom._norm(code) if code else ""
        if not target:
            others = self._lan_other_rooms()
            if len(others) == 1:
                target = others[0]
                self._note(f"same network  taking room {target}")
            elif len(others) > 1:
                self._note("same network rooms: " + ", ".join(others) + "  type /lock CODE")
                await self._take_and_lock()
                return
        elif not has_key:
            self._note("master key needed to lock another room")
            return
        if target and target != self.room:
            await self._set_room(target)
        await self._take_and_lock()

    async def _take_and_lock(self) -> None:
        ctl = self.ctl
        if ctl is None:
            self._note("no room yet")
            return
        if ctl.operator_sk is None:
            ctl.operator_sk = load_operator_key()
        if not ctl.is_host:
            if ctl.operator_sk is None:
                self._note("master key or host only")
                return
            claim = ctl.claim_payload()
            if claim:
                self._signal(claim)
            await asyncio.sleep(0.4)
            if not self._running or self.ctl is not ctl:
                return
            ctl.become_host()
            self._sync_key()
            self._signal(ctl.host_payload())
            self._flush_door()
            self._start_host_beacon()
            self._note("you hold this room  (master key)")
        ctl.locked = True
        self._signal({"t": "mode", "mode": "private"})
        self._signal(ctl.host_payload())
        self._note(f"room {self.room} private  newcomers wait outside")

    def _on_lan_signal(self, payload: dict) -> None:
        self._on_wan(payload, "signal")

    def _signal(self, payload: dict) -> None:
        if self.ctl is not None:
            payload.setdefault("room", self.ctl.room)
        if self.wan is not None:
            self.wan.publish_signal(payload)
        self.mesh.broadcast_signal(payload)

    def _sync_key(self) -> None:
        if self.wan is not None and self.ctl is not None:
            self.wan.set_room_key(self.ctl.room_key)

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
                self._note("workers=1  waiting for LAN beacon")
            else:
                listing = ", ".join(f"{p.nick}" for p in peers)
                self._note(f"workers={listing}")
            return
        if lower in {"/code", "/listen"}:
            self._show_codes()
            return
        if lower == "/host":
            if self.ctl is None:
                self._note("no room yet")
                return
            role = "host" if self.ctl.is_host else "guest"
            door = "admitted" if self.ctl.admitted else "waiting outside"
            self._note(f"you={role}  room={self.room}  {self.ctl.mode}  {door}")
            return
        if lower == "/master":
            self._note("master key on this device" if has_master_key() else "no master key on this device")
            return
        if lower == "/waiting":
            if not self._host_only() or self.ctl is None:
                return
            if not self.ctl.waiting:
                self._note("door is empty")
                return
            names = ", ".join(f"{m.nick}" for m in self.ctl.waiting.values())
            self._note(f"waiting: {names}")
            return
        if lower == "/lock" or lower == "/private" or lower.startswith("/lock ") or lower.startswith("/private "):
            rest = text.split(maxsplit=1)
            code = rest[1].strip() if len(rest) > 1 else ""
            await self._operator_lock(code)
            return
        if lower in {"/open", "/unlock"}:
            if not self._host_only() or self.ctl is None:
                return
            self.ctl.locked = False
            self._signal({"t": "mode", "mode": "open"})
            self._signal(self.ctl.host_payload())
            for member in list(self.ctl.waiting.values()):
                payload = self.ctl.auto_admit_payload(member)
                if payload:
                    self._signal(payload)
            self._note("room open")
            return
        if lower.startswith("/admit"):
            if not self._host_only() or self.ctl is None:
                return
            parts = text.split(maxsplit=1)
            if len(parts) < 2:
                self._note("usage: /admit NAME")
                return
            payloads = self.ctl.admit_payloads(parts[1].strip())
            if not payloads:
                self._note("no one by that name at the door")
                return
            for payload in payloads:
                self._signal(payload)
            self._note(f"admitted {parts[1].strip()}")
            return
        if lower.startswith("/deny"):
            if not self._host_only() or self.ctl is None:
                return
            parts = text.split(maxsplit=1)
            if len(parts) < 2:
                self._note("usage: /deny NAME")
                return
            payload = self.ctl.deny_payload(parts[1].strip())
            if payload is None:
                self._note("no one by that name at the door")
                return
            self._signal(payload)
            self._note(f"denied {parts[1].strip()}")
            return
        if lower.startswith("/kick"):
            if not self._host_only() or self.ctl is None:
                return
            parts = text.split(maxsplit=1)
            if len(parts) < 2:
                self._note("usage: /kick NAME")
                return
            payloads = self.ctl.kick_payloads(parts[1].strip())
            if not payloads:
                self._note("no one by that name in the room")
                return
            self._sync_key()
            for payload in payloads:
                self._signal(payload)
            self._note(f"kicked {parts[1].strip()}")
            return
        if lower.startswith("/claim"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self._note("usage: /claim KEY   paste the master key")
                return
            sk = import_operator_key(parts[1].strip())
            if sk is None:
                self._note("claim failed")
                return
            if self.ctl is not None:
                self.ctl.operator_sk = sk
                self.ctl.host_id = self.peer_id
                claim = self.ctl.claim_payload()
                if claim:
                    self._signal(claim)
                await asyncio.sleep(1.0)
                if self.ctl is not None:
                    self.ctl.become_host()
                    self._sync_key()
                    self._signal(self.ctl.host_payload())
                    self._start_host_beacon()
            self._note("you hold this room")
            return
        if lower.startswith("/join"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self.store.add("own", "*", "usage: /join LAN-CODE   or  /join ROOM   or  /join 192.168.1.10:1234")
                self.ui.invalidate()
                return
            await self._join_target(parts[1].strip())
            return
        if lower.startswith("/room"):
            parts = text.split(maxsplit=1)
            if len(parts) < 2 or not parts[1].strip():
                self.store.add("own", "*", f"room {self.room}   friend types: /room {self.room}")
                self.ui.invalidate()
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
            if self.ctl is not None:
                self.ctl.nick = new_nick
            self._note(f"{old} is now {new_nick}")
            return
        if text.startswith("/"):
            self._note(f"Unknown command {text.split()[0]}. Try /help")
            return
        if self.ctl is None or not self.ctl.admitted:
            self._note("waiting outside  host has not let you in")
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
            self.store.add("own", "*", f"join {code}   ({ip}:{self.tcp_port})  same Wi-Fi")
        self.store.add("own", "*", f"room {self.room}   any internet: /room {self.room}")
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
        if self._host_task is not None:
            self._host_task.cancel()
            self._host_task = None
        self._stop_knocking()
        if self.wan is not None:
            self.wan.close(clear_retain=self.ctl.is_host if self.ctl else False)
            self.wan = None
        self.room = room
        self.mesh.room = room
        if self.beacon is not None:
            self.beacon.room = room
        if self.discovery is not None:
            await self.discovery.set_room(room)
        self.ctl = RoomCtl(
            peer_id=self.peer_id,
            nick=self.nick,
            room=room,
            dh_sk=self._dh_sk,
            operator_sk=load_operator_key(),
        )
        self.wan = WanRoom(self.peer_id, self.nick, self.room, self._on_wan)
        ok = await self.wan.start()
        if not ok:
            self.wan = None
            self.store.add("own", "*", "room offline  no internet?")
            self.ui.invalidate()
            return
        self.store.add("own", "*", f"room {self.room}  internet on")
        self.ui.invalidate()
        await self._enter_room()

    async def _enter_room(self) -> None:
        ctl = self.ctl
        if ctl is None:
            return
        self._stop_knocking()
        self._signal(ctl.ask_payload(self.did))
        for _ in range(5):
            await asyncio.sleep(1.0)
            if not self._running or self.ctl is not ctl:
                return
            if ctl.admitted or (ctl.host_id and ctl.host_id != ctl.peer_id):
                break
            self._signal(ctl.ask_payload(self.did))
        if not self._running or self.ctl is not ctl:
            return
        if ctl.host_id and ctl.host_id != ctl.peer_id:
            if ctl.operator_sk is not None:
                claim = ctl.claim_payload()
                if claim:
                    self._signal(claim)
                await asyncio.sleep(0.4)
                if not self._running or self.ctl is not ctl:
                    return
                ctl.become_host()
                self._sync_key()
                self._signal(ctl.host_payload())
                self._flush_door()
                self._note("you hold this room  (master key)")
                self._start_host_beacon()
                return
            if ctl.admitted:
                self._note("in the room")
                return
            if ctl.locked:
                self._note("waiting outside  host must /admit you")
            else:
                self._note("knocking  waiting for host key")
            self._start_knocking()
            return
        ctl.become_host()
        self._sync_key()
        self._signal(ctl.host_payload())
        self._flush_door()
        self._note("you are host of this room")
        self._start_host_beacon()

    def _flush_door(self) -> None:
        ctl = self.ctl
        if ctl is None or not ctl.is_host:
            return
        for member in list(ctl.waiting.values()):
            if ctl.is_muted(member.peer_id, member.nick, member.pk, member.did):
                left = ctl.mute_left(member.peer_id, member.nick, member.pk, member.did)
                self._signal({"t": "deny", "to": member.peer_id, "why": "spam", "sec": left})
                continue
            if not ctl.locked and member.peer_id not in ctl.kicked:
                admit = ctl.auto_admit_payload(member)
                if admit:
                    self._signal(admit)
            elif ctl.locked:
                self._note(f"{member.nick} waits at the door  /admit {member.nick}")

    def _start_knocking(self) -> None:
        if self._loop is None:
            return
        self._stop_knocking()
        self._knock_task = self._loop.create_task(self._knock_loop())

    def _stop_knocking(self) -> None:
        if self._knock_task is not None:
            self._knock_task.cancel()
            self._knock_task = None

    async def _knock_loop(self) -> None:
        try:
            while self._running and self.ctl is not None and not self.ctl.is_host and not self.ctl.admitted:
                self._signal(self.ctl.ask_payload(self.did))
                await asyncio.sleep(2)
        except asyncio.CancelledError:
            return

    def _start_host_beacon(self) -> None:
        if self._loop is None:
            return
        self._stop_knocking()
        if self._host_task is not None:
            self._host_task.cancel()
        self._host_task = self._loop.create_task(self._host_beacon())

    async def _host_beacon(self) -> None:
        try:
            while self._running and self.ctl is not None and self.ctl.is_host and self.wan is not None:
                self._signal(self.ctl.host_payload())
                await asyncio.sleep(3)
        except asyncio.CancelledError:
            return

    def _hint_other_room(self, peer_id: str, nick: str, room: str) -> None:
        key = f"{peer_id}:{room}"
        if not room or key in self._hinted:
            return
        self._hinted.add(key)
        self._note(f"{nick} is in room {room}  type /room {room} to join")

    def _on_ask(self, peer_id: str, nick: str, pk: bytes, did: str) -> None:
        if self.ctl is None:
            return
        member = Member(peer_id, nick, pk, did)
        self.ctl.remember(peer_id, nick, pk, did)
        if not self.ctl.is_host:
            return
        if self.ctl.is_muted(peer_id, nick, pk, did):
            left = self.ctl.mute_left(peer_id, nick, pk, did)
            self._signal({"t": "deny", "to": peer_id, "why": "spam", "sec": left})
            self._note(f"{nick} blocked for spam  {left}s")
            return
        if not self.ctl.locked and peer_id not in self.ctl.kicked:
            admit = self.ctl.auto_admit_payload(member)
            if admit:
                self._signal(admit)
        elif self.ctl.locked:
            self._note(f"{nick} waits at the door  /admit {nick}")

    def _on_wan(self, payload: dict, channel: str = "signal") -> None:
        if self.ctl is None:
            return
        kind = str(payload.get("t") or "")
        nick = str(payload.get("nick") or "peer")[:24]
        peer_id = str(payload.get("id") or "")
        other_room = str(payload.get("room") or "")
        if other_room:
            self._lan_rooms[peer_id] = WanRoom._norm(other_room)
        if channel != "chat" and other_room and other_room != self.room:
            if kind == "hello":
                self._hint_other_room(peer_id, nick, other_room)
            return
        if channel == "chat":
            if not self.ctl.admitted:
                return
            if kind == "chat":
                self._on_chat(
                    nick,
                    str(payload.get("text") or ""),
                    str(payload.get("mid") or ""),
                    peer_id,
                )
            elif kind == "typing":
                self._on_typing(nick, bool(payload.get("on")))
            return
        if kind == "claim":
            was_host = self.ctl.is_host
            if not self.ctl.take_claim(payload):
                return
            if was_host and not self.ctl.is_host:
                handoff = self.ctl.handoff_payload(peer_id)
                if handoff:
                    self._signal(handoff)
                self._note(f"{nick} took host with the master key")
            elif self.ctl.is_host:
                self._sync_key()
                self._start_host_beacon()
                self._note("you hold this room")
            self.ui.invalidate()
            return
        if kind == "host":
            if peer_id == self.peer_id:
                return
            yielded = self.ctl.on_host(payload)
            if yielded:
                self._sync_key()
                self._signal(self.ctl.ask_payload(self.did))
                self._note("yielding host")
            elif not self.ctl.is_host and not self.ctl.admitted:
                self._signal(self.ctl.ask_payload(self.did))
            self.ui.invalidate()
            return
        if kind == "mode":
            if not self.ctl.is_host:
                self.ctl.locked = str(payload.get("mode") or "open") == "private"
                self.ui.invalidate()
            return
        if kind == "ask":
            pk = _pk_bytes(payload.get("pk"))
            if pk is None:
                return
            self._on_ask(peer_id, nick, pk, str(payload.get("did") or "")[:32])
            return
        if kind in {"admit", "rekey", "handoff"}:
            if str(payload.get("to") or "") != self.peer_id:
                return
            if self.ctl.accept_key(str(payload.get("box") or ""), int(payload.get("epoch") or 0)):
                self._stop_knocking()
                self._sync_key()
                self._note("in the room" if kind != "rekey" else "room key rotated")
            return
        if kind == "deny":
            if str(payload.get("to") or "") == self.peer_id:
                why = str(payload.get("why") or "")
                sec = int(payload.get("sec") or 0)
                if why == "spam":
                    self._note(f"host blocked you for spam  wait {sec or BAN_SEC}s")
                else:
                    self._note("host kept you outside")
            return
        if kind == "kick":
            if str(payload.get("to") or "") != self.peer_id:
                return
            self.ctl.room_key = None
            self._sync_key()
            if self.wan is not None:
                self.wan.close()
                self.wan = None
            self._note("kicked  session closed for this room")
            why = str(payload.get("why") or "")
            sec = int(payload.get("sec") or 0)
            if why == "spam":
                self._note(f"spam filter  wait {sec or BAN_SEC}s before joining again")
            return
        if kind == "hello":
            pk = _pk_bytes(payload.get("pk"))
            if pk is not None:
                self._on_ask(peer_id, nick, pk, str(payload.get("did") or "")[:32])
            return
        elif kind == "bye":
            self.ui.set_typing(nick, False)
            if peer_id:
                self.ctl.waiting.pop(peer_id, None)
                self.ctl.members.pop(peer_id, None)
                if self.ctl.host_id == peer_id and not self.ctl.is_host:
                    self.ctl.host_id = None
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
        self._stop_knocking()
        if self._host_task is not None:
            self._host_task.cancel()
            self._host_task = None
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
                self.wan.close(clear_retain=bool(self.ctl and self.ctl.is_host))
            except Exception:
                pass
            self.wan = None
        try:
            await self.mesh.close()
        except Exception:
            pass
        self.store.clear()


def _pk_bytes(value: object) -> bytes | None:
    try:
        raw = from_hex(str(value or ""))
        return raw if len(raw) == 32 else None
    except Exception:
        return None


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
