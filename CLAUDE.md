# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

openshell-env 是在 Mac Mini M4（Apple Silicon）上建立雙 AI sandbox 基礎設施的安裝配置工具。透過 OpenShell + OrbStack 讓 Claude Code 和 OpenClaw 在完全隔離的環境中並行運行。

## 常用命令

```bash
make help              # 顯示所有 targets
make install           # 完整安裝（互動式，含所有 phase）
make install-base      # Phase 1-3：安裝 Homebrew、OrbStack、OpenShell CLI
make setup-claude      # Phase 4-5：建立 Claude Code sandbox
make setup-claw        # Phase 4+6：建立 OpenClaw sandbox
make apply-policies    # Phase 7：套用網路沙箱政策 YAML
make verify            # Phase 8：驗證檔案系統與 credential 隔離
make status            # 查看 sandbox 目前狀態
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
```

## 架構

### 隔離模型（三層）

1. **檔案系統隔離（Landlock）** — 每個 sandbox 有獨立 `/sandbox` 工作目錄，不互通
2. **Credential 隔離** — Claude OAuth token 和 Google API Key 只注入各自對應的 sandbox
3. **網路隔離（Policy Gateway）** — 所有出站流量走 OpenShell Proxy，依 YAML 白名單決策

### 兩個 Sandbox

| Sandbox | 工具 | LLM | 認證方式 |
|---------|------|-----|---------|
| `claude-dev` | Claude Code | claude-opus/sonnet | OAuth（Pro/Max 訂閱） |
| `claw-agent` | OpenClaw | Gemini 3 Flash | Google API Key |

## Policy YAML 注意事項

Policy 檔位於 `policies/` 目錄，修改後用 `make apply-policies` 套用。

**Schema 正確寫法：**

```yaml
version: 1   # 整數，不是字串

network_policy:
  policies:
    - name: some_service
      enforcement:                 # enforcement 在 policy 層級，不是 endpoint 層級
        - binaries:
            - /path/to/binary      # binaries 必填，不能省略
      endpoints:
        - host: api.example.com
          ports: [443]
          methods: [GET, POST]
```

**Claude Code Binary 路徑（三個都要列）：**
- `/usr/local/bin/claude`
- `/sandbox/.local/bin/claude`
- `/sandbox/.local/share/claude/versions/**`（glob 模式）

省略任一個會導致 proxy 回 403。

**Live sandbox 限制：** 運行中的 sandbox 只能透過熱更新**新增**網路路徑，不能移除已有路徑。需要移除時要重啟 sandbox。

## 腳本規範

所有 Bash 腳本使用 `set -euo pipefail` 嚴格模式，並具備冪等性（重複執行安全）。修改腳本時維持這個慣例。
