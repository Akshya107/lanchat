"""Internet room relay. Signaling is public to the room; chat is AES-GCM.

Uses a public MQTT broker so two people on different networks can chat
when both have internet. Phone and computer must use the same broker.
"""

from __future__ import annotations

import json
import threading
from collections.abc import Callable
from typing import Any

from .crypto import open_chat, seal_chat

OnPayload = Callable[[dict[str, Any], str], None]

# Same order as the phone app. WebSocket first — many networks block :1883.
_BROKERS = (
    ("broker.hivemq.com", 8884, True, True),
    ("broker.hivemq.com", 8000, True, False),
    ("broker.hivemq.com", 1883, False, False),
    ("test.mosquitto.org", 8081, True, True),
    ("test.mosquitto.org", 1883, False, False),
)


class WanRoom:
    def __init__(self, peer_id: str, nick: str, room: str, on_payload: OnPayload) -> None:
        self.peer_id = peer_id
        self.nick = nick
        self.room = self._norm(room)
        self.on_payload = on_payload
        self.connected = False
        self.room_key: bytes | None = None
        self._client: Any = None
        self._loop: Any = None

    @staticmethod
    def _norm(room: str) -> str:
        return "".join(ch for ch in room.upper() if ch.isalnum())[:12]

    @property
    def signal_topic(self) -> str:
        return f"ec/v2/{self.room}/s"

    @property
    def chat_topic(self) -> str:
        return f"ec/v2/{self.room}/m"

    def set_room_key(self, key: bytes | None) -> None:
        self.room_key = key

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
                client.subscribe(self.signal_topic, qos=0)
                client.subscribe(self.chat_topic, qos=0)
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
        topic = str(getattr(msg, "topic", "") or "")
        channel = "chat" if topic.endswith("/m") else "signal"
        payload: dict[str, Any] | None = None
        if channel == "chat":
            if self.room_key is None:
                return
            payload = open_chat(msg.payload, self.room, self.room_key)
        else:
            try:
                obj = json.loads(msg.payload.decode("utf-8"))
                payload = obj if isinstance(obj, dict) else None
            except Exception:
                payload = None
        if not payload:
            return
        if str(payload.get("id") or "") == self.peer_id and payload.get("t") != "claim":
            return
        if self._loop is None:
            return
        self._loop.call_soon_threadsafe(self.on_payload, payload, channel)

    def _publish(self, topic: str, body: bytes, retain: bool = False) -> None:
        if not self.connected or self._client is None:
            return
        try:
            self._client.publish(topic, body, qos=0, retain=retain)
        except Exception:
            pass

    def publish_signal(self, payload: dict) -> None:
        body = payload.copy()
        body.setdefault("id", self.peer_id)
        body.setdefault("nick", self.nick)
        body.setdefault("room", self.room)
        try:
            raw = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        except Exception:
            return
        self._publish(self.signal_topic, raw, retain=body.get("t") == "host")

    def publish_chat(self, payload: dict) -> None:
        if self.room_key is None:
            return
        body = payload.copy()
        body.setdefault("id", self.peer_id)
        body.setdefault("nick", self.nick)
        try:
            blob = seal_chat(body, self.room, self.room_key)
        except Exception:
            return
        self._publish(self.chat_topic, blob.encode("ascii"))

    def set_nick(self, nick: str) -> None:
        self.nick = nick

    def close(self, clear_retain: bool = False) -> None:
        self.connected = False
        client = self._client
        self._client = None
        if client is None:
            return
        try:
            if clear_retain:
                client.publish(self.signal_topic, b"", qos=0, retain=True)
            else:
                raw = json.dumps(
                    {"t": "bye", "id": self.peer_id, "nick": self.nick, "room": self.room},
                    separators=(",", ":"),
                ).encode("utf-8")
                client.publish(self.signal_topic, raw, qos=0, retain=False)
        except Exception:
            pass
        try:
            client.loop_stop()
            client.disconnect()
        except Exception:
            pass
