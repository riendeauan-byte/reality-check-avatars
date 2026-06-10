#!/usr/bin/env bash
# Stop + remove the login agent. Leaves the folder and generated audio intact.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.realitycheck.avatars"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "Electron.app/Contents/MacOS/Electron $ROOT/app" 2>/dev/null || true
echo "Reality Check Avatars stopped + autostart removed. (Your audio is left in place.)"
