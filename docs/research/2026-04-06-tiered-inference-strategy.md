# 多模型分層推理策略

> 研究日期：2026-04-06
> 目標：解決 Mac Mini M4 (32GB RAM) 上 OpenClaw 單模型瓶頸，建立三層推理架構

## 背景：從前一版演進

2026-03-30 的 [ollama-hybrid-inference.md](./ollama-hybrid-inference.md) 完成了方案 A（OpenShell 原生推理路由），讓 claw-agent 可手動切換 Ollama / Gemini Flash。

實際使用後發現的問題：

1. **`gemma4:e4b` (4B) 太慢**：回應時間 3-8 秒，日常對話體驗差
2. **26B 模型塞不進記憶體**：32GB 扣除 OS (~6GB) + OrbStack VM (~3GB) = 實際可用 ~23GB，26B 模型需要 ~16GB，但加上 OS 其他佔用已太緊繃
3. **單一模型無法兼顧速度與能力**：小模型快但弱，大模型強但慢

## 硬體限制分析

### Mac Mini M4 32GB 模型載入能力

| 模型 | 大小（約） | 可用？ | 說明 |
|------|-----------|--------|------|
| gemma4:e2b (~2B) | ~1.5 GB | ✅ 可用 | 非常快，閒聊夠用 |
| gemma4:e4b (~4B) | ~3.5 GB | ✅ 可用 | 現狀，太慢 |
| gemma4:12b | ~8 GB | ✅ 可用 | 勉強 fit，品質不錯 |
| gemma4:27b | ~17 GB | ❌ 太大 | 加上 OS+VM 記憶體不夠 |
| qwen3:8b | ~5 GB | ✅ 可用 | 備選，tool use 不錯 |

實測（待補）：
- `gemma4:e2b` 回應時間：TBD
- `gemma4:12b` 回應時間：TBD

### OLLAMA_MAX_LOADED_MODELS 分析

| 設定 | 場景 | 說明 |
|------|------|------|
| 1（原設定） | 同時只跑一個模型 | 切換時需重新載入 |
| 2 | e2b + e4b 同時在記憶體 | ~5GB，32GB 完全可行 |

## 三層模型架構

### 決策邏輯

```
任務到來
  │
  ├── 短訊息 / 閒聊 / 問候 / 簡單翻譯
  │   → T1：gemma4:e2b（本地，<1s）
  │
  ├── Tool use / 搜尋 / 摘要 / 內容生成 / 中等 coding
  │   → T2：Gemini 2.5 Flash（雲端，1-3s）
  │
  └── 複雜 coding / debug / 架構設計 / PR review
      → T3：Claude Opus/Sonnet via ACP Gateway（10-60s）
```

### 為何 T2 選 Gemini Flash 而非本地 12B？

| 考量 | 本地 gemma4:12b | Gemini 2.5 Flash |
|------|----------------|-----------------|
| 速度 | ~2-5s（M4 本地推理） | ~1-3s（網路） |
| 品質 | 中等 | 優（尤其 tool use） |
| 記憶體佔用 | ~8GB | 0 |
| Tool use 能力 | 普通 | 強 |
| API key 需求 | 無 | 需 Google API Key |
| 成本 | 電費 | 免費額度（2025.4 起 Flash 有免費 tier） |

結論：Gemini Flash 在品質和速度上均優於本地 12B，且不佔記憶體。本地 12B 作為 Gemini 不可用時的 fallback 或離線模式備選。

### 為何 T3 選 Claude Code via ACP Gateway？

- ACP Gateway 已在 `setup-acp-gateway.sh` 建立好，零額外開發
- `claw-agent` 可透過 MCP tool `claude_code` 直接呼叫 claude-dev sandbox
- Claude Opus/Sonnet 處理複雜 coding/推理任務是現行最佳選擇
- 使用者已有 Claude Pro/Max 訂閱

## 實作架構

### 雙 Sandbox 靜態分配（選定方案）

```
┌─────────────────────────────────┐   ┌──────────────────────────────┐
│ claw-agent（主力 T2）           │   │ claw-ollama-gemma4（快速 T1） │
│ 預設：Gemini 2.5 Flash          │   │ 預設：gemma4:e2b              │
│ MCP：claude-code（T3 升級）     │   │ 純本地、零 API key            │
│ 連接：Telegram/Discord/Slack    │   │ 可連接獨立 bot channel        │
└────────────┬────────────────────┘   └──────────────┬───────────────┘
             │                                        │
             ▼                                        ▼
     Google AI API                            Ollama（host macOS）
     Gemini 2.5 Flash                         gemma4:e2b
             │
             │（T3 複雜任務）
             ▼
     ACP Gateway → claude-dev → Claude Code
```

### 為何不用 Per-Request 自動路由？

`openshell inference set` 是 gateway-level 操作，一個 gateway 底下所有 sandbox 共享同一個 routing 設定（`--sandbox` flag 在現行版本已移除）。因此：

- **不能**在同一個 sandbox 內 per-request 切換模型
- **可以**用多個 sandbox，各自有不同的 inference.json 設定
- 未來可考慮 host-side proxy router（見下方路線圖）

### 為何不在 Sandbox 內直接呼叫 Gemini API？

OpenShell 的安全模型要求 API Key 不進 sandbox（credential isolation）：
- API Key 由 OpenShell Gateway 在 sandbox 外注入
- Sandbox 只看到 `inference.local` 這個虛擬 endpoint
- 即使 sandbox 被攻破，攻擊者也拿不到 Google API Key

方案 B（sandbox 內直接呼叫 Gemini）會破壞這個安全模型，不採用。

## 修改摘要

| 檔案 | 改動 |
|------|------|
| `scripts/setup-ollama.sh` | `DEFAULT_MODEL` 改為 `gemma4:e2b` |
| `scripts/setup-claw.sh` | 推理優先順序改為 Gemini Flash > Ollama fallback |
| `scripts/setup-quick-claw.sh` | 預設 MODEL 改為 `gemma4:e2b` |
| `Makefile` | 新增 `tier-setup` target |
| `.env.example` | `OLLAMA_MAX_LOADED_MODELS` 建議改為 2，更新說明 |
| `CLAUDE.md` | 更新 sandbox 表格和架構說明 |

## 未來路線圖

### Host-Side Inference Router（未實作）

```
OpenClaw (sandbox 內)
  │ 送出 OpenAI-compatible 請求，model 欄位指定 "gemma4:e2b" 或 "gemini-flash"
  ▼
OpenShell Gateway → Inference Router（host 上的 Go HTTP proxy）
  │
  ├── model = "gemma4:*" → Ollama (port 11434)
  └── model = "gemini-*" → Gemini API (generativelanguage.googleapis.com)
```

實作難度：~200 行 Go，放在 `inference-router/` 目錄，類似 `acp-gateway/`。
這樣可以讓單一 sandbox 做 per-request 模型選擇，無需維護兩個 sandbox。

### gemma4:12b 本地備援（未實作）

若 Gemini API 不可用（斷網、超過 quota），可手動切換到本地 12B：

```bash
ollama pull gemma4:12b
openshell inference set --provider ollama-local --model gemma4:12b
```

需更新 `claw_agent_policy.yaml` 確保 Ollama 連線正常。

## 已知陷阱

### `openshell inference set --sandbox` 不存在

`openshell inference set` **不支援 `--sandbox` flag**（在 commit `7a5d979` 移除），這是 gateway-level 操作，影響所有 sandbox。

舊寫法（會報錯）：
```bash
openshell inference set --sandbox claw-agent --provider ollama-local --model gemma4:e2b
# error: unexpected argument '--sandbox' found
```

正確寫法：
```bash
openshell inference set --provider ollama-local --model gemma4:e2b
```

這個限制意味著無法用單一指令只切換特定 sandbox 的推理後端，需要透過 sandbox 內的 `inference.json` 來覆寫（`setup-claw.sh` 中的 onboarding 已處理）。

## 待驗證項目

- [ ] `gemma4:e2b` 實際回應時間（M4 本地）
- [ ] Gemini 2.5 Flash 在 OpenShell inference routing 下的延遲
- [ ] `OLLAMA_MAX_LOADED_MODELS=2` 在 32GB 系統上的穩定性
- [ ] claw-agent（T2）觸發 ACP Gateway 呼叫 Claude Code 的完整流程
