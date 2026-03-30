#!/bin/bash
# setup-claw.sh — 建立 OpenClaw sandbox（Phase 4+6）
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

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

# ── 建立 Gemini Provider ──────────────────────────────────────────────────────
echo ""
echo "── Gemini Provider ──────────────────────────────────"
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "gemini-flash"; then
  info "Provider 'gemini-flash' 已存在，略過"
else
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
fi

# ── 建立 Sandbox ──────────────────────────────────────────────────────────────
echo ""
echo "── 建立 claw-agent sandbox ──────────────────────────"
if openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "claw-agent"; then
  info "Sandbox 'claw-agent' 已存在，略過"
else
  step "建立 claw-agent sandbox..."
  openshell sandbox create \
    --name claw-agent \
    --provider github-claw \
    --provider gemini-flash \
    --from openclaw
  info "Sandbox 建立完成"
fi

# ── 設定 OpenClaw Inference ──────────────────────────────────────────────────
echo ""
echo "── 設定 OpenClaw Inference ──────────────────────────"

# 確認 ollama-local provider 是否存在
HAS_OLLAMA=false
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "ollama-local"; then
  HAS_OLLAMA=true
  step "設定 inference routing（ollama-local 為預設）..."
  openshell inference set \
    --sandbox claw-agent \
    --provider ollama-local \
    --model qwen3:8b 2>/dev/null && info "Inference routing 已設定" || \
    warn "Inference routing 設定失敗（可能 openshell 版本不支援 --sandbox flag）"
else
  warn "Provider 'ollama-local' 不存在"
  warn "請先執行 make setup-ollama 以啟用本地推理"
  warn "目前 claw-agent 將使用 Gemini Flash 雲端 API"
fi

echo ""
info "OpenClaw sandbox 建立完成！"
echo ""
echo "  下一步："
echo "  1. openshell sandbox connect claw-agent"
if [ "$HAS_OLLAMA" = true ]; then
  echo "  2. openclaw onboard --auth-choice openai-compatible"
  echo "     Base URL: https://inference.local/v1"
  echo "  3. 驗證推理："
  echo "     curl https://inference.local/v1/models"
  echo ""
  echo "  切換推理後端（在 sandbox 外執行）："
  echo "  本地 Ollama ："
  echo "    openshell inference set --sandbox claw-agent --provider ollama-local --model qwen3:8b"
  echo "  雲端 Gemini ："
  echo "    openshell inference set --sandbox claw-agent --provider gemini-flash --model gemini-3-flash"
else
  echo "  2. openclaw onboard --auth-choice google-api-key"
  echo "     （需要 Google Gemini API key）"
  echo ""
  echo "  若日後啟用本地推理，請先執行 make setup-ollama，再重新執行 make setup-claw"
fi
echo ""
