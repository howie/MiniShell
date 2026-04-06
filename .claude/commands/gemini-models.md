# Gemini Model 查詢與驗證

查詢 Google Generative AI API 取得**實際可用的模型清單**，與 codebase 設定交叉比對。
避免依賴過時文件導致 404 或 deprecation 問題。

可選參數：`$ARGUMENTS`（`tts` / `live` / `llm` / `imagen` / 留空顯示全部）

## Step 1: 讀取 API Key

從 `backend/.env` 讀取 `GEMINI_API_KEY`。
如果當前目錄是 worktree，改讀 worktree 內的 `backend/.env`。

```bash
# 偵測 .env 位置（worktree 或主 repo）
if [ -f backend/.env ]; then
  ENV_FILE="backend/.env"
elif [ -f /Users/howie/Workspace/github/heyu-ai/yibi-mvp/backend/.env ]; then
  ENV_FILE="/Users/howie/Workspace/github/heyu-ai/yibi-mvp/backend/.env"
fi
grep GEMINI_API_KEY "$ENV_FILE"
```

如果找不到 `GEMINI_API_KEY`，停止並告知使用者需要設定。

## Step 2: 查詢可用模型

呼叫 ListModels API：

```
GET https://generativelanguage.googleapis.com/v1beta/models?key=<API_KEY>&pageSize=1000
```

使用 WebFetch 或 curl 取得 JSON 回應。

從回應的 `models` 陣列中，對每個模型取出：
- `name`（格式 `models/gemini-xxx`）
- `displayName`
- `supportedGenerationMethods`

## Step 3: 模型分類

依據 `supportedGenerationMethods` 和模型名稱分類：

| 類別 | 判斷條件 |
|------|---------|
| **Live API** | methods 包含 `bidiGenerateContent` |
| **TTS** | 名稱包含 `tts` 或 `native-audio` |
| **Imagen** | 名稱包含 `imagen` |
| **LLM** | methods 包含 `generateContent` 且不屬於上述類別 |
| **Embedding** | methods 包含 `embedContent` |

如果 `$ARGUMENTS` 有指定類別（tts/live/llm/imagen），只顯示該類別。
否則顯示所有類別。

按類別用表格呈現，每個模型顯示：
- 模型 ID（去掉 `models/` 前綴）
- supportedGenerationMethods
- 輸入/輸出 token 限制（如果有）

## Step 4: 比對 codebase 設定

在 codebase 中搜尋所有 Gemini 模型引用：

```bash
# 搜尋 backend 中的 gemini 模型名稱
grep -rn 'gemini-[a-zA-Z0-9._-]*' backend/src/ --include="*.py" | grep -v __pycache__ | grep -v '.pyc'
```

重點比對這些檔案中的模型設定：
- `backend/src/infrastructure/config/settings.py` — 模型設定
- `backend/src/infrastructure/providers/ai/gemini_client.py` — Gemini client
- `backend/src/infrastructure/providers/tts/` — TTS provider

## Step 5: 輸出報告

### 格式

```
=== Gemini Model Availability Report ===
查詢時間: <timestamp>

--- Codebase Model Status ---
✅ gemini-2.5-flash-preview-tts    → API 可用
✅ gemini-2.5-pro-preview-tts      → API 可用
❌ gemini-2.0-flash-live-001       → API 不存在（已下架？）
⚠️ gemini-2.5-flash                → 可用，但有更新版 gemini-2.5-flash-002

--- Available Models by Category ---

🗣️ TTS Models:
  gemini-2.5-flash-preview-tts
  gemini-2.5-pro-preview-tts

🎙️ Live API Models (bidiGenerateContent):
  gemini-2.0-flash-live-001
  ...

🤖 LLM Models:
  gemini-2.5-flash
  gemini-2.5-pro
  ...
```

### 狀態判定

- **✅ 可用**：codebase 中的模型名稱出現在 API 回傳清單中
- **❌ 不存在**：codebase 中引用但 API 清單中找不到
- **⚠️ 有更新版**：模型可用但同系列有更新的版本號（例如 `-001` vs `-002`）

如果有 ❌ 的模型，額外建議替代方案（從同類別中挑選最接近的可用模型）。
