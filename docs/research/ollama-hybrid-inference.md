# Ollama 混合推理架構設計

> 研究日期：2026-03-30
> 目標：讓 claw-agent 同時支援本地 Ollama + 雲端 Gemini Flash，可自動或手動切換

## NemoClaw Inference Router 原理

NemoClaw 的推理路由運作在 OpenShell Gateway（sandbox 外）：

```
OpenClaw Agent (sandbox 內)
  │
  │  推理請求 → https://inference.local
  │
  ▼
OpenShell Proxy Gateway (sandbox 外)
  │
  ├─ Privacy Router ← 檢查 query 內容
  │   ├─ 含 PII/敏感程式碼 → 本地模型
  │   └─ 非敏感 → 雲端模型
  │
  └─ Credential 注入（API Key 不進 sandbox）
```

設計原則：
- Agent 只知道 `inference.local`，不知道真正 endpoint
- API Key 由 Gateway 注入，即使 sandbox 被攻破也不洩漏
- 路由決策在 sandbox 外（out-of-process），Agent 無法繞過

## 關鍵發現：OpenShell 原生支援 Inference Routing

**OpenShell 本身就內建這個機制**，不需要 NemoClaw Blueprint。

```bash
# 建立 Ollama provider（OpenAI-compatible 格式）
openshell provider create \
  --name ollama-local \
  --type openai \
  --credential OPENAI_API_KEY=unused \
  --config OPENAI_BASE_URL=http://host.openshell.internal:11434/v1

# 設定 sandbox 的推理路由
openshell inference set --provider ollama-local --model qwen3:8b

# 熱切換到 Gemini
openshell inference set --provider gemini-flash --model gemini-3-flash
```

## K8s Sidecar vs OpenShell Gateway 對照

```
K8s 版 (NemoClaw Helm):
┌────────────────────────────────┐
│ Pod                            │
│ ┌──────────┐ ┌──────────────┐ │
│ │ OpenClaw │→│ Inference    │ │
│ │ Container│ │ Sidecar      │ │  ← per-pod sidecar
│ └──────────┘ └──────┬───────┘ │
└─────────────────────┼─────────┘
                      ▼
              Ollama / NIM / Cloud

OpenShell 版 (MiniShell):
┌────────────────────────────────┐
│ K3s Cluster (OrbStack VM 內)   │
│ ┌──────────┐ ┌──────────────┐ │
│ │ claw-    │→│ OpenShell    │ │
│ │ agent    │ │ Gateway      │ │  ← 等價於 sidecar
│ │ sandbox  │ │ (proxy+route)│ │
│ └──────────┘ └──────┬───────┘ │
└─────────────────────┼─────────┘
                      ▼
              Ollama (macOS host)
```

差別：K8s sidecar 是 per-pod，OpenShell Gateway 是 per-gateway（管所有 sandbox）。

## 三個實作方案

### 方案 A：OpenShell 原生（推薦）

**難度：⭐ | 工時：2-3 小時 | 零程式碼**

直接用 OpenShell 內建功能，與 NemoClaw 安全模型完全相同：
- API Key 不進 sandbox ✅
- Agent 不知道真正 endpoint ✅
- 路由在 sandbox 外 ✅

唯一缺點：需要手動 `openshell inference set` 切換，沒有自動路由。

### 方案 B：加 Python 輕量 Router（可選）

**難度：⭐⭐ | 工時：1-2 天 | ~150 行 Python**

```python
# minishell-blueprint/router.py
def auto_route():
    """Ollama 可用就用 Ollama，否則 fallback Gemini"""
    if check_ollama():
        set_inference("ollama-local", "qwen3:8b")
    else:
        set_inference("gemini-flash", "gemini-3-flash")

# CLI: python router.py [auto|ollama|gemini|status]
```

功能：Ollama 健康檢查 + 自動 fallback + status 查詢。

### 方案 C：完整 Blueprint 移植

**難度：⭐⭐⭐⭐ | 工時：2-4 週 | 不建議**

NemoClaw Blueprint 約 3000+ 行（OCI 版本化、Privacy Router NLP、state management、rollback）。對個人開發場景沒有必要。

## 需要修改的檔案

| 檔案 | 動作 |
|------|------|
| `scripts/setup-ollama.sh` | **新增** — Host 端裝 Ollama + 建立 OpenShell provider |
| `scripts/setup-claw.sh` | 修改 — 設定 inference routing，OpenClaw 改用 `inference.local` |
| `policies/claw_agent_policy.yaml` | 修改 — ollama_local 加 `host.openshell.internal` + `binaries` 限制 |
| `Makefile` | 修改 — 加 `setup-ollama` target |
| `.env.example` | 修改 — 加 `OLLAMA_HOST=0.0.0.0` 等設定提示 |
| `scripts/verify.sh` | 修改 — 加 Ollama 隔離驗證 |

## 潛在問題

| # | 問題 | 嚴重度 | 說明 |
|---|------|--------|------|
| 1 | **DNS 解析失敗** | ⚠️⚠️⚠️ | 走 `inference.local` 可能繞過此問題（由 Gateway 內部解析），但需驗證 |
| 2 | **Proxy TLS vs plain HTTP** | ⚠️⚠️ | OpenShell inference routing 設計上處理 protocol 轉換，預計可行 |
| 3 | **OpenClaw 是否支援 inference.local** | ⚠️⚠️ | 需 POC 驗證 OpenClaw 能否設定 `inference.local` 作為 base URL |
| 4 | **Gateway-level routing** | ⚠️ | `openshell inference set` 是 gateway-level，切換影響所有 sandbox。需確認是否支援 `--sandbox` flag |
| 5 | **M4 24GB 記憶體** | ⚠️ | 8B 模型 OK；設 `OLLAMA_MAX_LOADED_MODELS=1` |
| 6 | **Ollama 無認證跑在 host** | ⚠️ | 任何連到 `0.0.0.0:11434` 的程式都能存取。`claw_agent_policy` 補 binaries 限制可降低風險 |

### 最重要的 POC 驗證順序

1. 先確認 sandbox 能連到 host Ollama（DNS + 三層 NAT）
2. 確認 OpenShell `openshell inference set` 的 per-sandbox 支援度
3. 確認 OpenClaw 接受 `inference.local` 作為 provider endpoint

## 手動切換指令（方案 A 實作後）

```bash
# 切換到本地 Ollama
openshell inference set --provider ollama-local --model qwen3:8b

# 切換到雲端 Gemini Flash
openshell inference set --provider gemini-flash --model gemini-3-flash

# 查看目前設定
openshell inference get

# 換模型（例如測試 14B）
ollama pull qwen3:14b
openshell inference set --provider ollama-local --model qwen3:14b
```
