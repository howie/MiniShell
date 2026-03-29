#!/bin/bash
# setup-bridge.sh — 在 claude-dev sandbox 內安裝並啟動 messaging bridge
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

# ── 前置確認 ───────────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

if ! openshell sandbox list 2>/dev/null | grep -q "claude-dev"; then
  echo "Sandbox 'claude-dev' 不存在，請先執行 scripts/setup-claude.sh" >&2
  exit 1
fi

info "前置確認通過"

# ── Bot Token 申請說明 ─────────────────────────────────────────────────────────
echo ""
echo "── Bot Token 申請說明 ──────────────────────────────────"
echo "Discord（可跳過，按 Enter）："
echo "  1. https://discord.com/developers/applications → New Application"
echo "  2. Bot 頁面 → Reset Token → 複製 token"
echo "  3. Privileged Gateway Intents：開啟 Message Content Intent"
echo "  4. OAuth2 → URL Generator → bot scope → 邀請到伺服器"
echo ""
echo "Telegram（可跳過，按 Enter）："
echo "  1. Telegram 搜尋 @BotFather → /newbot"
echo "  2. 設定名稱和 username"
echo "  3. 複製收到的 token（格式：123456:ABC-DEF...）"
echo ""
echo "Slack（可跳過，按 Enter）："
echo "  1. https://api.slack.com/apps → Create New App → From scratch"
echo "  2. OAuth & Permissions → Bot Token Scopes："
echo "     chat:write, app_mentions:read, channels:history, im:history, im:write"
echo "  3. Socket Mode → Enable → 產生 App-Level Token（connections:write）"
echo "  4. Install to Workspace → 複製 Bot Token（xoxb-...）和 App Token（xapp-...）"
echo "──────────────────────────────────────────────────────────"
echo ""

# ── 互動式詢問 Token ───────────────────────────────────────────────────────────
echo -n "Discord Bot Token（Enter 跳過）: "
read -rs DISCORD_TOKEN; echo ""

echo -n "Telegram Bot Token（Enter 跳過）: "
read -rs TELEGRAM_TOKEN; echo ""

echo -n "Slack Bot Token（xoxb-...，Enter 跳過）: "
read -rs SLACK_BOT_TOKEN; echo ""

echo -n "Slack App Token（xapp-...，Enter 跳過）: "
read -rs SLACK_APP_TOKEN; echo ""

echo ""

# ── 各平台 enabled 狀態 ────────────────────────────────────────────────────────
DISCORD_ENABLED="false"
TELEGRAM_ENABLED="false"
SLACK_ENABLED="false"

[[ -n "$DISCORD_TOKEN"   ]] && DISCORD_ENABLED="true"
[[ -n "$TELEGRAM_TOKEN"  ]] && TELEGRAM_ENABLED="true"
[[ -n "$SLACK_BOT_TOKEN" ]] && [[ -n "$SLACK_APP_TOKEN" ]] && SLACK_ENABLED="true"

# ── 詢問允許的 ID（只問 enabled 的平台）─────────────────────────────────────────
# 輔助函式：將空格分隔字串轉成 JSON 陣列
ids_to_json_array() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo "[]"
    return
  fi
  local result="["
  local first=true
  for id in $input; do
    [[ "$first" == true ]] && first=false || result+=","
    result+="\"$id\""
  done
  result+="]"
  echo "$result"
}

DISCORD_ALLOWED_USERS="[]"
DISCORD_ALLOWED_CHANNELS="[]"
TELEGRAM_ALLOWED_CHATS="[]"
TELEGRAM_ALLOWED_USERS="[]"
SLACK_ALLOWED_USERS="[]"
SLACK_ALLOWED_CHANNELS="[]"

if [[ "$DISCORD_ENABLED" == "true" ]]; then
  echo "── Discord 允許的 ID ────────────────────────────────────"
  echo "  提示：Discord 右鍵帳號 → Copy User ID 取得 User ID"
  echo "  以空格分隔多個 ID，留空=不限制（不建議，僅私人 bot 使用）"
  echo -n "  允許的 User IDs: "
  read -r _discord_users
  echo -n "  允許的 Channel IDs: "
  read -r _discord_channels
  echo ""
  DISCORD_ALLOWED_USERS=$(ids_to_json_array "$_discord_users")
  DISCORD_ALLOWED_CHANNELS=$(ids_to_json_array "$_discord_channels")
fi

if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
  echo "── Telegram 允許的 ID ───────────────────────────────────"
  echo "  提示：@userinfobot 取得 chat id"
  echo "  以空格分隔多個 ID，留空=不限制（不建議，僅私人 bot 使用）"
  echo -n "  允許的 Chat IDs: "
  read -r _telegram_chats
  echo -n "  允許的 User IDs: "
  read -r _telegram_users
  echo ""
  TELEGRAM_ALLOWED_CHATS=$(ids_to_json_array "$_telegram_chats")
  TELEGRAM_ALLOWED_USERS=$(ids_to_json_array "$_telegram_users")
fi

if [[ "$SLACK_ENABLED" == "true" ]]; then
  echo "── Slack 允許的 ID ──────────────────────────────────────"
  echo "  以空格分隔多個 ID，留空=不限制（不建議，僅私人 bot 使用）"
  echo -n "  允許的 User IDs: "
  read -r _slack_users
  echo -n "  允許的 Channel IDs: "
  read -r _slack_channels
  echo ""
  SLACK_ALLOWED_USERS=$(ids_to_json_array "$_slack_users")
  SLACK_ALLOWED_CHANNELS=$(ids_to_json_array "$_slack_channels")
fi

# ── 建立 sandbox 目錄結構 ──────────────────────────────────────────────────────
step "建立 sandbox 目錄結構..."
openshell sandbox connect claude-dev -- bash -c '
  mkdir -p /sandbox/messaging-bridge/src/platforms
  mkdir -p /sandbox/messaging-bridge/src/utils
  mkdir -p /sandbox/messaging-bridge/logs
'
info "目錄結構建立完成"

# ── 傳輸 bridge 原始碼（base64）────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_DIR="$(dirname "$SCRIPT_DIR")/bridge"

transfer_file() {
  local src="$1"
  local dst="$2"
  step "傳輸 $(basename "$src") → $dst"
  local b64
  b64=$(base64 < "$src" | tr -d '\n')
  echo "${b64}" | openshell sandbox connect claude-dev -- bash -c "base64 -d > '${dst}'"
}

step "確認 bridge 原始碼存在..."
REQUIRED_FILES=(
  "$BRIDGE_DIR/package.json"
  "$BRIDGE_DIR/start.sh"
  "$BRIDGE_DIR/src/index.js"
  "$BRIDGE_DIR/src/executor.js"
  "$BRIDGE_DIR/src/platforms/discord.js"
  "$BRIDGE_DIR/src/platforms/telegram.js"
  "$BRIDGE_DIR/src/platforms/slack.js"
  "$BRIDGE_DIR/src/utils/sanitize.js"
  "$BRIDGE_DIR/src/utils/chunker.js"
)
for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "缺少 bridge 原始碼：$f" >&2
    exit 1
  fi
done
info "Bridge 原始碼確認完成"

transfer_file "${BRIDGE_DIR}/package.json"                    "/sandbox/messaging-bridge/package.json"
transfer_file "${BRIDGE_DIR}/start.sh"                        "/sandbox/messaging-bridge/start.sh"
transfer_file "${BRIDGE_DIR}/src/index.js"                    "/sandbox/messaging-bridge/src/index.js"
transfer_file "${BRIDGE_DIR}/src/executor.js"                 "/sandbox/messaging-bridge/src/executor.js"
transfer_file "${BRIDGE_DIR}/src/platforms/discord.js"        "/sandbox/messaging-bridge/src/platforms/discord.js"
transfer_file "${BRIDGE_DIR}/src/platforms/slack.js"          "/sandbox/messaging-bridge/src/platforms/slack.js"
transfer_file "${BRIDGE_DIR}/src/platforms/telegram.js"       "/sandbox/messaging-bridge/src/platforms/telegram.js"
transfer_file "${BRIDGE_DIR}/src/utils/chunker.js"            "/sandbox/messaging-bridge/src/utils/chunker.js"
transfer_file "${BRIDGE_DIR}/src/utils/sanitize.js"           "/sandbox/messaging-bridge/src/utils/sanitize.js"

openshell sandbox connect claude-dev -- bash -c 'chmod +x /sandbox/messaging-bridge/start.sh'
info "原始碼傳輸完成"

# ── 建立 bridge.config.json ────────────────────────────────────────────────────
step "建立 bridge.config.json..."

json_escape() {
  # 轉義 JSON string 特殊字元
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

DISCORD_TOKEN_ESC=$(json_escape "$DISCORD_TOKEN")
TELEGRAM_TOKEN_ESC=$(json_escape "$TELEGRAM_TOKEN")
SLACK_BOT_TOKEN_ESC=$(json_escape "$SLACK_BOT_TOKEN")
SLACK_APP_TOKEN_ESC=$(json_escape "$SLACK_APP_TOKEN")

CONFIG_JSON=$(cat <<CONFIGEOF
{
  "executor": {
    "timeout_ms": 300000,
    "claude_binary": "/sandbox/.local/bin/claude-sandbox"
  },
  "discord": {
    "enabled": ${DISCORD_ENABLED},
    "token": "${DISCORD_TOKEN_ESC}",
    "allowed_channel_ids": ${DISCORD_ALLOWED_CHANNELS},
    "allowed_user_ids": ${DISCORD_ALLOWED_USERS},
    "command_prefix": "!claude "
  },
  "telegram": {
    "enabled": ${TELEGRAM_ENABLED},
    "token": "${TELEGRAM_TOKEN_ESC}",
    "allowed_chat_ids": ${TELEGRAM_ALLOWED_CHATS},
    "allowed_user_ids": ${TELEGRAM_ALLOWED_USERS}
  },
  "slack": {
    "enabled": ${SLACK_ENABLED},
    "bot_token": "${SLACK_BOT_TOKEN_ESC}",
    "app_token": "${SLACK_APP_TOKEN_ESC}",
    "allowed_channel_ids": ${SLACK_ALLOWED_CHANNELS},
    "allowed_user_ids": ${SLACK_ALLOWED_USERS}
  }
}
CONFIGEOF
)

CONFIG_B64=$(echo "$CONFIG_JSON" | base64 | tr -d '\n')
echo "${CONFIG_B64}" | openshell sandbox connect claude-dev -- bash -c "base64 -d > /sandbox/messaging-bridge/bridge.config.json && chmod 600 /sandbox/messaging-bridge/bridge.config.json"
info "bridge.config.json 建立完成（權限 600）"

# ── npm install ────────────────────────────────────────────────────────────────
step "在 sandbox 內執行 npm install..."
openshell sandbox connect claude-dev -- bash -c 'cd /sandbox/messaging-bridge && npm install --save-exact'
info "npm install 完成"

# ── 啟動 bridge ───────────────────────────────────────────────────────────────
step "啟動 messaging bridge..."
openshell sandbox connect claude-dev -- bash -c '
  cd /sandbox/messaging-bridge
  if [ -f bridge.pid ] && kill -0 $(cat bridge.pid) 2>/dev/null; then
    echo "[bridge] 已在運行中（PID $(cat bridge.pid)），跳過啟動"
  else
    bash start.sh
  fi
'
info "Bridge 已啟動！"
echo ""
echo "  管理指令："
echo "  openshell sandbox connect claude-dev -- bash -c 'cat /sandbox/messaging-bridge/logs/bridge.log'"
echo "  openshell sandbox connect claude-dev -- bash -c 'kill \$(cat /sandbox/messaging-bridge/bridge.pid)'"
