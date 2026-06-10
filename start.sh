#!/usr/bin/env bash
# Run Reality Check Avatars in the foreground (for testing). Ctrl-C to stop.
cd "$(dirname "$0")/app"
exec npx electron .
