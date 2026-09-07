#!/usr/bin/env bash
# One-time install. Share ONLY this command — no zip, no folder:
#
#   curl -fsSL https://raw.githubusercontent.com/Akshya107/lanchat/main/get-lanchat.sh | bash
#
# Then open a new terminal and type:  lanchat
set -euo pipefail

# Override with env if you fork.
LANCHAT_GH_OWNER="${LANCHAT_GH_OWNER:-Akshya107}"
LANCHAT_GH_REPO="${LANCHAT_GH_REPO:-lanchat}"
LANCHAT_GH_BRANCH="${LANCHAT_GH_BRANCH:-main}"

DATA="${XDG_DATA_HOME:-$HOME/.local/share}/lanchat"
BIN_DIR="$HOME/.local/bin"

say() { printf '%s\n' "$*"; }
die() { printf 'lanchat install failed: %s\n' "$*" >&2; exit 1; }

find_python() {
  local c
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1; then
      if "$c" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
        command -v "$c"
        return 0
      fi
    fi
  done
  return 1
}

ensure_path_line() {
  local rc="$1"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  mkdir -p "$BIN_DIR"
  if [[ ! -f "$rc" ]] || ! grep -Fq '.local/bin' "$rc" 2>/dev/null; then
    printf '\n# lanchat\n%s\n' "$line" >> "$rc"
    say "Added PATH to $rc"
  fi
}

install_python_mac() {
  if ! command -v brew >/dev/null 2>&1; then
    say "Python is missing. Installing Homebrew first (you may be asked for your password)…"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
    command -v brew >/dev/null 2>&1 || die "Homebrew install did not finish. Open Terminal and run this install command again."
  fi
  say "Installing Python with Homebrew…"
  brew install python
}

install_python_linux() {
  if command -v apt-get >/dev/null 2>&1; then
    say "Installing Python (you may be asked for your password)…"
    sudo apt-get update -y
    sudo apt-get install -y python3 python3-venv python3-pip
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 python3-pip
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm python python-pip
  else
    die "Install Python 3.9+ with your package manager, then run this command again."
  fi
}

ensure_python() {
  local py
  if py="$(find_python)"; then
    say "Using $($py -V 2>&1)"
    echo "$py"
    return
  fi
  case "$(uname -s)" in
    Darwin) install_python_mac ;;
    Linux) install_python_linux ;;
    *) die "Use the Windows command from HOW_TO.md" ;;
  esac
  py="$(find_python)" || die "Python 3.9+ is still missing. Close Terminal, open it again, and re-run the install command."
  say "Using $($py -V 2>&1)"
  echo "$py"
}

local_project() {
  local here
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$here/pyproject.toml" && -d "$here/ephemeral_chat" ]]; then
      echo "$here"
      return 0
    fi
  fi
  return 1
}

fetch_src() {
  local dest="$1"
  mkdir -p "$dest"
  if [[ -n "$LANCHAT_GH_OWNER" ]]; then
    local url="https://raw.githubusercontent.com/${LANCHAT_GH_OWNER}/${LANCHAT_GH_REPO}/${LANCHAT_GH_BRANCH}/install/src.tgz.b64"
    say "Downloading lanchat…"
    curl -fsSL "$url" | python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.read()))' | tar -xz -C "$dest"
    [[ -f "$dest/pyproject.toml" ]] || die "Download did not contain the app. Check the GitHub address."
    return
  fi
  die "This installer is not on GitHub yet, so there is nothing to download. Run it from the lanchat project folder, or set LANCHAT_GH_OWNER."
}

main() {
  say "Installing lanchat…"
  local py src tmp
  py="$(ensure_python)"
  mkdir -p "$DATA" "$BIN_DIR"

  if src="$(local_project)"; then
    say "Installing from this folder"
  else
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    fetch_src "$tmp"
    src="$tmp"
  fi

  say "Setting up a private Python folder (does not touch your other apps)…"
  "$py" -m venv "$DATA/venv"
  "$DATA/venv/bin/python" -m pip install -q --upgrade pip
  "$DATA/venv/bin/python" -m pip install -q "$src"

  ln -sf "$DATA/venv/bin/lanchat" "$BIN_DIR/lanchat"
  ln -sf "$DATA/venv/bin/ephemeral-chat" "$BIN_DIR/ephemeral-chat"

  if command -v brew >/dev/null 2>&1; then
    local brew_bin
    brew_bin="$(brew --prefix 2>/dev/null)/bin"
    if [[ -d "$brew_bin" && -w "$brew_bin" ]]; then
      ln -sf "$DATA/venv/bin/lanchat" "$brew_bin/lanchat"
    fi
  fi

  case "${SHELL:-}" in
    */zsh) ensure_path_line "$HOME/.zshrc"; ensure_path_line "$HOME/.zprofile" ;;
    *) ensure_path_line "$HOME/.bashrc"; ensure_path_line "$HOME/.profile" ;;
  esac

  export PATH="$BIN_DIR:$PATH"
  say ""
  say "Done. Close this window, open a new Terminal, type:"
  say "  lanchat"
  say "and press Enter."
}

main "$@"
