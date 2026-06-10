#!/usr/bin/env bash
# Install Reality Check Avatars as a login agent (starts silently at login, restarts if it dies).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/app"
LABEL="com.realitycheck.avatars"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
ELECTRON="$APP/node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"
LOG="$ROOT/agent.log"

if [ ! -x "$ELECTRON" ]; then
  echo "Electron binary not found — fetching it now (one-time ~120MB download)..."
  if [ ! -d "$APP/node_modules/electron" ]; then
    (cd "$APP" && npm install)
  fi
  # npm setups with ignore-scripts=true skip Electron's binary download; run it directly.
  if [ ! -x "$ELECTRON" ] && [ -f "$APP/node_modules/electron/install.js" ]; then
    (cd "$APP" && env -u ELECTRON_SKIP_BINARY_DOWNLOAD node node_modules/electron/install.js)
  fi
  if [ ! -x "$ELECTRON" ]; then
    echo "Could not download Electron. Check your internet connection, then re-run this script." >&2
    exit 1
  fi
fi

# Build the camera/mic detector (optional; needs Xcode Command Line Tools).
# Without it, the "pause during camera or mic use" feature simply stays off.
if command -v swiftc >/dev/null 2>&1; then
  if swiftc -O -o "$APP/sensors/mediastate" "$APP/sensors/mediastate.swift" 2>/dev/null; then
    echo "Built camera/mic detector."
  else
    echo "Note: could not build the camera/mic detector (continuing without it)."
  fi
else
  echo "Note: swiftc not found; camera/mic auto-pause stays off until Xcode Command Line Tools are installed."
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$ELECTRON</string>
    <string>$APP</string>
  </array>
  <key>RunAtLoad</key>        <true/>
  <key>KeepAlive</key>        <true/>
  <key>StandardOutPath</key>  <string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST_EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Installed + started: $LABEL"
echo "First time you open a watched site, macOS will ask to let it control Chrome -> click Allow."
echo "Log: $LOG"
