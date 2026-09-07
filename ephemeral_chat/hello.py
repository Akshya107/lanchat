"""First-launch sci-fi hello. RAM only."""

from __future__ import annotations


def _box(name: str) -> list[str]:
    title = f"HELLO, {name.upper()}"
    sub = "YOU ARE NOW IN THE MACHINE"
    inner = max(len(title), len(sub), 28)
    title = title.center(inner)
    sub = sub.center(inner)
    bar = "═" * (inner + 2)
    return [
        f"  ╔{bar}╗",
        f"  ║ {title} ║",
        f"  ║ {sub} ║",
        f"  ╚{bar}╝",
    ]


def boot_sequence(name: str) -> list[tuple[str, str]]:
    """Return (kind, line) frames for the opening sequence."""
    frames: list[tuple[str, str]] = [
        ("boot", ""),
        ("boot", "          ░▒▓█  OPENING NEURAL UPLINK  █▓▒░"),
        ("boot", "          ░▒▓█     ACCESSING THE GRID     █▓▒░"),
        ("boot", ""),
        ("boot", "  > bios checksum ................ OK"),
        ("boot", "  > quantum bus sync ............. OK"),
        ("boot", "  > ghost protocol ............... ARMED"),
        ("boot", "  > retina / voice hash .......... MATCH"),
        ("boot", f"  > operator lock ................ {name.upper()}"),
        ("boot", "  > uplink ....................... LIVE"),
        ("boot", ""),
    ]
    for line in _box(name):
        frames.append(("hello", line))
    frames.append(("boot", ""))
    frames.append(("boot", f"  welcome back, {name}. the grid is listening."))
    frames.append(("boot", "  type to transmit.  /quit severs the link."))
    frames.append(("boot", ""))
    return frames
