"""Advertise and browse `_ephemeral-chat._tcp` over mDNS / Bonjour."""

from __future__ import annotations

import asyncio
import socket
from typing import Callable

from zeroconf import IPVersion, ServiceInfo, ServiceStateChange
from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf

from .util import instance_name, local_ipv4_all

SERVICE_TYPE = "_ephemeral-chat._tcp.local."

OnUp = Callable[[str, str, str, int], None]
OnDown = Callable[[str], None]


def _txt_properties(info: AsyncServiceInfo) -> dict[str, str]:
    decoded = getattr(info, "decoded_properties", None)
    if decoded is not None:
        return {str(k): ("" if v is None else str(v)) for k, v in dict(decoded).items()}
    props: dict[str, str] = {}
    for key, value in (info.properties or {}).items():
        name = key.decode() if isinstance(key, bytes) else str(key)
        if isinstance(value, bytes):
            props[name] = value.decode("utf-8", "replace")
        elif value is None:
            props[name] = ""
        else:
            props[name] = str(value)
    return props


def _ipv4_addresses(info: AsyncServiceInfo) -> list[str]:
    try:
        found = list(info.parsed_addresses(IPVersion.V4Only))
    except TypeError:
        found = [addr for addr in info.parsed_addresses() if "." in addr]
    return [addr for addr in found if addr]


class Discovery:
    def __init__(
        self,
        peer_id: str,
        nick: str,
        port: int,
        local_ip: str,
        on_up: OnUp,
        on_down: OnDown,
    ) -> None:
        self.peer_id = peer_id
        self.nick = nick
        self.port = port
        self.local_ip = local_ip
        self.on_up = on_up
        self.on_down = on_down
        self._aiozc: AsyncZeroconf | None = None
        self._browser: AsyncServiceBrowser | None = None
        self._info: ServiceInfo | None = None
        self._names: dict[str, str] = {}
        self._loop: asyncio.AbstractEventLoop | None = None
        self._tasks: set[asyncio.Task[None]] = set()

    def _service_info(self) -> ServiceInfo:
        host = instance_name(self.peer_id)
        packed = []
        for ip, _broadcast in local_ipv4_all():
            try:
                packed.append(socket.inet_aton(ip))
            except OSError:
                continue
        if not packed:
            packed = [socket.inet_aton(self.local_ip)]
        return ServiceInfo(
            SERVICE_TYPE,
            f"{host}.{SERVICE_TYPE}",
            addresses=packed,
            port=self.port,
            properties={"id": self.peer_id, "nick": self.nick},
            server=f"{host}.local.",
        )

    async def start(self) -> None:
        self._loop = asyncio.get_running_loop()
        self._aiozc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        self._info = self._service_info()
        await (await self._aiozc.async_register_service(self._info))
        self._browser = AsyncServiceBrowser(
            self._aiozc.zeroconf,
            SERVICE_TYPE,
            handlers=[self._on_state],
        )

    async def set_nick(self, nick: str) -> None:
        self.nick = nick
        if self._aiozc is None:
            return
        self._info = self._service_info()
        await (await self._aiozc.async_update_service(self._info))

    async def stop(self) -> None:
        if self._browser is not None:
            await self._browser.async_cancel()
            self._browser = None
        if self._aiozc is not None and self._info is not None:
            try:
                await (await self._aiozc.async_unregister_service(self._info))
            except Exception:
                pass
        if self._aiozc is not None:
            await self._aiozc.async_close()
            self._aiozc = None
        for task in list(self._tasks):
            task.cancel()
        self._info = None
        self._names.clear()

    def _on_state(self, zeroconf, service_type: str, name: str, state_change: ServiceStateChange) -> None:
        if self._loop is None:
            return
        if state_change is ServiceStateChange.Added:
            coro = self._resolve(zeroconf, service_type, name)
            self._loop.call_soon_threadsafe(self._spawn, coro)
        elif state_change is ServiceStateChange.Removed:
            def _gone(service_name: str = name) -> None:
                peer_id = self._names.pop(service_name, None)
                if peer_id:
                    self.on_down(peer_id)

            self._loop.call_soon_threadsafe(_gone)

    def _spawn(self, coro) -> None:
        if self._aiozc is None:
            coro.close()
            return
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _resolve(self, zeroconf, service_type: str, name: str) -> None:
        try:
            info = AsyncServiceInfo(service_type, name)
            if not await info.async_request(zeroconf, 3000):
                return
            props = _txt_properties(info)
            peer_id = str(props.get("id") or "")
            nick = str(props.get("nick") or "peer")[:24]
            if not peer_id or peer_id == self.peer_id:
                return
            addresses = _ipv4_addresses(info)
            if not addresses or info.port is None:
                return
            self._names[name] = peer_id
            self.on_up(peer_id, nick, addresses[0], int(info.port))
        except Exception:
            return
