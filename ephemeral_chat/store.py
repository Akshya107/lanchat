"""RAM-only message history. Never touches the filesystem."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from time import time

_SEEN_CAP = 400


@dataclass
class Message:
    kind: str  # "chat" | "own" | "sys"
    nick: str
    text: str
    ts: float
    mid: str = ""

    def wipe(self) -> None:
        self.nick = ""
        self.text = ""
        self.mid = ""
        self.kind = ""
        self.ts = 0.0


class MemoryStore:
    """Bounded in-memory log. `clear()` drops every message immediately."""

    def __init__(self, limit: int = 700) -> None:
        self.limit = limit
        self.messages: list[Message] = []
        self._seen: set[str] = set()
        self._seen_order: deque[str] = deque()

    def remember_id(self, mid: str) -> bool:
        """Return False if this message id was already received."""
        if not mid:
            return True
        if mid in self._seen:
            return False
        if len(self._seen_order) >= _SEEN_CAP:
            old = self._seen_order.popleft()
            self._seen.discard(old)
        self._seen.add(mid)
        self._seen_order.append(mid)
        return True

    def add(self, kind: str, nick: str, text: str, mid: str = "", ts: float | None = None) -> Message | None:
        if mid and not self.remember_id(mid):
            return None
        msg = Message(kind=kind, nick=nick, text=text, ts=time() if ts is None else ts, mid=mid)
        self.messages.append(msg)
        overflow = len(self.messages) - self.limit
        if overflow > 0:
            for dropped in self.messages[:overflow]:
                dropped.wipe()
            del self.messages[:overflow]
        return msg

    def log(self, text: str) -> Message | None:
        return self.add("log", "", text)

    def chat(self, nick: str, text: str, *, own: bool, mid: str) -> Message | None:
        return self.add("own" if own else "chat", nick, text, mid=mid)

    def system(self, text: str) -> Message | None:
        return self.add("sys", "*", text)

    def clear(self) -> None:
        for msg in self.messages:
            msg.wipe()
        self.messages.clear()
        self._seen.clear()
        self._seen_order.clear()
