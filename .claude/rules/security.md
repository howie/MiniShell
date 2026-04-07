# 安全規範（全域）

## Secrets 管理

- **不得**在程式碼或設定檔中硬寫 token、password、API key
- `.env` 檔不得 commit；所有 secret 範本放在 `.env.example`（值留空或用佔位符）
- 腳本中讀取敏感輸入一律用 `read -rs`（silent + raw）

## Credential 隔離

這個專案有兩個獨立 sandbox，credential 必須嚴格隔離：

| Sandbox | Credential |
|---------|-----------|
| `claude-dev` | Claude OAuth token |
| `claw-agent` | Ollama/Gemini API key |

跨 sandbox 注入 credential 是嚴重錯誤，會破壞安全邊界。

## Policy YAML binaries 路徑

Policy YAML 的 `binaries` 欄位不可省略。省略任一條路徑會導致 OpenShell Proxy 回 403。

Claude Code 的四條路徑必須全部列出：
```yaml
binaries:
  - { path: /usr/local/bin/claude }
  - { path: "/sandbox/.local/bin/claude" }
  - { path: "/sandbox/.local/bin/claude-runner" }   # renamed copy，繞過 --trust 注入
  - { path: "/sandbox/.local/share/claude/versions/**" }
```

## 環境變數驗證

Go 和腳本在啟動時必須驗證所有必要的環境變數，缺少時 fail-fast（不要讓程式跑到一半才失敗）。
