#!/bin/bash
# Auto hot-reload watcher for Flutter web
# Watches lib/ for .dart file changes and refreshes Chrome

cd "$(dirname "$0")/.."

LOG_FILE="${FLUTTER_WEB_LOG:-/tmp/prototype-web.log}"
TARGET_URL="${FLUTTER_WEB_URL:-}"
DEFAULT_HOST="${FLUTTER_WEB_HOST:-127.0.0.1}"
DEFAULT_PORT="${FLUTTER_WEB_PORT:-53000}"

# Try to infer the current served URL from the Flutter run log if not provided.
if [[ -z "$TARGET_URL" && -f "$LOG_FILE" ]]; then
  TARGET_URL=$(perl -ne 'if(/served at (https?:\/\/\S+)/){print $1; exit}' "$LOG_FILE")
fi

# Fallback if nothing was found.
if [[ -z "$TARGET_URL" ]]; then
  TARGET_URL="http://${DEFAULT_HOST}:${DEFAULT_PORT}"
fi

read HOST PORT <<EOF
$(TARGET_URL="$TARGET_URL" DEFAULT_HOST="$DEFAULT_HOST" DEFAULT_PORT="$DEFAULT_PORT" python3 - <<'PY'
import os, urllib.parse
url = os.environ.get("TARGET_URL", "")
fallback_host = os.environ.get("DEFAULT_HOST", "127.0.0.1")
fallback_port = int(os.environ.get("DEFAULT_PORT", "53000"))
try:
    parsed = urllib.parse.urlparse(url)
    host = parsed.hostname or fallback_host
    port = parsed.port or (443 if parsed.scheme == "https" else fallback_port)
    print(f"{host} {port}")
except Exception:
    print(f"{fallback_host} {fallback_port}")
PY
)
EOF

echo "Starting Flutter auto hot-reload watcher..."
echo "Watching lib/ for .dart file changes..."
echo "Will refresh Chrome tab on changes for ${TARGET_URL}"
echo "Press Ctrl+C to stop"
echo ""

fswatch -o -e ".*" -i "\\.dart$" lib/ | while read num; do
  echo "[$(date +%H:%M:%S)] File change detected, refreshing browser..."

  # Refresh Chrome tab matching the inferred host/port
  osascript <<EOF 2>/dev/null
    tell application "Google Chrome"
      set tabList to every tab of every window
      repeat with theTab in tabs of window 1
        if URL of theTab contains "${HOST}:${PORT}" then
          tell theTab to reload
          exit repeat
        end if
      end repeat
    end tell
EOF

  echo "[$(date +%H:%M:%S)] Browser refresh triggered"
done
