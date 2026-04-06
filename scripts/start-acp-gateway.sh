#!/bin/bash
# Start the ACP Gateway on the HOST.
# Claude Code is executed via SSH into the claude-dev sandbox.
#
# Usage:
#   bash scripts/start-acp-gateway.sh [--build]
#
# Options:
#   --build   Rebuild the Go binary before starting.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_DIR="$REPO_DIR/acp-gateway"
BINARY="$GATEWAY_DIR/acp-gateway"
CONFIG_PATH="$HOME/.config/acp-gateway/config.json"
SSH_HOST="openshell-claude-dev"
LOG_DIR="$HOME/.local/log/acp-gateway"
PID_FILE="$HOME/.local/run/acp-gateway.pid"

mkdir -p "$LOG_DIR" "$(dirname "$PID_FILE")"

# ── Build if requested or binary missing ─────────────────────────────────────
if [[ "${1:-}" == "--build" ]] || [[ ! -f "$BINARY" ]]; then
  echo "[acp-gateway] Building Go binary..."
  (cd "$GATEWAY_DIR" && go build -o acp-gateway .)
  echo "[acp-gateway] Build complete."
fi

# ── Verify config exists ────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[acp-gateway] ERROR: Config not found at $CONFIG_PATH"
  echo "[acp-gateway] Run 'make setup-acp-gateway' first."
  exit 1
fi

# ── Read auth token ──────────────────────────────────────────────────────────
if [[ -z "${ACP_GATEWAY_TOKEN:-}" ]]; then
  # Try to read from .env file next to config.
  ENV_FILE="$(dirname "$CONFIG_PATH")/.env"
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
  fi
fi

if [[ -z "${ACP_GATEWAY_TOKEN:-}" ]]; then
  echo "[acp-gateway] ERROR: ACP_GATEWAY_TOKEN is not set."
  echo "[acp-gateway] Set it in the environment or in $(dirname "$CONFIG_PATH")/.env"
  exit 1
fi

# ── Kill existing process if running ─────────────────────────────────────────
if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "[acp-gateway] Stopping existing process (PID $OLD_PID)..."
    kill "$OLD_PID"
    sleep 2
  fi
  rm -f "$PID_FILE"
fi

# ── Start gateway ────────────────────────────────────────────────────────────
LOG_FILE="$LOG_DIR/gateway.log"
echo "[acp-gateway] Starting ACP Gateway... (log: $LOG_FILE)"

ACP_GATEWAY_CONFIG_PATH="$CONFIG_PATH" \
ACP_GATEWAY_TOKEN="$ACP_GATEWAY_TOKEN" \
ACP_GATEWAY_SSH_HOST="$SSH_HOST" \
  "$BINARY" >> "$LOG_FILE" 2>&1 &

GW_PID=$!
echo "$GW_PID" > "$PID_FILE"
echo "[acp-gateway] Started PID $GW_PID"
echo "[acp-gateway] Tail log: tail -f $LOG_FILE"
