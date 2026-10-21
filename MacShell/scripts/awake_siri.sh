#!/usr/bin/env bash
# Awake Siri Voice Assistant (On-Demand Activation)
# Strictly does NOT keep mic open continuously.
# Only opens mic when called, listens to 1 phrase, responds, and closes mic immediately.

PIDFILE="/tmp/macshell_siri_awake.pid"

# If already listening/active, pressing shortcut again cancels and dismisses
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        rm -f "$PIDFILE"
        qs -c MacShell ipc call siri dismiss 2>/dev/null || true
        exit 0
    fi
fi

# Store current PID
echo "$$" > "$PIDFILE"

# Run Siri on-demand cycle using isolated virtual environment python
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACSHELL_DIR="$(dirname "$SCRIPT_DIR")"
VENV_PYTHON="$MACSHELL_DIR/venv/bin/python"

if [ -x "$VENV_PYTHON" ]; then
    "$VENV_PYTHON" "$SCRIPT_DIR/siri_daemon.py" --awake
else
    python3 "$SCRIPT_DIR/siri_daemon.py" --awake
fi

rm -f "$PIDFILE"
