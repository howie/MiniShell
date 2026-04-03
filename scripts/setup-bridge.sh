#!/bin/bash
# setup-bridge.sh — 在 claude-dev sandbox 內安裝並啟動 messaging bridge
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
warn "此腳本已棄用，請改用：make setup-bridge（已自動指向 Go 版）"
echo "   或直接執行：scripts/setup-bridge-go.sh"
echo ""
exit 1


YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

SANDBOX_NAME="claude-dev"
SSH_HOST="openshell-${SANDBOX_NAME}"

# 在 sandbox 內執行指令的輔助函式
sandbox_exec() {
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$SSH_HOST" "$@"
}

# ── 前置確認 ───────────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

if ! openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "$SANDBOX_NAME"; then
  echo "Sandbox '${SANDBOX_NAME}' 不存在，請先執行 scripts/setup-claude.sh" >&2
  exit 1
fi

info "前置確認通過"

# ── 安裝 SSH config（若尚未存在）───────────────────────────────────────────────
if ! grep -q "$SSH_HOST" ~/.ssh/config 2>/dev/null; then
  step "安裝 SSH config for ${SANDBOX_NAME}..."
  mkdir -p ~/.ssh
  echo "" >> ~/.ssh/config
  openshell sandbox ssh-config "$SANDBOX_NAME" >> ~/.ssh/config
  info "SSH config 已安裝"
else
  info "SSH config 已存在"
fi

# ── 測試 SSH 連線 ─────────────────────────────────────────────────────────────
step "測試 SSH 連線..."
if ! sandbox_exec "echo ok" &>/dev/null; then
  echo "無法 SSH 連線到 ${SANDBOX_NAME}" >&2
  exit 1
fi
info "SSH 連線正常"

# ── 從 .env 載入 token（若存在）────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

DISCORD_TOKEN=""
TELEGRAM_TOKEN=""
SLACK_BOT_TOKEN=""
SLACK_APP_TOKEN=""
TELEGRAM_ALLOWED_CHAT_IDS_ENV=""
TELEGRAM_ALLOWED_USER_IDS_ENV=""
SLACK_ALLOWED_USER_IDS_ENV=""
SLACK_ALLOWED_CHANNEL_IDS_ENV=""
DISCORD_ALLOWED_USER_IDS_ENV=""
DISCORD_ALLOWED_CHANNEL_IDS_ENV=""

if [ -f "$ENV_FILE" ]; then
  info ".env 檔案找到，從中載入 token..."
  while IFS= read -r line; do
    # 忽略空行和注釋
    [[ -z "$line" || "$line" == \#* ]] && continue
    # 解析 key=value
    key="${line%%=*}"
    value="${line#*=}"
    # 去除前後空白（純 bash，避免 xargs 在空值時觸發 set -e）
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$key" in
      TELEGRAM_TOKEN)               TELEGRAM_TOKEN="$value" ;;
      SLACK_BOT_TOKEN)              SLACK_BOT_TOKEN="$value" ;;
      SLACK_APP_TOKEN)              SLACK_APP_TOKEN="$value" ;;
      DISCORD_TOKEN)                DISCORD_TOKEN="$value" ;;
      TELEGRAM_ALLOWED_CHAT_IDS)    TELEGRAM_ALLOWED_CHAT_IDS_ENV="$value" ;;
      TELEGRAM_ALLOWED_USER_IDS)    TELEGRAM_ALLOWED_USER_IDS_ENV="$value" ;;
      SLACK_ALLOWED_USER_IDS)       SLACK_ALLOWED_USER_IDS_ENV="$value" ;;
      SLACK_ALLOWED_CHANNEL_IDS)    SLACK_ALLOWED_CHANNEL_IDS_ENV="$value" ;;
      DISCORD_ALLOWED_USER_IDS)     DISCORD_ALLOWED_USER_IDS_ENV="$value" ;;
      DISCORD_ALLOWED_CHANNEL_IDS)  DISCORD_ALLOWED_CHANNEL_IDS_ENV="$value" ;;
    esac
  done < "$ENV_FILE"
else
  warn ".env 不存在，將進入互動式輸入（可複製 .env.example 建立）"
fi

# ── 互動式補齊缺少的 Token ────────────────────────────────────────────────────
if [ -z "$DISCORD_TOKEN" ]; then
  echo -n "Discord Bot Token（Enter 跳過）: "
  read -rs DISCORD_TOKEN; echo ""
fi

if [ -z "$TELEGRAM_TOKEN" ]; then
  echo -n "Telegram Bot Token（Enter 跳過）: "
  read -rs TELEGRAM_TOKEN; echo ""
fi

if [ -z "$SLACK_BOT_TOKEN" ]; then
  echo -n "Slack Bot Token（xoxb-...，Enter 跳過）: "
  read -rs SLACK_BOT_TOKEN; echo ""
fi

if [ -z "$SLACK_APP_TOKEN" ]; then
  echo -n "Slack App Token（xapp-...，Enter 跳過）: "
  read -rs SLACK_APP_TOKEN; echo ""
fi

echo ""

# ── 各平台 enabled 狀態 ────────────────────────────────────────────────────────
DISCORD_ENABLED="false"
TELEGRAM_ENABLED="false"
SLACK_ENABLED="false"

[[ -n "$DISCORD_TOKEN"   ]] && DISCORD_ENABLED="true"
[[ -n "$TELEGRAM_TOKEN"  ]] && TELEGRAM_ENABLED="true"
[[ -n "$SLACK_BOT_TOKEN" ]] && [[ -n "$SLACK_APP_TOKEN" ]] && SLACK_ENABLED="true"

if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
  info "Telegram: 啟用"
else
  warn "Telegram: 未啟用（缺少 token）"
fi
if [[ "$SLACK_ENABLED" == "true" ]]; then
  info "Slack: 啟用"
else
  warn "Slack: 未啟用（需要 bot_token + app_token）"
fi
if [[ "$DISCORD_ENABLED" == "true" ]]; then
  info "Discord: 啟用"
else
  info "Discord: 跳過"
fi

# ── 詢問允許的 ID（只問 enabled 且 .env 沒設定的平台）────────────────────────────
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

DISCORD_ALLOWED_USERS=$(ids_to_json_array "${DISCORD_ALLOWED_USER_IDS_ENV:-}")
DISCORD_ALLOWED_CHANNELS=$(ids_to_json_array "${DISCORD_ALLOWED_CHANNEL_IDS_ENV:-}")
TELEGRAM_ALLOWED_CHATS=$(ids_to_json_array "${TELEGRAM_ALLOWED_CHAT_IDS_ENV:-}")
TELEGRAM_ALLOWED_USERS=$(ids_to_json_array "${TELEGRAM_ALLOWED_USER_IDS_ENV:-}")
SLACK_ALLOWED_USERS=$(ids_to_json_array "${SLACK_ALLOWED_USER_IDS_ENV:-}")
SLACK_ALLOWED_CHANNELS=$(ids_to_json_array "${SLACK_ALLOWED_CHANNEL_IDS_ENV:-}")

if [[ "$DISCORD_ENABLED" == "true" && -z "${DISCORD_ALLOWED_USER_IDS_ENV:-}" ]]; then
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

if [[ "$TELEGRAM_ENABLED" == "true" && -z "${TELEGRAM_ALLOWED_CHAT_IDS_ENV:-}" ]]; then
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

if [[ "$SLACK_ENABLED" == "true" && -z "${SLACK_ALLOWED_USER_IDS_ENV:-}" ]]; then
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

# ── 傳輸 bridge 原始碼 ────────────────────────────────────────────────────────
BRIDGE_DIR="$(dirname "$SCRIPT_DIR")/bridge"

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

step "建立 sandbox 目錄結構..."
sandbox_exec "mkdir -p /sandbox/messaging-bridge/src/platforms /sandbox/messaging-bridge/src/utils /sandbox/messaging-bridge/logs"
info "目錄結構建立完成"

step "上傳 bridge 原始碼..."
openshell sandbox upload "$SANDBOX_NAME" "$BRIDGE_DIR/" /sandbox/messaging-bridge
info "原始碼上傳完成"

sandbox_exec "chmod +x /sandbox/messaging-bridge/start.sh"

# ── 注入 Slack WebSocket 主機名稱解析（/etc/hosts）──────────────────────────────
# Sandbox 的 Kubernetes CoreDNS 無法解析外部域名，而 HTTP CONNECT tunnel 會被
# Policy Gateway 在 ~15-20 秒後關閉。這裡從 host 解析 IP 後寫入 sandbox /etc/hosts，
# 讓 WebSocket 可以直連 Slack 而不需要透過 proxy tunnel。
step "注入 Slack WebSocket 主機名稱到 sandbox /etc/hosts..."
SLACK_WSS_HOSTS=("wss-primary.slack.com" "wss-backup.slack.com")
HOSTS_ENTRIES=""
for host in "${SLACK_WSS_HOSTS[@]}"; do
  # 從 host 機器解析 IP（取第一個 A record）
  ip=$(node -e "const dns=require('dns'); dns.resolve4('${host}',(e,a)=>{ if(e){process.stderr.write(e.message+'\n');process.exit(1);} console.log(a[0]); })" 2>/dev/null || true)
  if [[ -n "$ip" ]]; then
    HOSTS_ENTRIES+="${ip}	${host}\n"
    info "  ${host} → ${ip}"
  else
    warn "  無法解析 ${host}，跳過"
  fi
done
if [[ -n "$HOSTS_ENTRIES" ]]; then
  # 移除舊的 Slack WSS 記錄再新增
  sandbox_exec "grep -v 'wss-.*\.slack\.com' /etc/hosts > /tmp/hosts.new && cat /tmp/hosts.new > /etc/hosts || true"
  printf '%b' "$HOSTS_ENTRIES" | sandbox_exec "cat >> /etc/hosts"
  info "/etc/hosts 注入完成"
else
  warn "未注入任何 Slack 主機名稱（DNS 解析全部失敗）"
fi

# ── 建立 bridge.config.json ────────────────────────────────────────────────────
step "建立 bridge.config.json..."

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' || {
    echo "json_escape 失敗 — python3 不可用或執行錯誤" >&2
    exit 1
  }
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

echo "$CONFIG_JSON" | sandbox_exec "cat > /sandbox/messaging-bridge/bridge.config.json && chmod 600 /sandbox/messaging-bridge/bridge.config.json"
info "bridge.config.json 建立完成（權限 600）"

# ── npm install ────────────────────────────────────────────────────────────────
step "在本機安裝 npm 依賴（繞過 sandbox proxy 限制）..."
npm_output="$(cd "$BRIDGE_DIR" && npm install --save-exact --no-progress 2>&1)" || {
  printf '%s\n' "$npm_output" | tail -30
  echo "npm install 失敗，請確認 node/npm 版本與 package.json 內容" >&2
  exit 1
}
printf '%s\n' "$npm_output" | tail -3
info "npm install 完成"

step "打包 node_modules（保留 symlink）..."
NODE_MODULES_TAR="$TMPDIR/bridge-node-modules.tar.gz"
tar -czf "$NODE_MODULES_TAR" -C "$BRIDGE_DIR" -h node_modules
info "打包完成：$NODE_MODULES_TAR"

step "上傳 node_modules 到 sandbox..."
sandbox_exec 'rm -rf /sandbox/messaging-bridge/node_modules'
openshell sandbox upload "$SANDBOX_NAME" "$NODE_MODULES_TAR" /tmp/
sandbox_exec 'cd /sandbox/messaging-bridge && tar -xzf /tmp/bridge-node-modules.tar.gz && rm /tmp/bridge-node-modules.tar.gz'
rm -f "$NODE_MODULES_TAR"
info "node_modules 上傳完成"

# ── 啟動 bridge ───────────────────────────────────────────────────────────────
step "啟動 messaging bridge..."
sandbox_exec 'cd /sandbox/messaging-bridge && if [ -f bridge.pid ] && kill -0 $(cat bridge.pid) 2>/dev/null; then echo "[bridge] 停止舊程序..."; kill $(cat bridge.pid); sleep 1; fi; bash start.sh'

# 確認 bridge process 確實在執行
sleep 2
if ! sandbox_exec 'kill -0 $(cat /sandbox/messaging-bridge/bridge.pid 2>/dev/null) 2>/dev/null'; then
  echo "Bridge 啟動失敗，最後 20 行 log：" >&2
  sandbox_exec 'tail -20 /sandbox/messaging-bridge/logs/bridge.log 2>/dev/null || echo "(log 不存在)"' >&2
  exit 1
fi
info "Bridge 已啟動！"
echo ""
echo "  管理指令："
echo "  ssh ${SSH_HOST} 'cat /sandbox/messaging-bridge/logs/bridge.log'"
echo "  ssh ${SSH_HOST} 'kill \$(cat /sandbox/messaging-bridge/bridge.pid)'"
