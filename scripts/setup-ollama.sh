#!/bin/bash
# setup-ollama.sh — 安裝本地 Ollama 並建立 OpenShell inference provider
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

# ── 安裝 Ollama ───────────────────────────────────────────────────────────────
echo ""
echo "── 安裝 Ollama ──────────────────────────────────────"
if command -v ollama &>/dev/null; then
  info "Ollama 已安裝：$(ollama --version 2>/dev/null || echo 'unknown version')"
else
  step "安裝 Ollama..."
  brew install ollama
  info "Ollama 安裝完成"
fi

# ── 設定並啟動 Ollama ─────────────────────────────────────────────────────────
echo ""
echo "── 設定 Ollama 服務 ─────────────────────────────────"

# 確認是否已在執行
if curl -sf http://localhost:11434/api/tags &>/dev/null; then
  info "Ollama 已在執行"
else
  step "以 OLLAMA_HOST=0.0.0.0 啟動 Ollama..."
  warn "Ollama 必須綁定 0.0.0.0 才能從 VM sandbox 存取"
  OLLAMA_HOST=0.0.0.0 ollama serve &>/tmp/ollama.log &
  OLLAMA_PID=$!

  # 等待最多 15 秒
  for i in $(seq 1 15); do
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
      info "Ollama 已啟動（PID: $OLLAMA_PID）"
      break
    fi
    sleep 1
  done

  if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
    echo "Ollama 啟動失敗，請檢查 /tmp/ollama.log" >&2
    exit 1
  fi
fi

# 提示：持久化設定
warn "注意：此啟動方式重開機後不會自動還原"
warn "若需要開機自啟，請執行：brew services start ollama"
warn "開機自啟時請同時設定 launchd 環境變數 OLLAMA_HOST=0.0.0.0"

# ── 拉取預設模型 ──────────────────────────────────────────────────────────────
echo ""
echo "── 下載模型 ─────────────────────────────────────────"
DEFAULT_MODEL="qwen3:8b"

if ollama list 2>/dev/null | grep -q "${DEFAULT_MODEL}"; then
  info "模型 ${DEFAULT_MODEL} 已存在"
else
  step "下載 ${DEFAULT_MODEL}（約 5GB，請稍候）..."
  ollama pull "${DEFAULT_MODEL}"
  info "模型 ${DEFAULT_MODEL} 下載完成"
fi

# ── 建立 OpenShell Ollama Provider ───────────────────────────────────────────
echo ""
echo "── 建立 OpenShell Provider ──────────────────────────"

if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "ollama-local"; then
  info "Provider 'ollama-local' 已存在，略過"
else
  step "建立 ollama-local provider..."
  # 使用 OpenAI-compatible 格式，指向 host.openshell.internal
  # OpenShell Gateway 會將此 hostname 解析到 macOS host
  openshell provider create \
    --name ollama-local \
    --type openai \
    --credential OPENAI_API_KEY=unused \
    --config OPENAI_BASE_URL=http://host.openshell.internal:11434/v1
  info "Provider 'ollama-local' 建立完成"
fi

# ── 設定 claw-agent 的 inference routing ─────────────────────────────────────
echo ""
echo "── 設定 Inference Routing ───────────────────────────"

if openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "claw-agent"; then
  step "設定 claw-agent 使用 ollama-local 作為預設推理後端..."
  openshell inference set \
    --sandbox claw-agent \
    --provider ollama-local \
    --model "${DEFAULT_MODEL}"
  info "Inference routing 設定完成"

  step "確認設定..."
  openshell inference get --sandbox claw-agent 2>/dev/null || \
    openshell inference get 2>/dev/null || true
else
  warn "Sandbox 'claw-agent' 不存在，略過 inference routing 設定"
  warn "請先執行 make setup-claw，再重新執行 make setup-ollama"
fi

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
info "Ollama 本地推理設定完成！"
echo ""
echo "  切換推理後端："
echo "  本地 Ollama ："
echo "    openshell inference set --sandbox claw-agent --provider ollama-local --model qwen3:8b"
echo "  雲端 Gemini  ："
echo "    openshell inference set --sandbox claw-agent --provider gemini-flash --model gemini-3-flash"
echo "  查看目前設定："
echo "    openshell inference get --sandbox claw-agent"
echo ""
echo "  在 sandbox 內驗證連線："
echo "    openshell sandbox connect claw-agent"
echo "    curl https://inference.local/v1/models"
echo ""
