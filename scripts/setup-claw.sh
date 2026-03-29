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

if ! openshell status 2>/dev/null | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

# ── 建立 GitHub Provider（OpenClaw 用）────────────────────────────────────────
echo ""
echo "── GitHub Provider（OpenClaw 用）───────────────────"
if openshell provider list 2>/dev/null | grep -q "github-claw"; then
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
if openshell provider list 2>/dev/null | grep -q "gemini-flash"; then
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
if openshell sandbox list 2>/dev/null | grep -q "claw-agent"; then
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

echo ""
info "OpenClaw sandbox 建立完成！"
echo ""
echo "  下一步："
echo "  1. openshell sandbox connect claw-agent"
echo "  2. openclaw onboard --auth-choice google-api-key"
echo "  3. 在 OpenClaw 內用 /model google/gemini-3-flash 確認模型"
