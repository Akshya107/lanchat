"""Full-screen log tail: fake API lines, real chat highlighted."""

from __future__ import annotations

import textwrap
from collections.abc import Callable
from time import time

from datetime import datetime

from prompt_toolkit.application import Application
from prompt_toolkit.application.current import get_app
from prompt_toolkit.buffer import Buffer
from prompt_toolkit.formatted_text import StyleAndTextTuples
from prompt_toolkit.key_binding import KeyBindings
from prompt_toolkit.layout import HSplit, Layout, Window
from prompt_toolkit.layout.controls import BufferControl, FormattedTextControl
from prompt_toolkit.layout.processors import BeforeInput
from prompt_toolkit.styles import Style

from .camouflage import event_line
from .store import MemoryStore, Message

STYLE = Style.from_dict(
    {
        "root": "bg:#000000 #007700",
        "log": "bg:#000000 #007700",
        "log.warn": "bg:#000000 #556600",
        "sys": "bg:#000000 #006600",
        "hit": "bg:#00ff00 #000000 bold",
        "boot": "bg:#000000 bold #00ff66",
        "hello": "bg:#00ff00 #000000 bold",
        "status": "bg:#001a00 #00aa00",
        "typing": "bg:#000000 italic #66ff66",
        "sep": "bg:#000000 #003300",
        "prompt": "bg:#000000 bold #00ff00",
        "input": "bg:#000000 #00ff00",
    }
)


class ChatUI:
    def __init__(
        self,
        store: MemoryStore,
        status: Callable[[], str],
        on_submit: Callable[[str], None],
        on_clear: Callable[[], None],
        on_quit: Callable[[], None],
        on_typing: Callable[[bool], None] | None = None,
    ) -> None:
        self.store = store
        self._status = status
        self.on_submit = on_submit
        self.on_clear = on_clear
        self.on_quit = on_quit
        self.on_typing = on_typing
        self.typists: dict[str, float] = {}
        self.shielded = False
        self.buffer = Buffer(multiline=False, complete_while_typing=False)
        self.buffer.on_text_changed += self._buffer_changed
        self._app: Application[None] | None = None
        self._app = self._build()

    def _build(self) -> Application[None]:
        kb = KeyBindings()

        @kb.add("enter")
        def _enter(_event) -> None:
            text = self.buffer.text
            self.buffer.reset()
            if self.on_typing:
                self.on_typing(False)
            self.on_submit(text)

        @kb.add("c-c")
        @kb.add("c-d")
        def _quit(_event) -> None:
            self.on_quit()

        @kb.add("c-l")
        def _clear(_event) -> None:
            self.on_clear()

        body = HSplit(
            [
                Window(
                    FormattedTextControl(self._history_fragments, focusable=False),
                    wrap_lines=False,
                    always_hide_cursor=True,
                    style="class:root",
                ),
                Window(height=1, char="─", style="class:sep"),
                Window(
                    FormattedTextControl(self._status_fragments, focusable=False),
                    height=1,
                    style="class:status",
                    always_hide_cursor=True,
                ),
                Window(
                    FormattedTextControl(self._typing_fragments, focusable=False),
                    height=1,
                    style="class:typing",
                    always_hide_cursor=True,
                ),
                Window(
                    BufferControl(
                        buffer=self.buffer,
                        input_processors=[BeforeInput("$ ", style="class:prompt")],
                    ),
                    height=1,
                    dont_extend_height=True,
                    style="class:input",
                ),
            ],
            style="class:root",
        )
        return Application(
            layout=Layout(body),
            key_bindings=kb,
            style=STYLE,
            full_screen=True,
            mouse_support=False,
            include_default_pygments_style=False,
            erase_when_done=True,
        )

    async def run(self) -> None:
        assert self._app is not None
        await self._app.run_async()

    def set_shield(self, on: bool) -> None:
        self.shielded = on
        self.invalidate()

    def invalidate(self) -> None:
        if self._app is not None:
            self._app.invalidate()

    def exit(self) -> None:
        if self._app is not None:
            self._app.exit()

    def _status_fragments(self) -> StyleAndTextTuples:
        if self.shielded:
            return [("class:root", " ")]
        return [("class:status", f" {self._status()} ")]

    def _typing_fragments(self) -> StyleAndTextTuples:
        if self.shielded:
            return [("class:root", " ")]
        now = time()
        names = [name for name, seen in self.typists.items() if now - seen < 2.4]
        if not names:
            return [("class:typing", " ")]
        if len(names) == 1:
            text = f" {names[0]} is typing..."
        else:
            text = f" {', '.join(names)} are typing..."
        return [("class:typing", text)]

    def set_typing(self, nick: str, active: bool) -> None:
        if not nick:
            return
        if active:
            self.typists[nick] = time()
        else:
            self.typists.pop(nick, None)
        self.invalidate()

    def _buffer_changed(self, _buffer: Buffer) -> None:
        if not self.on_typing:
            return
        text = self.buffer.text
        self.on_typing(bool(text.strip()) and not text.lstrip().startswith("/"))

    def _history_fragments(self) -> StyleAndTextTuples:
        try:
            size = get_app().output.get_size()
            rows = max(1, size.rows - 4)
            cols = max(20, size.columns)
        except Exception:
            rows, cols = 20, 80
        if self.shielded:
            blank = " " * cols
            return [("class:root", ("\n".join([blank] * rows)))]

        rendered: list[StyleAndTextTuples] = []
        for msg in self.store.messages:
            rendered.extend(self._message_lines(msg, cols))

        visible = rendered[-rows:]
        out: StyleAndTextTuples = []
        for i, line in enumerate(visible):
            if i:
                out.append(("class:root", "\n"))
            out.extend(line)
        return out

    def _message_lines(self, msg: Message, cols: int) -> list[StyleAndTextTuples]:
        if msg.kind in {"chat", "own"}:
            stamp = datetime.fromtimestamp(msg.ts).strftime("%H:%M:%S")
            line = f"{stamp}  {msg.nick:<12}  {msg.text}"
            style = "class:hit"
        elif msg.kind == "hello":
            line = msg.text
            style = "class:hello"
        elif msg.kind == "boot":
            line = msg.text or " "
            style = "class:boot"
        elif msg.kind == "sys":
            line = event_line(msg.text)
            style = "class:sys"
        else:
            line = msg.text
            style = "class:log.warn" if " WARN " in line or " ERROR " in line else "class:log"
        return self._wrap_line([(style, line)], cols)

    def _wrap_line(self, fragments: StyleAndTextTuples, cols: int) -> list[StyleAndTextTuples]:
        text = "".join(piece for _, piece in fragments)
        style = fragments[0][0] if fragments else "class:log"
        if len(text) <= cols:
            return [fragments]
        wrapped = textwrap.wrap(text, width=max(8, cols), subsequent_indent="  ")
        if not wrapped:
            return [fragments]
        return [[(style, chunk)] for chunk in wrapped]
