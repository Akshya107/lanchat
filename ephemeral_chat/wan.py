"""Internet room relay. Signaling only — messages are not stored by us.

Uses a public MQTT broker so two people on different networks can chat
when both have internet. Phone and computer must use the same broker.
"""

from __future__ import annotations

import base64
import hashlib
import json
import threading
from collections.abc import Callable
from typing import Any

OnPayload = Callable[[dict[str, Any]], None]

# Same order as the phone app. WebSocket first — many networks block :1883.
_BROKERS = (
    ("broker.hivemq.com", 8884, True, True),
    ("broker.hivemq.com", 8000, True, False),
    ("broker.hivemq.com", 1883, False, False),
    ("test.mosquitto.org", 8081, True, True),
    ("test.mosquitto.org", 1883, False, False),
)


def _keystream(key: bytes, n: int) -> bytes:
    out = bytearray()
    block = hashlib.sha256(key).digest()
    while len(out) < n:
        out.extend(block)
        block = hashlib.sha256(key + block).digest()
    return bytes(out[:n])


def _seal(payload: dict, room: str) -> bytes:
    raw = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ks = _keystream(room.encode("utf-8"), len(raw))
    return base64.b64encode(bytes(a ^ b for a, b in zip(raw, ks)))


def _open(blob: bytes, room: str) -> dict | None:
    try:
        data = base64.b64decode(blob)
        ks = _keystream(room.encode("utf-8"), len(data))
        raw = bytes(a ^ b for a, b in zip(data, ks))
        obj = json.loads(raw.decode("utf-8"))
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


class WanRoom:
    def __init__(self, peer_id: str, nick: str, room: str, on_payload: OnPayload) -> None:
        self.peer_id = peer_id
        self.nick = nick
        self.room = self._norm(room)
        self.on_payload = on_payload
        self.connected = False
        self._client: Any = None
        self._loop: Any = None

    @staticmethod
    def _norm(room: str) -> str:
        return "".join(ch for ch in room.upper() if ch.isalnum())[:12]

    @property
    def topic(self) -> str:
        return f"ec/v1/{self.room}/m"

    async def start(self) -> bool:
        import asyncio

        self._loop = asyncio.get_running_loop()
        try:
            import paho.mqtt.client as mqtt
        except ImportError:
            return False
        return await self._loop.run_in_executor(None, self._connect, mqtt)

    def _connect(self, mqtt: Any) -> bool:
        cid = f"ec{self.peer_id[:16]}"
        ready = threading.Event()

        def on_connect(client: Any, _ud: Any, _flags: Any, rc: int, *_args: Any) -> None:
            if rc == 0:
                self.connected = True
                client.subscribe(self.topic, qos=0)
                self.publish({"t": "hello", "id": self.peer_id, "nick": self.nick})
                ready.set()

        for host, port, ws, tls in _BROKERS:
            ready.clear()
            self.connected = False
            try:
                kwargs: dict[str, Any] = {
                    "client_id": cid,
                    "protocol": mqtt.MQTTv311,
                    "clean_session": True,
                }
                if ws:
                    kwargs["transport"] = "websockets"
                try:
                    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION1, **kwargs)
                except Exception:
                    client = mqtt.Client(**kwargs)
                if ws:
                    try:
                        client.ws_set_options(path="/mqtt")
                    except Exception:
                        pass
                if tls:
                    client.tls_set()
                client.on_message = self._on_message
                client.on_connect = on_connect
                client.connect(host, port, keepalive=30)
                client.loop_start()
                if ready.wait(timeout=6):
                    self._client = client
                    return True
                try:
                    client.loop_stop()
                    client.disconnect()
                except Exception:
                    pass
            except Exception:
                continue
        return False

    def _on_message(self, _client: Any, _ud: Any, msg: Any) -> None:
        payload = _open(msg.payload, self.room)
        if not payload:
            return
        if str(payload.get("id") or "") == self.peer_id:
            return
        if self._loop is None:
            return
        self._loop.call_soon_threadsafe(self.on_payload, payload)

    def publish(self, payload: dict) -> None:
        if not self.connected or self._client is None:
            return
        body = payload.copy()
        body.setdefault("id", self.peer_id)
        body.setdefault("nick", self.nick)
        try:
            self._client.publish(self.topic, _seal(body, self.room), qos=0, retain=False)
        except Exception:
            pass

    def set_nick(self, nick: str) -> None:
        self.nick = nick

    def close(self) -> None:
        self.connected = False
        client = self._client
        self._client = None
        if client is None:
            return
        try:
            client.publish(
                self.topic,
                _seal({"t": "bye", "id": self.peer_id, "nick": self.nick}, self.room),
                qos=0,
                retain=False,
            )
        except Exception:
            pass
        try:
            client.loop_stop()
            client.disconnect()
        except Exception:
            pass
