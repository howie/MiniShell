# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

openshell-env 是在 Mac Mini M4（Apple Silicon）上建立雙 AI sandbox 基礎設施的安裝配置工具。透過 OpenShell + OrbStack 讓 Claude Code 和 OpenClaw 在完全隔離的環境中並行運行。

## 常用命令

```bash
make help              # 顯示所有 targets
make install           # 完整安裝（互動式，含所有 phase，含 Ollama + Gemma 4）
make install-base      # Phase 1-3：安裝 Homebrew、OrbStack、OpenShell CLI
make setup-claude      # Phase 4-5：建立 Claude Code sandbox
make quick-claw        # 一鍵啟動 OpenClaw（本地 Ollama gemma4:e2b，不需 API key）
make tier-setup        # 三層推理分層設定（T1 本地/T2 Gemini Flash/T3 Claude Code）
make setup-ollama      # 安裝 Ollama + Gemma 4 e2b 本地推理
make setup-claw        # Phase 4+6：建立 OpenClaw sandbox
make apply-policies    # Phase 7：套用網路沙箱政策 YAML
make verify            # Phase 8：驗證檔案系統與 credential 隔離
make status            # 查看 sandbox 目前狀態
make setup-host        # Phase 0：主機優化（防火牆、TCP Keepalive、Power Nap）
make setup-bridge      # 安裝 Go Messaging Bridge（選配：Discord/Telegram/Slack）
make lint              # 靜態檢查（shellcheck + yamllint）
```

### Sandbox 操作

```bash
openshell sandbox connect claude-dev    # 進入 Claude sandbox
openshell sandbox connect claw-agent    # 進入 OpenClaw sandbox
openshell term                          # TUI dashboard

# 監控 deny log（policy 擋住請求時）
openshell logs claude-dev --since 10m | grep "action=deny"

# Policy 熱更新（不需重啟 sandbox）
openshell policy set claude-dev --policy policies/claude_dev_policy.yaml --wait
openshell policy set claw-agent --policy policies/claw_agent_policy.yaml --wait

# Ansible 操作（在 repo 根目錄執行）
make dashboard         # 啟動 OpenClaw Dashboard（設定 config + gateway + LAN tunnel）
make gw-restart        # 重啟 claw-agent gateway
make sandbox-check     # 健康檢查（所有 sandbox + tunnel）
make notebook-tunnel   # 從筆電建立 SSH tunnel（解決 Secure Context）
```

## 架構

### 隔離模型（三層）

1. **檔案系統隔離（Landlock）** — 每個 sandbox 有獨立 `/sandbox` 工作目錄，不互通
2. **Credential 隔離** — Claude OAuth token 和 Ollama/Gemini credential 只注入各自對應的 sandbox
3. **網路隔離（Policy Gateway）** — 所有出站流量走 OpenShell Proxy，依 YAML 白名單決策

### 三層推理架構（Tiered Inference）

| Tier | Sandbox | 工具 | LLM | 場景 | 延遲 |
|------|---------|------|-----|------|------|
| T3 重度 | `claude-dev` | Claude Code | claude-opus/sonnet | 複雜 coding、架構設計、PR review | 10-60s |
| T2 標準 | `claw-agent` | OpenClaw | Gemini 2.5 Flash（雲端） | tool use、搜尋、摘要、中等 coding | 1-3s |
| T1 快速 | `claw-ollama-gemma4` | OpenClaw | gemma4:e2b（本地） | 閒聊、問候、簡單 Q&A、翻譯 | <1s |

**T3 串聯**：claw-agent 透過 ACP Gateway 以 MCP tool 形式呼叫 claude-dev，T2 處理不了的任務自動升級到 T3。

使用 `make tier-setup` 一次設定三層，或 `make quick-claw` 只建立 T1 本地 sandbox。

### 元件目錄

| 目錄 | 語言 | 用途 |
|------|------|------|
| `scripts/` | Bash | 安裝與設定腳本（Phase 0-8） |
| `bridge-go/` | Go | Messaging Bridge（Discord/Telegram/Slack 轉發） |
| `acp-gateway/` | Go | ACP Gateway HTTP server（讓 OpenClaw 呼叫 Claude Code） |
| `mcp-claude-code/` | Node.js | Stdio MCP Server（ACP Gateway 的 MCP 介面，供 OpenClaw 使用） |
| `ansible/` | YAML | Ansible playbooks（dashboard、gateway 管理、健康檢查） |
| `policies/` | YAML | OpenShell 網路沙箱政策（per-sandbox YAML 白名單） |

### Channel 整合

claw-agent 透過 OpenClaw 內建 channel 支援連接通訊平台（單一 agent，多 channel 架構）：

| Platform | 設定方式 | 備註 |
|----------|---------|------|
| Telegram | `make setup-claw` 互動設定 | @BotFather 建立 bot |
| Discord  | `make setup-claw` 互動設定 | Developer Portal 建立 App |
| Slack    | `make setup-claw` 互動設定 | Socket Mode（需 bot + app token） |
| LINE     | `make setup-claw` 互動設定 | 需安裝 plugin `@openclaw/line` |

Token 可預填在 `.env`（參考 `.env.example`），安裝時自動讀取。
事後管理：`openclaw configure --section channels`（在 sandbox 內執行）。

## 程式碼規範

詳細的語言/工具規範在 `.claude/rules/` 目錄下，依正在編輯的檔案類型自動載入：

| Rule 檔案 | 載入時機 | 涵蓋內容 |
|-----------|---------|---------|
| `security.md` | 永遠 | Secrets 管理、credential 隔離、env var 驗證 |
| `bash-scripts.md` | `scripts/**/*.sh` | `set -euo pipefail`、冪等性、color helpers |
| `go-code.md` | `bridge-go/`、`acp-gateway/` `.go` | slog、graceful shutdown、依賴鎖定 |
| `policy-yaml.md` | `policies/**/*.yaml` | Schema、4 條 Claude binary 路徑、live sandbox 限制 |
| `ansible.md` | `ansible/**/*.yml` | FQCN、繁體中文 task name、`changed_when` |
| `makefile.md` | `Makefile` | `.PHONY`、`chmod +x`、`make lint` |
| `mcp-server.md` | `mcp-claude-code/**/*.js` | ESM、JSON-RPC stdio 職責分離 |
