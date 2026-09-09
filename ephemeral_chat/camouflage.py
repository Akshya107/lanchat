"""Fake API access-log lines. Real chat is formatted the same, then highlighted."""

from __future__ import annotations

import random
import time
from datetime import datetime, timezone

_METHODS = ("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD")
_LEVELS = ("INFO", "INFO", "INFO", "DEBUG", "DEBUG", "WARN")
_STATUSES = (200, 200, 200, 201, 204, 301, 304, 400, 401, 403, 404, 429, 500, 502)
_PATHS = (
    "/v1/health",
    "/v1/ready",
    "/v1/metrics",
    "/v1/auth/token",
    "/v1/auth/refresh",
    "/v1/users",
    "/v1/users/{id}",
    "/v1/sessions",
    "/v1/events",
    "/v1/events/batch",
    "/v1/ingest",
    "/v1/ingest/bulk",
    "/v1/cache/keys",
    "/v1/cache/flush",
    "/v1/search",
    "/v1/search/suggest",
    "/v1/billing/usage",
    "/v1/webhooks",
    "/v1/webhooks/retry",
    "/v1/files",
    "/internal/queue/pop",
    "/internal/worker/heartbeat",
    "/internal/kv/get",
    "/internal/kv/set",
    "/graphql",
)
_IPS = (
    "10.0.4.18",
    "10.0.4.22",
    "10.1.12.8",
    "10.2.0.44",
    "172.16.3.9",
    "172.16.8.21",
    "192.168.10.14",
    "192.168.10.31",
)


def _stamp() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{int(now.microsecond / 1000):03d}Z"


def _req() -> str:
    return f"req_{random.randrange(16**6):06x}"


def _path() -> str:
    path = random.choice(_PATHS)
    if "{id}" in path:
        path = path.replace("{id}", f"{random.randint(1000, 99999)}")
    if random.random() < 0.25:
        path += f"?limit={random.choice((10, 25, 50, 100))}&cursor={random.randrange(16**4):04x}"
    return path


def fake_line() -> str:
    method = random.choice(_METHODS)
    status = random.choice(_STATUSES)
    if method == "GET" and status in {201, 204}:
        status = 200
    if method in {"POST", "PUT", "PATCH"} and status == 304:
        status = 201
    level = "ERROR" if status >= 500 else ("WARN" if status >= 400 else random.choice(_LEVELS))
    ms = random.choice((1, 2, 3, 5, 8, 11, 14, 19, 27, 41, 63, 88, 120, 240))
    bytes_ = random.choice((0, 128, 256, 512, 1024, 2048, 4096, 8192, 16384))
    return (
        f"{_stamp()}  {level:<5}  {status}  {method:<6}  {_path():<32}  "
        f"{ms:>4}ms  {_req()}  ip={random.choice(_IPS)}  bytes={bytes_}"
    )


def event_line(detail: str) -> str:
    safe = detail.replace('"', "'")[:120]
    return (
        f"{_stamp()}  INFO   204  GET     /internal/worker/heartbeat        "
        f"  4ms  {_req()}  detail=\"{safe}\""
    )


def jitter_delay() -> float:
    # Half the previous cadence (already 3/4 of the original).
    if random.random() < 0.35:
        return random.uniform(0.08, 0.24)
    return random.uniform(0.32, 1.12)


def seed_uptime() -> str:
    started = int(time.time()) - random.randint(4000, 86000)
    return f"boot={started}  region=local  build=2026.4.7"
