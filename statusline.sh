#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/statusline.ps1"
SCRIPT_WIN_PATH="$(cygpath -w "$SCRIPT_PATH")"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoLogo -NoProfile -Command "& { \$input | & '$SCRIPT_WIN_PATH' }"
fi

POWERSHELL_EXE="/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [[ -x "$POWERSHELL_EXE" ]]; then
  exec "$POWERSHELL_EXE" -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& { \$input | & '$SCRIPT_WIN_PATH' }"
fi

if command -v powershell >/dev/null 2>&1; then
  exec powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& { \$input | & '$SCRIPT_WIN_PATH' }"
fi

exit 0
