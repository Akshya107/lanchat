#!/usr/bin/env bash
# Rebuild the single-file app: ephemeral-chat.pyz
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
PY="${ROOT}/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY="python3"
fi
mkdir -p dist/bundle
"$PY" -m pip install -q -r requirements.txt --target dist/bundle
find dist/bundle \( -name '*.so' -o -name '*.dylib' -o -name '*.pyd' \) -delete
rm -rf dist/bundle/bin
rm -rf dist/bundle/ephemeral_chat
cp -R ephemeral_chat dist/bundle/
find dist/bundle -type d -name '__pycache__' -prune -exec rm -rf {} +
"$PY" -m zipapp dist/bundle -m ephemeral_chat.app:main -p "/usr/bin/env python3" -o ephemeral-chat.pyz
chmod +x ephemeral-chat.pyz
echo "Built $(ls -lh ephemeral-chat.pyz | awk '{print $5}') ephemeral-chat.pyz"
