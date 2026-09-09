"""First-launch sci-fi hello. RAM only."""

from __future__ import annotations


def _box(name: str) -> list[str]:
    title = f"OPERATOR {name.upper()}  ·  LATTICE LOCK"
    sub = "YOU HAVE CROSSED INTO THE MESH"
    inner = max(len(title), len(sub), 36)
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
    upper = name.upper()
    frames: list[tuple[str, str]] = [
        ("boot", ""),
        ("boot", "              ◈  LANCHAT  ·  CHRONO-MESH NODE  ◈"),
        ("boot", "              ░▒▓█  OPENING PHOTONIC UPLINK  █▓▒░"),
        ("boot", ""),
        ("boot", "  > photonic kernel .................. OK"),
        ("boot", "  > temporal lattice ................. CALIBRATED"),
        ("boot", "  > ghost-protocol handshake ......... LOCKED"),
        ("boot", "  > neural lace / operator hash ...... MATCH"),
        ("boot", f"  > identity vector .................. {upper}"),
        ("boot", "  > mesh horizon ..................... LIVE"),
        ("boot", ""),
    ]
    for line in _box(name):
        frames.append(("hello", line))
    frames.append(("boot", ""))
    frames.append(("boot", f"  {upper}  ·  the lattice sees you now."))
    frames.append(("boot", "  speak to transmit  ·  /quit collapses this node."))
    frames.append(("boot", ""))
    return frames
