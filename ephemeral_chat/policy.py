"""First-launch rules. Shown once per machine, then remembered locally."""

from __future__ import annotations

import sys

from .operator import default_key_path

POLICY_VERSION = "1"

SCREEN = """
  ┌─────────────────────────────────────────────────────────┐
  │  ◈  LANCHAT  ·  DIRECTIVE 01  ·  CIVILIAN USE ONLY      │
  └─────────────────────────────────────────────────────────┘

  This node is for private, lawful chat between people you
  choose. Words live in RAM and vanish when you quit.

  YOU are responsible for what you transmit, and for any
  offence committed with this software.

  The maker of LANCHAT is NOT responsible for misuse, harm,
  or illegal activity by any operator.

  Do not use this for crimes or anything the law forbids.
  Private chat. Not a weapon. Not a hiding place for crime.

  Type ACCEPT to enter the lattice. Anything else exits.
"""


def _path():
    return default_key_path().parent / "policy.accepted"


def already_accepted() -> bool:
    try:
        return _path().read_text().strip() == POLICY_VERSION
    except OSError:
        return False


def mark_accepted() -> None:
    path = _path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(POLICY_VERSION + "\n")
        path.chmod(0o600)
    except OSError:
        pass


def require_accept() -> None:
    if already_accepted():
        return
    text = SCREEN.strip("\n")
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print(text)
        print("\n  (non-interactive) set policy.accepted or run in a terminal.")
        sys.exit(1)
    print("\033[32m" + text + "\033[0m")
    try:
        answer = input("\n  ▸ ").strip().upper()
    except (EOFError, KeyboardInterrupt):
        print("\nlink refused.")
        sys.exit(0)
    if answer != "ACCEPT":
        print("link refused.")
        sys.exit(0)
    mark_accepted()
