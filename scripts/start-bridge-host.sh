#!/bin/bash
# Start the messaging bridge (Go version) on the HOST.
# Claude is executed via SSH into the claude-dev sandbox.
#
# Usage:
#   bash scripts/start-bridge-host.sh [--sync-config] [--build]
#
# Options:
#   --sync-config  Fetch latest bridge.config.json from sandbox before starting.
#   --build        Rebuild the Go binary before starting.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRIDGE_GO_DIR="$REPO_DIR/bridge-go"
BINARY="$BRIDGE_GO_DIR/bridge-go"
HOST_CONFIG_PATH="$HOME/.config/messaging-bridge/bridge.config.json"
SSH_HOST="openshell-claude-dev"
LOG_DIR="$HOME/.local/log/messaging-bridge"
PID_FILE="$HOME/.local/run/messaging-bridge-host.pid"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"

# ── Build if requested or binary missing ─────────────────────────────────────
if [[ "${1:-}" == "--build" ]] || [[ "${2:-}" == "--build" ]] || [[ ! -f "$BINARY" ]]; then
  echo "[host-bridge] Building Go bridge..."
  (cd "$BRIDGE_GO_DIR" && go build -o bridge-go .)
  echo "[host-bridge] Build complete."
fi

# ── Sync config from sandbox if requested or if config doesn't exist ──────────
if [[ "${1:-}" == "--sync-config" ]] || [[ "${2:-}" == "--sync-config" ]] || [[ ! -f "$HOST_CONFIG_PATH" ]]; then
  echo "[host-bridge] Syncing config from sandbox..."
  mkdir -p "$(dirname "$HOST_CONFIG_PATH")"
  ssh "$SSH_HOST" 'cat /sandbox/messaging-bridge/bridge.config.json' > "$HOST_CONFIG_PATH"
  echo "[host-bridge] Config saved to $HOST_CONFIG_PATH"
fi

# ── Kill existing host bridge if running ─────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[host-bridge] Stopping existing process (PID $OLD_PID)..."
    kill "$OLD_PID"
    sleep 2
  fi
  rm -f "$PID_FILE"
fi

# ── Start bridge ──────────────────────────────────────────────────────────────
LOG_FILE="$LOG_DIR/bridge-host.log"
echo "[host-bridge] Starting Go bridge... (log: $LOG_FILE)"

BRIDGE_CONFIG_PATH="$HOST_CONFIG_PATH" \
BRIDGE_SSH_HOST="$SSH_HOST" \
  "$BINARY" >> "$LOG_FILE" 2>&1 &

BRIDGE_PID=$!
echo "$BRIDGE_PID" > "$PID_FILE"
echo "[host-bridge] Started PID $BRIDGE_PID"
echo "[host-bridge] Tail log: tail -f $LOG_FILE"
