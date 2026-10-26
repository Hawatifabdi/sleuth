#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
for cmd in bash python3 ip ping curl timeout getent readlink; do
  if ! command -v "$cmd" >/dev/null 2>&1; then printf 'Missing dependency: %s\n' "$cmd" >&2; exit 1; fi
done
if [[ $EUID -eq 0 ]]; then DEST=/usr/local/bin; else DEST="$HOME/.local/bin"; mkdir -p "$DEST"; fi
chmod +x "$HERE/bin/sleuth" "$HERE/libexec/tls_inspector.py"
ln -sfn "$HERE/bin/sleuth" "$DEST/sleuth"
printf 'Installed command link: %s/sleuth\n' "$DEST"
if [[ ":$PATH:" != *":$DEST:"* ]]; then printf 'Add this to your shell profile if needed: export PATH="%s:$PATH"\n' "$DEST"; fi
