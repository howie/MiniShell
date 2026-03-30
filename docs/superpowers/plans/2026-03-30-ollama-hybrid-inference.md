# Ollama Hybrid Inference Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 claw-agent sandbox 內的 OpenClaw 能透過 OpenShell 原生 inference routing，在本地 Ollama 與雲端 Gemini Flash 之間手動切換，且 API Key 不進 sandbox。

**Architecture:** OpenShell Gateway 原生支援 `inference.local` 作為受管推理端點——sandbox 內程式碼呼叫 `https://inference.local`，Gateway 攔截後剝掉 sandbox credential、注入 host 端設定的 provider credential，再轉發到 Ollama 或 Gemini。這與 NemoClaw Blueprint 的安全模型相同，但不需要額外程式碼。

**Tech Stack:** Bash (`set -euo pipefail`)、OpenShell CLI (`openshell provider`, `openshell inference`)、Ollama、OpenClaw、YAML

---

## File Map

| 檔案 | 動作 |
|------|------|
| `scripts/setup-ollama.sh` | **新增** — Host 端安裝 Ollama、綁定 0.0.0.0、拉模型、建立 OpenShell provider |
| `scripts/setup-claw.sh` | **修改** — 加入 inference routing 設定與 OpenClaw 改用 `inference.local` |
| `policies/claw_agent_policy.yaml` | **修改** — `ollama_local` 加 `host.openshell.internal` + `binaries` 限制 |
| `Makefile` | **修改** — 加 `setup-ollama` target 與 help 說明 |
| `.env.example` | **修改** — 加 Ollama 相關設定提示 |
| `scripts/verify.sh` | **修改** — 加 Ollama 連線驗證與隔離測試 |

---

## Task 1：更新 Policy YAML

**Files:**
- Modify: `policies/claw_agent_policy.yaml`

- [ ] **Step 1: 替換 `ollama_local` block**

開啟 `policies/claw_agent_policy.yaml`，將目前的 `ollama_local` 區塊（L26-29）：

```yaml
  ollama_local:
    name: ollama_local
    endpoints:
      - { host: host.docker.internal, port: 11434 }
```

替換為：

```yaml
  ollama_local:
    name: ollama_local
    endpoints:
      - { host: host.docker.internal, port: 11434 }
      - { host: host.openshell.internal, port: 11434 }
    binaries:
      - { path: /usr/bin/node }
      - { path: /usr/bin/curl }
```

- [ ] **Step 2: 驗證 YAML 語法**

```bash
python3 -c "import yaml; yaml.safe_load(open('policies/claw_agent_policy.yaml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add policies/claw_agent_policy.yaml
git commit -m "feat(policy): add host.openshell.internal and binaries to ollama_local"
```

---

## Task 2：新增 `scripts/setup-ollama.sh`

**Files:**
- Create: `scripts/setup-ollama.sh`

- [ ] **Step 1: 建立腳本**

新增 `scripts/setup-ollama.sh`，完整內容：

```bash
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

if ollama list 2>/dev/null | grep -q "^${DEFAULT_MODEL}"; then
  info "模型 ${DEFAULT_MODEL} 已存在"
else
  step "下載 ${DEFAULT_MODEL}（約 5GB，請稍候）..."
  ollama pull "${DEFAULT_MODEL}"
  info "模型 ${DEFAULT_MODEL} 下載完成"
fi

# ── 建立 OpenShell Ollama Provider ───────────────────────────────────────────
echo ""
echo "── 建立 OpenShell Provider ──────────────────────────"

if openshell provider list 2>/dev/null | grep -q "ollama-local"; then
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

if openshell sandbox list 2>/dev/null | grep -q "claw-agent"; then
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
```

- [ ] **Step 2: 賦予執行權限**

```bash
chmod +x scripts/setup-ollama.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-ollama.sh
git commit -m "feat: add setup-ollama.sh for local inference with OpenShell routing"
```

---

## Task 3：修改 `scripts/setup-claw.sh`

**Files:**
- Modify: `scripts/setup-claw.sh`

- [ ] **Step 1: 在最後的 info/echo 區塊前加入 OpenClaw inference 配置步驟**

找到 `setup-claw.sh` 結尾的這段（最後 ~8 行）：

```bash
echo ""
info "OpenClaw sandbox 建立完成！"
echo ""
echo "  下一步："
echo "  1. openshell sandbox connect claw-agent"
echo "  2. openclaw onboard --auth-choice google-api-key"
echo "  3. 在 OpenClaw 內用 /model google/gemini-3-flash 確認模型"
```

替換為：

```bash
# ── 設定 OpenClaw 使用 inference.local ───────────────────────────────────────
echo ""
echo "── 設定 OpenClaw Inference ──────────────────────────"

# 確認 ollama-local provider 是否存在
if openshell provider list 2>/dev/null | grep -q "ollama-local"; then
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
echo ""
```

- [ ] **Step 2: 確認腳本語法正確**

```bash
bash -n scripts/setup-claw.sh && echo "語法 OK"
```

Expected: `語法 OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-claw.sh
git commit -m "feat(setup-claw): add inference routing setup and update next-steps instructions"
```

---

## Task 4：修改 `Makefile`

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: 加入 `setup-ollama` target**

找到 Makefile 中 `setup-bridge` target：

```makefile
# Messaging Bridge（選配）
setup-bridge:
	@chmod +x $(SCRIPTS)/setup-bridge.sh
	@$(SCRIPTS)/setup-bridge.sh
```

在它之前插入：

```makefile
# 本地推理（選配）
setup-ollama:
	@chmod +x $(SCRIPTS)/setup-ollama.sh
	@$(SCRIPTS)/setup-ollama.sh

```

- [ ] **Step 2: 更新 `.PHONY`**

找到：

```makefile
.PHONY: help install install-base setup-claude setup-claw apply-policies verify setup-bridge status
```

替換為：

```makefile
.PHONY: help install install-base setup-claude setup-claw apply-policies verify setup-ollama setup-bridge status
```

- [ ] **Step 3: 更新 `help` target**

在 help echo 區塊的 `setup-bridge` 說明行之前插入：

```makefile
	@echo "  make setup-ollama     安裝本地 Ollama 並設定 inference routing（選配）"
```

- [ ] **Step 4: 驗證 Makefile 語法**

```bash
make help
```

Expected: 輸出包含 `setup-ollama` 那一行。

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat(makefile): add setup-ollama target for local inference"
```

---

## Task 5：修改 `.env.example`

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: 在檔案開頭加入 Ollama 設定區塊**

在 `.env.example` 第一行之前插入：

```bash
# Ollama 本地推理（選配）
# 必須設為 0.0.0.0 才能讓 VM sandbox 存取 host 上的 Ollama
# 預設值 127.0.0.1 只允許本機存取，sandbox 無法連到
OLLAMA_HOST=0.0.0.0
# 限制同時載入的模型數量（24GB RAM 建議設 1）
OLLAMA_MAX_LOADED_MODELS=1

```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: add Ollama environment variables to .env.example"
```

---

## Task 6：修改 `scripts/verify.sh`

**Files:**
- Modify: `scripts/verify.sh`

- [ ] **Step 1: 在 `── Gateway 狀態 ──` 區塊之前加入 Ollama 驗證**

找到這段（verify.sh L91-98）：

```bash
# ── Gateway 狀態 ──────────────────────────────────────────────────────────────
echo ""
echo "── Gateway 狀態 ─────────────────────────────────────"
if openshell status 2>/dev/null | grep -q "Connected"; then
  pass "Gateway 在線"
else
  fail "Gateway 未連線"
fi
```

在它之前插入：

```bash
# ── Ollama 推理驗證 ───────────────────────────────────────────────────────────
echo ""
echo "── Ollama 推理驗證 ──────────────────────────────────"

# 確認 Host 端 Ollama 在執行
if curl -sf http://localhost:11434/api/tags &>/dev/null; then
  pass "Host 端 Ollama 在線（localhost:11434）"
  OLLAMA_RUNNING=1
else
  warn "Host 端 Ollama 未在執行，略過 sandbox 連線測試"
  OLLAMA_RUNNING=0
fi

if [[ $OLLAMA_RUNNING -eq 1 && $HAS_CLAW -eq 1 ]]; then
  # claw-agent 應能連到 Ollama（透過 inference.local 或直連）
  CLAW_INFERENCE=$(openshell sandbox connect claw-agent -- \
    bash -c "curl -sf https://inference.local/v1/models 2>/dev/null && echo ok || echo blocked" \
    2>/dev/null || echo "error")

  if [[ "$CLAW_INFERENCE" == "ok" ]]; then
    pass "claw-agent 能透過 inference.local 連到推理後端"
  else
    warn "claw-agent 無法連到 inference.local（可能尚未設定 inference routing）"
    warn "請執行 make setup-ollama 後再驗證"
  fi

  # claude-dev 不應能透過 inference.local 連到 Ollama
  if [[ $HAS_CLAUDE -eq 1 ]]; then
    CLAUDE_OLLAMA=$(openshell sandbox connect claude-dev -- \
      bash -c "curl -sf http://host.openshell.internal:11434/api/tags 2>/dev/null && echo ok || echo blocked" \
      2>/dev/null || echo "error")

    if [[ "$CLAUDE_OLLAMA" == "blocked" || "$CLAUDE_OLLAMA" == "error" ]]; then
      pass "claude-dev 無法直連 Ollama（policy 有效）"
    else
      warn "claude-dev 可以直連 Ollama host（policy 可能需要加強）"
    fi
  fi
fi

```

- [ ] **Step 2: 確認腳本語法正確**

```bash
bash -n scripts/verify.sh && echo "語法 OK"
```

Expected: `語法 OK`

- [ ] **Step 3: Commit**

```bash
git add scripts/verify.sh
git commit -m "feat(verify): add Ollama inference routing verification tests"
```

---

## Task 7：端對端驗證

這個 task 是手動驗證，確認整體設定正確。

- [ ] **Step 1: 套用更新後的 policy**

```bash
make apply-policies
```

Expected: `[✓] Policy 套用完成` 或類似成功訊息。

- [ ] **Step 2: 確認 Ollama 在線**

```bash
curl http://localhost:11434/api/tags | python3 -m json.tool
```

Expected: 回傳包含 `qwen3:8b` 的 JSON 模型列表。

如果 Ollama 未啟動：

```bash
OLLAMA_HOST=0.0.0.0 OLLAMA_MAX_LOADED_MODELS=1 ollama serve &
```

- [ ] **Step 3: 建立 ollama-local provider（如果尚未存在）**

```bash
make setup-ollama
```

- [ ] **Step 4: 在 sandbox 內驗證 inference.local 連線**

```bash
openshell sandbox connect claw-agent
# 以下在 sandbox 內執行：
curl https://inference.local/v1/models
```

Expected: 回傳 Ollama 模型列表（`{"object":"list","data":[{"id":"qwen3:8b",...}]}`）

如果失敗，代表 `openshell inference set` 尚未生效，確認：

```bash
# 在 sandbox 外執行
openshell inference get --sandbox claw-agent
```

- [ ] **Step 5: 測試 OpenClaw 推理**

```bash
openshell sandbox connect claw-agent
openclaw chat
# 輸入：Hello, which model are you?
```

Expected: 回覆來自 qwen3:8b（Ollama 本地模型）。

- [ ] **Step 6: 測試手動切換到 Gemini**

```bash
# 在 sandbox 外執行
openshell inference set --sandbox claw-agent --provider gemini-flash --model gemini-3-flash

# 進入 sandbox 驗證
openshell sandbox connect claw-agent
curl https://inference.local/v1/models
```

Expected: 回傳 Gemini 模型。

- [ ] **Step 7: 執行完整驗證腳本**

```bash
make verify
```

Expected: 所有項目 PASS（或 SKIP），無 FAIL。

- [ ] **Step 8: 切回 Ollama（預設）**

```bash
openshell inference set --sandbox claw-agent --provider ollama-local --model qwen3:8b
```

---

## 已知風險備忘

| 風險 | 症狀 | 處理方式 |
|------|------|----------|
| `openshell inference set` 不支援 `--sandbox` flag | 命令報錯 | 改用 `openshell inference set --provider ... --model ...`（影響所有 sandbox） |
| `inference.local` 無法解析 | `curl: (6) Could not resolve host` | 確認 inference routing 已設定：`openshell inference get` |
| Ollama 無法從 sandbox 連到 | `curl: (7) Failed to connect` | 確認 Ollama 綁定 `0.0.0.0`，非 `127.0.0.1` |
| OpenClaw 不接受 `inference.local` | onboard 失敗 | 改在 openclaw.json 直接設定 `baseUrl: https://inference.local/v1` |
