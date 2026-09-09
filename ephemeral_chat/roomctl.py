"""Room host, lock, waiting list, and key rotation. RAM only."""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from .crypto import hex_of, new_room_key, unwrap_room_key, wrap_room_key, x25519_public
from .operator import sign_claim, verify_claim
from .spam import BAN_SEC, SpamWatch


@dataclass
class Member:
    peer_id: str
    nick: str
    pk: bytes
    did: str = ""


@dataclass
class RoomCtl:
    peer_id: str
    nick: str
    room: str
    dh_sk: bytes
    operator_sk: Ed25519PrivateKey | None = None
    host_id: str | None = None
    locked: bool = False
    room_key: bytes | None = None
    epoch: int = 0
    waiting: dict[str, Member] = field(default_factory=dict)
    members: dict[str, Member] = field(default_factory=dict)
    kicked: set[str] = field(default_factory=set)
    muted_until: dict[str, float] = field(default_factory=dict)
    spam: SpamWatch = field(default_factory=SpamWatch)
    seen_claim_ts: int = 0

    @property
    def dh_pk(self) -> bytes:
        return x25519_public(self.dh_sk)

    @property
    def dh_pk_hex(self) -> str:
        return hex_of(self.dh_pk)

    @property
    def is_host(self) -> bool:
        return self.host_id == self.peer_id

    @property
    def admitted(self) -> bool:
        return self.room_key is not None

    @property
    def mode(self) -> str:
        return "private" if self.locked else "open"

    def remember(self, peer_id: str, nick: str, pk: bytes | None, did: str = "") -> None:
        if not peer_id or peer_id == self.peer_id or not pk or len(pk) != 32:
            return
        nick = (nick or "peer")[:24]
        did = (did or "")[:32]
        if peer_id in self.members:
            self.members[peer_id].nick = nick
            self.members[peer_id].pk = pk
            if did:
                self.members[peer_id].did = did
        elif peer_id in self.waiting:
            self.waiting[peer_id].nick = nick
            self.waiting[peer_id].pk = pk
            if did:
                self.waiting[peer_id].did = did
        elif peer_id not in self.kicked:
            self.waiting[peer_id] = Member(peer_id, nick, pk, did)

    def become_host(self) -> None:
        self.host_id = self.peer_id
        if self.room_key is None:
            self.room_key = new_room_key()
            self.epoch += 1
        self.members[self.peer_id] = Member(self.peer_id, self.nick, self.dh_pk)
        self.waiting.pop(self.peer_id, None)

    def host_payload(self) -> dict:
        return {
            "t": "host",
            "id": self.peer_id,
            "nick": self.nick,
            "pk": self.dh_pk_hex,
            "mode": self.mode,
            "epoch": self.epoch,
        }

    def ask_payload(self, did: str = "") -> dict:
        body = {"t": "ask", "id": self.peer_id, "nick": self.nick, "pk": self.dh_pk_hex}
        if did:
            body["did"] = did
        return body

    def claim_payload(self) -> dict | None:
        if self.operator_sk is None:
            return None
        ts = int(time.time())
        sig = sign_claim(self.operator_sk, self.room, self.peer_id, ts, self.dh_pk_hex)
        return {
            "t": "claim",
            "id": self.peer_id,
            "nick": self.nick,
            "pk": self.dh_pk_hex,
            "ts": ts,
            "sig": sig,
        }

    def accept_key(self, box: str, epoch: int | None = None) -> bool:
        key = unwrap_room_key(box, self.dh_sk)
        if key is None:
            return False
        self.room_key = key
        if epoch is not None and epoch > 0:
            self.epoch = epoch
        self.waiting.pop(self.peer_id, None)
        self.members[self.peer_id] = Member(self.peer_id, self.nick, self.dh_pk)
        return True

    def take_claim(self, payload: dict) -> bool:
        peer_id = str(payload.get("id") or "")
        nick = str(payload.get("nick") or "operator")[:24]
        pk_hex = str(payload.get("pk") or "")
        ts = int(payload.get("ts") or 0)
        sig = str(payload.get("sig") or "")
        if not peer_id or ts <= self.seen_claim_ts:
            return False
        if not verify_claim(self.room, peer_id, ts, pk_hex, sig):
            return False
        try:
            pk = bytes.fromhex(pk_hex)
        except ValueError:
            return False
        if len(pk) != 32:
            return False
        self.seen_claim_ts = ts
        self.host_id = peer_id
        self.kicked.discard(peer_id)
        if peer_id != self.peer_id:
            self.members[peer_id] = Member(peer_id, nick, pk)
            self.waiting.pop(peer_id, None)
        return True

    def on_host(self, payload: dict) -> bool:
        """Apply a host announcement. Returns True if we yielded and should re-ask."""
        peer_id = str(payload.get("id") or "")
        if not peer_id or peer_id == self.peer_id:
            return False
        if self.operator_sk is not None and self.is_host:
            return False
        if self.is_host and peer_id > self.peer_id:
            return False
        yielded = self.is_host and peer_id < self.peer_id
        if yielded:
            self.room_key = None
        self.host_id = peer_id
        self.locked = str(payload.get("mode") or "open") == "private"
        epoch = int(payload.get("epoch") or 0)
        if epoch > self.epoch:
            self.epoch = epoch
        nick = str(payload.get("nick") or "host")[:24]
        try:
            pk = bytes.fromhex(str(payload.get("pk") or ""))
        except ValueError:
            pk = b""
        if len(pk) == 32:
            self.members[peer_id] = Member(peer_id, nick, pk)
            self.waiting.pop(peer_id, None)
        return yielded

    def wrap_for(self, pk: bytes) -> str | None:
        if self.room_key is None or len(pk) != 32:
            return None
        return wrap_room_key(self.room_key, pk)

    def admit_payloads(self, target: str) -> list[dict]:
        member = self.waiting.pop(target, None) or self.members.get(target)
        if member is None:
            want = target.lower()
            for mid, row in list(self.waiting.items()):
                if row.nick.lower() == want:
                    member = self.waiting.pop(mid)
                    break
        if member is None or self.room_key is None:
            return []
        self.kicked.discard(member.peer_id)
        self._clear_mute(member)
        self.members[member.peer_id] = member
        box = self.wrap_for(member.pk)
        if not box:
            return []
        return [{"t": "admit", "to": member.peer_id, "epoch": self.epoch, "box": box}]

    def deny_payload(self, target: str) -> dict | None:
        member = self.waiting.pop(target, None)
        if member is None:
            want = target.lower()
            for mid, row in list(self.waiting.items()):
                if row.nick.lower() == want:
                    member = self.waiting.pop(mid)
                    break
        if member is None:
            return None
        return {"t": "deny", "to": member.peer_id}

    def kick_payloads(self, target: str, *, spam: bool = False) -> list[dict]:
        member = self.members.get(target)
        if member is None:
            want = target.lower()
            for mid, row in list(self.members.items()):
                if row.nick.lower() == want and mid != self.peer_id:
                    member = row
                    break
        if member is None or member.peer_id == self.peer_id:
            return []
        self.members.pop(member.peer_id, None)
        self.waiting.pop(member.peer_id, None)
        if spam:
            self._mute(member, BAN_SEC)
        else:
            self.kicked.add(member.peer_id)
        self.room_key = new_room_key()
        self.epoch += 1
        kick: dict = {"t": "kick", "to": member.peer_id}
        if spam:
            kick["why"] = "spam"
            kick["sec"] = BAN_SEC
        out: list[dict] = [kick]
        for row in self.members.values():
            if row.peer_id == self.peer_id:
                continue
            box = self.wrap_for(row.pk)
            if box:
                out.append({"t": "rekey", "to": row.peer_id, "epoch": self.epoch, "box": box})
        return out

    def auto_admit_payload(self, member: Member) -> dict | None:
        if self.room_key is None:
            return None
        self.waiting.pop(member.peer_id, None)
        self.members[member.peer_id] = member
        box = self.wrap_for(member.pk)
        if not box:
            return None
        return {"t": "admit", "to": member.peer_id, "epoch": self.epoch, "box": box}

    def handoff_payload(self, to_id: str) -> dict | None:
        row = self.members.get(to_id) or self.waiting.get(to_id)
        if row is None or self.room_key is None:
            return None
        box = self.wrap_for(row.pk)
        if not box:
            return None
        return {"t": "handoff", "to": to_id, "epoch": self.epoch, "box": box}

    def find_nick(self, peer_id: str) -> str:
        if peer_id in self.members:
            return self.members[peer_id].nick
        if peer_id in self.waiting:
            return self.waiting[peer_id].nick
        return "peer"

    def member_for(self, peer_id: str, nick: str = "") -> Member | None:
        if peer_id and peer_id in self.members:
            return self.members[peer_id]
        want = nick.lower()
        if not want:
            return None
        for row in self.members.values():
            if row.nick.lower() == want and row.peer_id != self.peer_id:
                return row
        return None

    def is_muted(self, peer_id: str, nick: str, pk: bytes | None = None, did: str = "") -> bool:
        now = time.time()
        keys = [peer_id, nick.lower()]
        if pk is not None and len(pk) == 32:
            keys.append(hex_of(pk))
        if did:
            keys.append(did)
        return any(self.muted_until.get(k, 0) > now for k in keys if k)

    def mute_left(self, peer_id: str, nick: str, pk: bytes | None = None, did: str = "") -> int:
        now = time.time()
        keys = [peer_id, nick.lower()]
        if pk is not None and len(pk) == 32:
            keys.append(hex_of(pk))
        if did:
            keys.append(did)
        left = 0.0
        for k in keys:
            if not k:
                continue
            left = max(left, self.muted_until.get(k, 0) - now)
        return max(0, int(left + 0.99))

    def _mute(self, member: Member, seconds: int) -> None:
        until = time.time() + seconds
        self.muted_until[member.peer_id] = until
        self.muted_until[member.nick.lower()] = until
        self.muted_until[hex_of(member.pk)] = until
        if member.did:
            self.muted_until[member.did] = until
        self.spam.forget(member.peer_id)

    def _clear_mute(self, member: Member) -> None:
        self.muted_until.pop(member.peer_id, None)
        self.muted_until.pop(member.nick.lower(), None)
        self.muted_until.pop(hex_of(member.pk), None)
        if member.did:
            self.muted_until.pop(member.did, None)
