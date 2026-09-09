"""Host-side spam detector. RAM only."""

from __future__ import annotations

import time
from collections import defaultdict, deque

BAN_SEC = 30
BURST_N = 4
BURST_SEC = 2.0
REPEAT_N = 3
REPEAT_SEC = 10.0
RAPID_N = 3
RAPID_GAP = 0.4


def _norm(text: str) -> str:
    return " ".join(text.lower().split())


class SpamWatch:
    def __init__(self) -> None:
        self._events: dict[str, deque[tuple[float, str]]] = defaultdict(deque)

    def note(self, who: str, text: str, now: float | None = None) -> bool:
        """Record a chat line. True if this sender is spamming."""
        if not who:
            return False
        now = time.time() if now is None else now
        line = _norm(text)
        if not line:
            return False
        q = self._events[who]
        q.append((now, line))
        while q and now - q[0][0] > REPEAT_SEC:
            q.popleft()
        burst = sum(1 for ts, _ in q if now - ts <= BURST_SEC)
        if burst >= BURST_N:
            return True
        if sum(1 for _, body in q if body == line) >= REPEAT_N:
            return True
        times = [ts for ts, _ in q][-RAPID_N:]
        if len(times) >= RAPID_N and all(times[i] - times[i - 1] <= RAPID_GAP for i in range(1, len(times))):
            return True
        return False

    def forget(self, who: str) -> None:
        self._events.pop(who, None)
