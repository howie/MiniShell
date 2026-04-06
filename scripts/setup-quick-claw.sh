#!/bin/bash
# setup-quick-claw.sh — 一鍵建立 OpenClaw + Ollama sandbox（零互動）
# 用法：./setup-quick-claw.sh [model]
# 範例：./setup-quick-claw.sh gemma4:12b
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

MODEL="${1:-gemma4:e2b}"   # T1 快速層預設，可覆蓋：make quick-claw MODEL=gemma4:e4b
SANDBOX_NAME="claw-ollama-gemma4"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo ""
echo "════════════════════════════════════════════════════"
echo "  Quick OpenClaw — 一鍵本地 AI Sandbox"
echo "  Model: ${MODEL}"
echo "  Sandbox: ${SANDBOX_NAME}"
echo "════════════════════════════════════════════════════"
echo ""

# ── 1. 前置檢查 ──────────────────────────────────────────────────────────────
step "檢查前置條件..."

if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base 安裝 OpenShell CLI" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected"; then
  step "Gateway 未連線，嘗試啟動..."
  openshell gateway start 2>/dev/null || true
  # 等待 gateway 就緒
  for i in $(seq 1 30); do
    if openshell status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected"; then
      break
    fi
    sleep 2
  done
  if ! openshell status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Connected"; then
    echo "Gateway 啟動失敗，請手動執行 openshell gateway start" >&2
    exit 1
  fi
fi

info "前置條件確認完成"

# ── 2. Ollama 安裝/啟動/拉模型 ───────────────────────────────────────────────
echo ""
echo "── Ollama ────────────────────────────────────────────"

if command -v ollama &>/dev/null; then
  info "Ollama 已安裝：$(ollama --version 2>/dev/null || echo 'unknown')"
else
  step "安裝 Ollama..."
  brew install ollama
  info "Ollama 安裝完成"
fi

if curl -sf http://localhost:11434/api/tags &>/dev/null; then
  info "Ollama 已在執行"
else
  step "以 OLLAMA_HOST=0.0.0.0 啟動 Ollama..."
  OLLAMA_HOST=0.0.0.0 ollama serve &>/tmp/ollama.log &
  for i in $(seq 1 15); do
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
      info "Ollama 已啟動"
      break
    fi
    sleep 1
  done
  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "Ollama 啟動失敗，請檢查 /tmp/ollama.log" >&2
    exit 1
  fi
fi

if ollama list 2>/dev/null | grep -q "${MODEL}"; then
  info "模型 ${MODEL} 已存在"
else
  step "下載 ${MODEL}（首次下載可能需要幾分鐘）..."
  ollama pull "${MODEL}"
  info "模型 ${MODEL} 下載完成"
fi

# ── 3. 建立 ollama-local Provider ────────────────────────────────────────────
echo ""
echo "── Provider ──────────────────────────────────────────"

if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "ollama-local"; then
  info "Provider 'ollama-local' 已存在，複用"
else
  step "建立 ollama-local provider..."
  openshell provider create \
    --name ollama-local \
    --type openai \
    --credential OPENAI_API_KEY=unused \
    --config OPENAI_BASE_URL=http://host.openshell.internal:11434/v1
  info "Provider 'ollama-local' 建立完成"
fi

# ── 4. 建立 Sandbox ─────────────────────────────────────────────────────────
echo ""
echo "── Sandbox ───────────────────────────────────────────"

if openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "${SANDBOX_NAME}"; then
  info "Sandbox '${SANDBOX_NAME}' 已存在，略過建立"
else
  step "建立 ${SANDBOX_NAME} sandbox..."
  openshell sandbox create \
    --name "${SANDBOX_NAME}" \
    --provider ollama-local \
    --from openclaw
  info "Sandbox 建立完成"
fi

# ── 5. 設定 Inference Routing ────────────────────────────────────────────────
echo ""
echo "── Inference Routing ─────────────────────────────────"

step "設定 inference routing（${MODEL}）..."
openshell inference set \
  --provider ollama-local \
  --model "${MODEL}" 2>/dev/null && info "Inference routing 已設定" || \
  warn "Inference routing 設定失敗（可手動設定）"

# ── 6. OpenClaw Onboarding ──────────────────────────────────────────────────
echo ""
echo "── OpenClaw Onboarding ───────────────────────────────"

step "寫入 OpenClaw 推理端點設定..."
sleep 2
openshell sandbox connect "${SANDBOX_NAME}" -- bash -c "
  mkdir -p /home/agent/.openclaw
  cat > /home/agent/.openclaw/inference.json << 'INNEREOF'
{
  \"provider\": \"openai-compatible\",
  \"base_url\": \"https://inference.local/v1\",
  \"api_key\": \"unused\",
  \"model\": \"${MODEL}\"
}
INNEREOF
" 2>/dev/null && info "OpenClaw onboarding 完成" || \
  warn "自動 onboarding 失敗，請進入 sandbox 後手動執行 openclaw onboard"

# ── 7. 套用 Policy ──────────────────────────────────────────────────────────
echo ""
echo "── Policy ────────────────────────────────────────────"

POLICY_FILE="$PROJECT_ROOT/policies/claw_ollama_gemma4_policy.yaml"
if [ -f "$POLICY_FILE" ]; then
  step "套用 ${SANDBOX_NAME} policy..."
  openshell policy set "${SANDBOX_NAME}" --policy "$POLICY_FILE" --wait
  info "Policy 套用完成"
else
  warn "找不到 ${POLICY_FILE}，請手動套用 policy"
fi

# ── 8. 快速驗證 ─────────────────────────────────────────────────────────────
echo ""
echo "── 驗證 ────────────────────────────────────────────"

step "驗證 sandbox 內推理連線..."
if openshell sandbox connect "${SANDBOX_NAME}" -- bash -c \
  "curl -sf https://inference.local/v1/models" &>/dev/null; then
  info "推理連線驗證成功"
else
  warn "推理連線驗證失敗（sandbox 可能還在啟動中，稍後手動驗證）"
fi

# ── 9. 完成 ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
info "Quick OpenClaw sandbox 建立完成！"
echo "════════════════════════════════════════════════════"
echo ""
echo "  連線進入："
echo "    openshell sandbox connect ${SANDBOX_NAME}"
echo ""
echo "  驗證推理："
echo "    curl https://inference.local/v1/models"
echo ""
echo "  切換模型（在 sandbox 外執行）："
echo "    openshell inference set --provider ollama-local --model <model>"
echo ""
echo "  日後加入通訊 channel："
echo "    進入 sandbox 後執行 openclaw configure --section channels"
echo ""
