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
echo ""
