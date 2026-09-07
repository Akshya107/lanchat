#!/usr/bin/env bash
# Install ephemeral-chat as a normal command (like a Homebrew formula).
#   ./install.sh
#   ephemeral-chat --name Ada
#
#   ./install.sh --uninstall

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/ephemeral-chat"
UNINSTALL=0

if [[ "${1:-}" == "--uninstall" || "${1:-}" == "uninstall" ]]; then
  UNINSTALL=1
fi

pick_bin_dir() {
  if command -v brew >/dev/null 2>&1; then
    local prefix
    prefix="$(brew --prefix 2>/dev/null || true)"
    if [[ -n "$prefix" && -d "$prefix/bin" && -w "$prefix/bin" ]]; then
      echo "$prefix/bin"
      return
    fi
  fi
  if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
    echo "/usr/local/bin"
    return
  fi
  mkdir -p "$HOME/.local/bin"
  echo "$HOME/.local/bin"
}

find_python() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)'; then
        echo "$candidate"
        return
      fi
    fi
  done
  return 1
}

uninstall() {
  local bin_dir
  bin_dir="$(pick_bin_dir)"
  rm -f "$bin_dir/ephemeral-chat" "$bin_dir/lanchat" "$bin_dir/chat"
  rm -rf "$DATA"
  echo "Removed lanchat."
  echo "The command was: $bin_dir/lanchat"
}

install() {
  local python bin_dir
  if ! python="$(find_python)"; then
    if command -v brew >/dev/null 2>&1; then
      echo "Python 3.9+ not found. Installing with Homebrew…"
      brew install python
      python="$(find_python)" || true
    fi
  fi
  if [[ -z "${python:-}" ]]; then
    echo "Python 3.9+ is required." >&2
    echo "macOS:  brew install python" >&2
    echo "Windows: https://www.python.org/downloads/  (tick “Add python.exe to PATH”)" >&2
    exit 1
  fi

  bin_dir="$(pick_bin_dir)"
  mkdir -p "$DATA" "$bin_dir"
  echo "Using $($python -V 2>&1)"
  echo "Installing into $DATA"
  "$python" -m venv "$DATA/venv"
  "$DATA/venv/bin/python" -m pip install -q --upgrade pip setuptools wheel
  "$DATA/venv/bin/python" -m pip install -q "$ROOT"
  ln -sf "$DATA/venv/bin/lanchat" "$bin_dir/lanchat"
  ln -sf "$DATA/venv/bin/ephemeral-chat" "$bin_dir/ephemeral-chat"
  echo
  echo "Installed. Open a terminal, type lanchat, and press Enter:"
  echo "  lanchat"
  if [[ "$bin_dir" == "$HOME/.local/bin" ]]; then
    case ":$PATH:" in
      *":$bin_dir:"*) ;;
      *)
        echo
        echo "Add this to ~/.zshrc (then run: source ~/.zshrc):"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
    esac
  fi
}

if [[ "$UNINSTALL" -eq 1 ]]; then
  uninstall
else
  install
fi
