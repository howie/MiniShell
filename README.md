# openshell-env

在 Mac Mini M4 上建立 OpenShell 雙 AI Sandbox 環境：
**Claude Code（Anthropic OAuth）** + **OpenClaw（Google Gemini Flash）**

---

## 架構概覽

```
Mac Mini M4（Apple Silicon）
└── OrbStack → Docker → OpenShell Gateway
    ├── Sandbox A: claude-dev  ← Claude Code（Pro/Max OAuth）
    └── Sandbox B: claw-agent  ← OpenClaw（Gemini 3 Flash API）
```

兩個 sandbox 完全隔離：獨立檔案系統、獨立 credential、各自的網路 Policy。

---

## 快速開始

```bash
# 完整安裝（互動式，會詢問 token）
make install

# 或逐步安裝
make install-base     # 安裝 Homebrew、工具、OrbStack、OpenShell
make setup-claude     # 建立 Claude Code sandbox
make setup-claw       # 建立 OpenClaw sandbox
make apply-policies   # 套用網路沙箱政策
make verify           # 驗證隔離是否正常
```

**前置需求（安裝前先準備）：**
1. [Google AI Studio API Key](https://aistudio.google.com/apikey)（給 OpenClaw 用）
2. 兩把 [GitHub Fine-grained PAT](https://github.com/settings/personal-access-tokens/new)（各別給 Claude / OpenClaw 用）
3. Anthropic Pro 或 Max 訂閱（給 Claude Code OAuth 用）

---

## Make Targets

| 指令 | 說明 |
|------|------|
| `make install` | 完整安裝（base → claude → claw → policies → verify） |
| `make install-base` | 安裝基礎環境（Homebrew、OrbStack、OpenShell） |
| `make setup-claude` | 建立 Claude Code sandbox |
| `make setup-claw` | 建立 OpenClaw sandbox |
| `make apply-policies` | 套用 `policies/` 目錄的 Policy YAML |
| `make verify` | 驗證沙箱隔離 |
| `make status` | 查看目前 sandbox / provider 狀態 |

---

## 目錄結構

```
openshell-env/
├── Makefile                    # 安裝入口
├── policies/                   # 沙箱網路政策
│   ├── claude_dev_policy.yaml  # Claude Code sandbox policy
│   └── claw_agent_policy.yaml  # OpenClaw sandbox policy
├── scripts/                    # 自動化腳本
│   ├── install-base.sh
│   ├── setup-claude.sh
│   ├── setup-claw.sh
│   ├── apply-policies.sh
│   └── verify.sh
└── docs/                       # 文件
    ├── installation.md         # 完整安裝手冊（手動版）
    ├── usage.md                # 日常使用指南
    └── learning.md             # 學習資源、架構說明、Policy YAML 詳解
```

---

## 文件索引

- [安裝手冊](docs/installation.md) — 手動安裝步驟參考、疑難排解
- [日常使用](docs/usage.md) — 常用指令、Token 輪替（每 30 天）
- [學習資源](docs/learning.md) — 架構說明、Policy YAML 欄位詳解、學習路徑

---

## 每月成本

| 項目 | 費用 |
|------|------|
| OrbStack + OpenShell + OpenClaw | $0 |
| Claude Code | $0 額外（Pro/Max 涵蓋） |
| Gemini Flash | $0 ~ $5 |
| **合計** | **$0 ~ $5** |
