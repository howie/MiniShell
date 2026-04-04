#!/bin/bash
# setup-acp-gateway.sh — Install and configure ACP Gateway for OpenClaw → Claude Code
#
# This script:
#   1. Verifies prerequisites (openshell, claude-dev sandbox, SSH connectivity)
#   2. Generates auth token
#   3. Builds the Go binary
#   4. Creates host config
#   5. Injects auth token + MCP config into claw-agent sandbox
#   6. Applies updated network policy
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY_DIR="$REPO_DIR/acp-gateway"
MCP_WRAPPER_DIR="$REPO_DIR/mcp-claude-code"
CONFIG_DIR="$HOME/.config/acp-gateway"
CONFIG_PATH="$CONFIG_DIR/config.json"
ENV_FILE="$CONFIG_DIR/.env"
SSH_HOST="openshell-claude-dev"
CLAW_SSH_HOST="openshell-claw-agent"
GATEWAY_PORT=7865

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  ACP Gateway — OpenClaw → Claude Code 跨 sandbox 橋接"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Phase 1: Prerequisites ───────────────────────────────────────────────────
echo "[1/6] 驗證前置條件..."

if ! command -v openshell &>/dev/null; then
  echo "  ✗ openshell CLI 未安裝 — 請先執行 make install-base"
  exit 1
fi
echo "  ✓ openshell CLI"

if ! command -v go &>/dev/null; then
  echo "  ✗ Go 未安裝"
  exit 1
fi
echo "  ✓ Go $(go version | awk '{print $3}')"

# Verify claude-dev sandbox exists and SSH works.
if ! ssh -o ConnectTimeout=5 "$SSH_HOST" 'echo ok' &>/dev/null; then
  echo "  ✗ 無法 SSH 到 $SSH_HOST — 確認 claude-dev sandbox 已建立且 SSH config 已設定"
  exit 1
fi
echo "  ✓ SSH → $SSH_HOST"

# Verify claw-agent sandbox exists.
if ! ssh -o ConnectTimeout=5 "$CLAW_SSH_HOST" 'echo ok' &>/dev/null; then
  echo "  ✗ 無法 SSH 到 $CLAW_SSH_HOST — 確認 claw-agent sandbox 已建立"
  exit 1
fi
echo "  ✓ SSH → $CLAW_SSH_HOST"

echo ""

# ── Phase 2: Generate auth token ─────────────────────────────────────────────
echo "[2/6] 設定認證..."

mkdir -p "$CONFIG_DIR"

if [[ -f "$ENV_FILE" ]] && grep -q "ACP_GATEWAY_TOKEN=" "$ENV_FILE"; then
  echo "  ✓ Auth token 已存在（$ENV_FILE）"
  # shellcheck source=/dev/null
  source "$ENV_FILE"
else
  ACP_GATEWAY_TOKEN=$(openssl rand -hex 32)
  echo "ACP_GATEWAY_TOKEN=$ACP_GATEWAY_TOKEN" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "  ✓ 已產生新 auth token → $ENV_FILE"
fi

echo ""

# ── Phase 3: Build Go binary ─────────────────────────────────────────────────
echo "[3/6] 編譯 ACP Gateway..."

(cd "$GATEWAY_DIR" && go build -o acp-gateway .)
echo "  ✓ 已編譯 $GATEWAY_DIR/acp-gateway"

echo ""

# ── Phase 4: Create host config ──────────────────────────────────────────────
echo "[4/6] 建立 host 端設定..."

if [[ ! -f "$CONFIG_PATH" ]]; then
  cat > "$CONFIG_PATH" <<CONFIGEOF
{
  "port": $GATEWAY_PORT,
  "executor": {
    "timeout_ms": 300000,
    "claude_binary": "claude"
  },
  "session": {
    "ttl_seconds": 1800,
    "max_sessions": 10,
    "max_history": 20
  },
  "rate_limit": {
    "requests_per_minute": 10,
    "burst_size": 3
  }
}
CONFIGEOF
  echo "  ✓ 已建立 $CONFIG_PATH"
else
  echo "  ✓ Config 已存在（$CONFIG_PATH）"
fi

echo ""

# ── Phase 5: Configure claw-agent MCP integration ────────────────────────────
echo "[5/6] 設定 claw-agent MCP 整合..."

# Inject auth token into claw-agent.
ssh "$CLAW_SSH_HOST" "mkdir -p /home/agent/.openclaw"
echo "$ACP_GATEWAY_TOKEN" | ssh "$CLAW_SSH_HOST" "cat > /home/agent/.openclaw/acp-token && chmod 600 /home/agent/.openclaw/acp-token"
echo "  ✓ Auth token 已注入 claw-agent"

# Upload MCP stdio wrapper as fallback.
ssh "$CLAW_SSH_HOST" "mkdir -p /sandbox/mcp-claude-code"
scp -q "$MCP_WRAPPER_DIR/package.json" "$CLAW_SSH_HOST:/sandbox/mcp-claude-code/"
scp -q "$MCP_WRAPPER_DIR/index.js" "$CLAW_SSH_HOST:/sandbox/mcp-claude-code/"
echo "  ✓ MCP stdio wrapper 已上傳到 claw-agent:/sandbox/mcp-claude-code/"

# Update openclaw.json to register MCP server.
# We use the stdio transport (reliable) as primary, with the gateway URL in env.
OPENCLAW_CONFIG="/home/agent/.openclaw/openclaw.json"

# Read existing config or create new one.
EXISTING_CONFIG=$(ssh "$CLAW_SSH_HOST" "cat $OPENCLAW_CONFIG 2>/dev/null" || echo '{}')

# Check if claude-code MCP is already registered.
if echo "$EXISTING_CONFIG" | grep -q '"claude-code"'; then
  echo "  ✓ claude-code MCP 已在 openclaw.json 中註冊"
else
  # Use node to merge JSON (jq may not be available in sandbox).
  ssh "$CLAW_SSH_HOST" "node -e '
    const fs = require(\"fs\");
    const cfgPath = \"$OPENCLAW_CONFIG\";
    let cfg = {};
    try { cfg = JSON.parse(fs.readFileSync(cfgPath, \"utf8\")); } catch {}
    if (!cfg.mcp) cfg.mcp = {};
    if (!cfg.mcp.servers) cfg.mcp.servers = {};
    cfg.mcp.servers[\"claude-code\"] = {
      command: \"node\",
      args: [\"/sandbox/mcp-claude-code/index.js\"],
      transport: \"stdio\",
      env: {
        ACP_GATEWAY_URL: \"http://host.docker.internal:$GATEWAY_PORT\",
        ACP_GATEWAY_TOKEN: fs.readFileSync(\"/home/agent/.openclaw/acp-token\", \"utf8\").trim()
      }
    };
    fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2) + \"\\n\");
    console.log(\"  ✓ openclaw.json updated with claude-code MCP server\");
  '"
fi

echo ""

# ── Phase 6: Apply updated network policy ────────────────────────────────────
echo "[6/6] 套用更新的網路 policy..."

if command -v openshell &>/dev/null; then
  openshell policy set claw-agent --policy "$REPO_DIR/policies/claw_agent_policy.yaml" --wait
  echo "  ✓ claw-agent policy 已更新（含 acp_gateway 端點）"
else
  echo "  ⚠ openshell 不可用，請手動執行: make apply-policies"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  設定完成！"
echo ""
echo "  啟動 gateway：bash scripts/start-acp-gateway.sh"
echo "  驗證健康：    curl http://localhost:$GATEWAY_PORT/health"
echo ""
echo "  OpenClaw 現在可以透過 claude_code tool 呼叫 Claude Code"
echo "════════════════════════════════════════════════════════════"
echo ""
