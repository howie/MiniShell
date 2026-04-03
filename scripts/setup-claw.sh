#!/bin/bash
# setup-claw.sh — 建立 OpenClaw sandbox（Phase 4+6）
# 預設使用本地 Gemma 4 e4b（透過 Ollama），Gemini Flash 為選配雲端備援
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

LOCAL_MODEL="gemma4:e4b"

# ── 確認前置條件 ──────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

# ── 建立 GitHub Provider（OpenClaw 用）────────────────────────────────────────
echo ""
echo "── GitHub Provider（OpenClaw 用）───────────────────"
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "github-claw"; then
  info "Provider 'github-claw' 已存在，略過"
else
  step "建立 github-claw provider"
  echo "  需要 GitHub Fine-grained PAT（openshell-claw-agent）"
  echo "  權限：Contents read-only、Metadata read-only"
  echo -n "  請輸入 GitHub PAT: "
  read -rs GITHUB_PAT
  echo ""

  if [[ -z "$GITHUB_PAT" ]]; then
    echo "PAT 不能為空" >&2
    exit 1
  fi

  openshell provider create \
    --name github-claw \
    --type github \
    --credential GITHUB_TOKEN="$GITHUB_PAT"
  info "Provider 'github-claw' 建立完成"
fi

# ── Gemini Provider（選配雲端備援）────────────────────────────────────────────
echo ""
echo "── Gemini Provider（選配雲端備援）─────────────────────"
HAS_GEMINI=false
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "gemini-flash"; then
  info "Provider 'gemini-flash' 已存在"
  HAS_GEMINI=true
else
  echo "  Gemini Flash 可作為雲端備援（本地推理不可用時自動切換）"
  echo -n "  是否設定 Gemini Flash 雲端備援？[y/N]: "
  read -r SETUP_GEMINI
  if [[ "${SETUP_GEMINI:-N}" =~ ^[Yy]$ ]]; then
    step "建立 gemini-flash provider"
    echo "  需要 Google AI Studio API Key（AIza...）"
    echo "  取得：https://aistudio.google.com/apikey"
    echo -n "  請輸入 GOOGLE_API_KEY: "
    read -rs GOOGLE_API_KEY
    echo ""

    if [[ -z "$GOOGLE_API_KEY" ]]; then
      echo "API Key 不能為空" >&2
      exit 1
    fi

    openshell provider create \
      --name gemini-flash \
      --type generic \
      --credential GOOGLE_API_KEY="$GOOGLE_API_KEY"
    info "Provider 'gemini-flash' 建立完成"
    HAS_GEMINI=true
  else
    info "略過 Gemini Flash 設定（可日後執行 make setup-claw 補設）"
  fi
fi

# ── 偵測 ollama-local provider ───────────────────────────────────────────────
HAS_OLLAMA=false
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "ollama-local"; then
  HAS_OLLAMA=true
fi

# ── 建立 Sandbox ──────────────────────────────────────────────────────────────
echo ""
echo "── 建立 claw-agent sandbox ──────────────────────────"
if openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "claw-agent"; then
  info "Sandbox 'claw-agent' 已存在，略過"
else
  step "建立 claw-agent sandbox..."

  # 動態組合 provider flags
  PROVIDER_FLAGS="--provider github-claw"
  if [ "$HAS_GEMINI" = true ]; then
    PROVIDER_FLAGS="$PROVIDER_FLAGS --provider gemini-flash"
  fi
  if [ "$HAS_OLLAMA" = true ]; then
    PROVIDER_FLAGS="$PROVIDER_FLAGS --provider ollama-local"
  fi

  openshell sandbox create \
    --name claw-agent \
    $PROVIDER_FLAGS \
    --from openclaw
  info "Sandbox 建立完成"
fi

# ── 設定 OpenClaw Inference ──────────────────────────────────────────────────
echo ""
echo "── 設定 OpenClaw Inference ──────────────────────────"

if [ "$HAS_OLLAMA" = true ]; then
  step "設定 inference routing（ollama-local / ${LOCAL_MODEL}）..."
  openshell inference set \
    --sandbox claw-agent \
    --provider ollama-local \
    --model "${LOCAL_MODEL}" 2>/dev/null && info "Inference routing 已設定" || \
    warn "Inference routing 設定失敗（可能 openshell 版本不支援 --sandbox flag）"
elif [ "$HAS_GEMINI" = true ]; then
  step "設定 inference routing（gemini-flash）..."
  openshell inference set \
    --sandbox claw-agent \
    --provider gemini-flash \
    --model gemini-3-flash 2>/dev/null && info "Inference routing 已設定（Gemini Flash）" || \
    warn "Inference routing 設定失敗"
else
  warn "沒有可用的推理後端"
  warn "請先執行 make setup-ollama 以啟用本地推理"
fi

# ── OpenClaw 自動 Onboarding ─────────────────────────────────────────────────
echo ""
echo "── OpenClaw 自動 Onboarding ─────────────────────────"

if [ "$HAS_OLLAMA" = true ]; then
  step "自動設定 OpenClaw 推理端點（${LOCAL_MODEL}）..."
  # 等待 sandbox 完全就緒
  sleep 2
  openshell sandbox connect claw-agent -- bash -c "
    mkdir -p /home/agent/.openclaw
    cat > /home/agent/.openclaw/inference.json << 'INNEREOF'
{
  \"provider\": \"openai-compatible\",
  \"base_url\": \"https://inference.local/v1\",
  \"api_key\": \"unused\",
  \"model\": \"${LOCAL_MODEL}\"
}
INNEREOF
  " 2>/dev/null && info "OpenClaw onboarding 完成（本地 ${LOCAL_MODEL}）" || \
    warn "自動 onboarding 失敗，請進入 sandbox 後手動執行 openclaw onboard"
elif [ "$HAS_GEMINI" = true ]; then
  step "自動設定 OpenClaw 推理端點（Gemini Flash）..."
  sleep 2
  openshell sandbox connect claw-agent -- bash -c "
    mkdir -p /home/agent/.openclaw
    cat > /home/agent/.openclaw/inference.json << 'INNEREOF'
{
  \"provider\": \"google-ai\",
  \"model\": \"gemini-3-flash\"
}
INNEREOF
  " 2>/dev/null && info "OpenClaw onboarding 完成（Gemini Flash）" || \
    warn "自動 onboarding 失敗，請進入 sandbox 後手動執行 openclaw onboard"
else
  warn "無推理後端，略過自動 onboarding"
fi

# ── OpenClaw Channel 設定（LINE / Telegram / Discord / Slack）────────────────
echo ""
echo "── OpenClaw Channel 設定 ────────────────────────────"
echo "  OpenClaw 支援同時連接多個通訊平台（單一 agent，多 channel）"
echo "  建議：先設定一個 channel 確認穩定後，再逐步新增"
echo ""

# 載入 .env（如果存在）
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
fi

CHANNELS_JSON="{}"
ENABLED_CHANNELS=""

# ── Telegram ──
echo -n "  啟用 Telegram？[y/N]: "
read -r SETUP_TG
if [[ "${SETUP_TG:-N}" =~ ^[Yy]$ ]]; then
  TG_TOKEN="${CLAW_TELEGRAM_TOKEN:-}"
  if [[ -z "$TG_TOKEN" ]]; then
    echo "  從 @BotFather 取得 Bot Token（格式：123456:ABC-DEF...）"
    echo -n "  Telegram Bot Token: "
    read -rs TG_TOKEN
    echo ""
  fi
  if [[ -n "$TG_TOKEN" ]]; then
    CHANNELS_JSON=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['telegram'] = {
  'enabled': True,
  'botToken': '$(echo "$TG_TOKEN" | sed "s/'/\\\\'/g")',
  'dmPolicy': 'pairing'
}
json.dump(c, sys.stdout)
")
    ENABLED_CHANNELS="$ENABLED_CHANNELS Telegram"
    info "Telegram 已設定"
  fi
fi

# ── Discord ──
echo -n "  啟用 Discord？[y/N]: "
read -r SETUP_DC
if [[ "${SETUP_DC:-N}" =~ ^[Yy]$ ]]; then
  DC_TOKEN="${CLAW_DISCORD_TOKEN:-}"
  DC_APP_ID="${CLAW_DISCORD_APP_ID:-}"
  if [[ -z "$DC_TOKEN" ]]; then
    echo "  從 Discord Developer Portal 取得 Bot Token"
    echo -n "  Discord Bot Token: "
    read -rs DC_TOKEN
    echo ""
  fi
  if [[ -z "$DC_APP_ID" ]]; then
    echo -n "  Discord Application ID: "
    read -r DC_APP_ID
  fi
  if [[ -n "$DC_TOKEN" && -n "$DC_APP_ID" ]]; then
    CHANNELS_JSON=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['discord'] = {
  'enabled': True,
  'botToken': '$(echo "$DC_TOKEN" | sed "s/'/\\\\'/g")',
  'applicationId': '$(echo "$DC_APP_ID" | sed "s/'/\\\\'/g")'
}
json.dump(c, sys.stdout)
")
    ENABLED_CHANNELS="$ENABLED_CHANNELS Discord"
    info "Discord 已設定"
  fi
fi

# ── Slack ──
echo -n "  啟用 Slack？[y/N]: "
read -r SETUP_SL
if [[ "${SETUP_SL:-N}" =~ ^[Yy]$ ]]; then
  SL_BOT="${CLAW_SLACK_BOT_TOKEN:-}"
  SL_APP="${CLAW_SLACK_APP_TOKEN:-}"
  if [[ -z "$SL_BOT" ]]; then
    echo "  從 api.slack.com → OAuth & Permissions 取得 Bot Token（xoxb-...）"
    echo -n "  Slack Bot Token: "
    read -rs SL_BOT
    echo ""
  fi
  if [[ -z "$SL_APP" ]]; then
    echo "  從 Socket Mode 取得 App Token（xapp-...）"
    echo -n "  Slack App Token: "
    read -rs SL_APP
    echo ""
  fi
  if [[ -n "$SL_BOT" && -n "$SL_APP" ]]; then
    CHANNELS_JSON=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['slack'] = {
  'enabled': True,
  'botToken': '$(echo "$SL_BOT" | sed "s/'/\\\\'/g")',
  'appToken': '$(echo "$SL_APP" | sed "s/'/\\\\'/g")'
}
json.dump(c, sys.stdout)
")
    ENABLED_CHANNELS="$ENABLED_CHANNELS Slack"
    info "Slack 已設定"
  fi
fi

# ── LINE ──
echo -n "  啟用 LINE？[y/N]: "
read -r SETUP_LINE
if [[ "${SETUP_LINE:-N}" =~ ^[Yy]$ ]]; then
  LINE_TOKEN="${CLAW_LINE_CHANNEL_TOKEN:-}"
  LINE_SECRET="${CLAW_LINE_CHANNEL_SECRET:-}"
  if [[ -z "$LINE_TOKEN" ]]; then
    echo "  從 LINE Developers Console → Messaging API 取得"
    echo -n "  LINE Channel Access Token: "
    read -rs LINE_TOKEN
    echo ""
  fi
  if [[ -z "$LINE_SECRET" ]]; then
    echo -n "  LINE Channel Secret: "
    read -rs LINE_SECRET
    echo ""
  fi
  if [[ -n "$LINE_TOKEN" && -n "$LINE_SECRET" ]]; then
    CHANNELS_JSON=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
c = json.load(sys.stdin)
c['line'] = {
  'enabled': True,
  'channelAccessToken': '$(echo "$LINE_TOKEN" | sed "s/'/\\\\'/g")',
  'channelSecret': '$(echo "$LINE_SECRET" | sed "s/'/\\\\'/g")'
}
json.dump(c, sys.stdout)
")
    ENABLED_CHANNELS="$ENABLED_CHANNELS LINE"
    info "LINE 已設定"
  fi
fi

# ── 寫入 channels 設定到 sandbox ──
if [[ "$CHANNELS_JSON" != "{}" ]]; then
  step "寫入 channel 設定到 sandbox..."

  # 安裝 LINE plugin（如果啟用了 LINE）
  if echo "$CHANNELS_JSON" | python3 -c "import sys,json; sys.exit(0 if 'line' in json.load(sys.stdin) else 1)" 2>/dev/null; then
    step "安裝 OpenClaw LINE plugin..."
    openshell sandbox connect claw-agent -- bash -c \
      "openclaw plugins install @openclaw/line 2>/dev/null" && \
      info "LINE plugin 安裝完成" || \
      warn "LINE plugin 安裝失敗（可稍後手動安裝：openclaw plugins install @openclaw/line）"
  fi

  # 組合完整的 openclaw.json channels 區塊
  FULL_CONFIG=$(python3 -c "
import json
channels = json.loads('$(echo "$CHANNELS_JSON" | sed "s/'/\\\\'/g")')
config = {
  'channels': channels,
  'agents': {
    'defaults': {
      'dmScope': 'per-channel-peer'
    }
  }
}
print(json.dumps(config, indent=2))
")

  openshell sandbox connect claw-agent -- bash -c "
    mkdir -p /home/agent/.openclaw
    cat > /home/agent/.openclaw/channels.json << 'CHANEOF'
${FULL_CONFIG}
CHANEOF
  " 2>/dev/null && info "Channel 設定已寫入 sandbox" || \
    warn "Channel 設定寫入失敗，請手動設定"

  info "已啟用 channel:${ENABLED_CHANNELS}"
else
  info "未啟用任何 channel（可稍後進入 sandbox 執行 openclaw configure --section channels）"
fi

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
info "OpenClaw sandbox 建立完成！"
echo ""
echo "  下一步："
echo "  1. openshell sandbox connect claw-agent"

if [ "$HAS_OLLAMA" = true ]; then
  echo "  2. 推理已自動設定為本地 ${LOCAL_MODEL}，可直接使用"
  echo "  3. 驗證推理："
  echo "     curl https://inference.local/v1/models"
  echo ""
  echo "  切換推理後端（在 sandbox 外執行）："
  echo "  本地 Ollama ："
  echo "    openshell inference set --sandbox claw-agent --provider ollama-local --model ${LOCAL_MODEL}"
  if [ "$HAS_GEMINI" = true ]; then
    echo "  雲端 Gemini ："
    echo "    openshell inference set --sandbox claw-agent --provider gemini-flash --model gemini-3-flash"
  fi
elif [ "$HAS_GEMINI" = true ]; then
  echo "  2. 推理已自動設定為 Gemini Flash"
  echo ""
  echo "  若日後啟用本地推理，請執行 make setup-ollama，再重新執行 make setup-claw"
else
  echo "  2. 請先設定推理後端："
  echo "     make setup-ollama   （本地 Gemma 4 e4b）"
fi

if [[ -n "$ENABLED_CHANNELS" ]]; then
  echo ""
  echo "  已啟用 Channel:${ENABLED_CHANNELS}"
  echo "  管理 channel："
  echo "    openclaw configure --section channels    （在 sandbox 內）"
  echo "  新增/移除 channel："
  echo "    重新執行 make setup-claw"
else
  echo ""
  echo "  新增通訊 channel（LINE/Telegram/Discord/Slack）："
  echo "    重新執行 make setup-claw 或在 sandbox 內執行 openclaw configure --section channels"
fi
echo ""
