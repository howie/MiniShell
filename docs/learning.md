# 學習資源

## 這個專案在做什麼

這個專案在 **Mac Mini M4** 上建立一個雙 AI sandbox 開發環境：

- **Sandbox A**：Claude Code（Anthropic）— 用 OAuth 認證，走 Pro/Max 訂閱
- **Sandbox B**：OpenClaw — 用 Google Gemini Flash API

兩個 sandbox 完全隔離，各自有獨立的檔案系統、credential 和網路政策。

---

## 核心元件說明

### OpenShell

一個沙箱化 AI coding agent 的執行平台。

- 提供 `openshell` CLI 管理 sandbox 的生命週期
- 底層用 **OrbStack（Apple Virtualization Framework）+ Docker + K3s** 執行 sandbox
- 內建 **Proxy Gateway**，所有 sandbox 的出站網路流量都走這個 proxy
- Policy YAML 控制每個 sandbox 允許存取哪些 host、哪些程式可以存取
- K3s 不需要手動安裝，OpenShell 自動管理

### Claude Code

Anthropic 的 CLI coding agent。

- 認證方式：OAuth `/login`（不需要 API Key，走 Pro/Max 訂閱額度）
- 支援 MCP（Model Context Protocol）連接外部工具
- Sandbox 內的 binary 路徑：`/sandbox/.local/bin/claude`（symlink）→ 實際路徑 `/sandbox/.local/share/claude/versions/<版本號>`

### OpenClaw

一個可切換多模型的 AI coding agent。

- 本專案配置使用 **Google Gemini 3 Flash** 模型
- 認證：Google AI Studio API Key（`GOOGLE_API_KEY`）
- 設定檔：`~/.openclaw/openclaw.json`

### OrbStack

一個輕量的 Docker / VM 執行環境，專為 Apple Silicon 優化。

- 比 Docker Desktop 更輕量、更快
- 使用 Apple Virtualization Framework（非 QEMU）
- OpenShell 需要 OrbStack 提供 Docker 環境

---

## 架構圖

```
Mac Mini M4（macOS，Apple Silicon）
│
├── openshell CLI（主機側）
│   └── 管理 gateway、sandbox、provider、policy
│
└── OrbStack（輕量 Linux VM）
    └── Docker Engine（OrbStack 內建）
        └── OpenShell Gateway Container（K3s，自動建立）
            │
            ├── Proxy Gateway（所有出站流量都走這裡）
            │   └── Policy Engine（根據 YAML 決定允許/拒絕）
            │
            ├── Sandbox A: claude-dev
            │   ├── 認證：OAuth（Pro/Max 訂閱）
            │   ├── Provider：github-claude（read/write PAT）
            │   ├── Filesystem：/sandbox（獨立）
            │   └── Network：依 claude_dev_policy.yaml
            │
            └── Sandbox B: claw-agent
                ├── 認證：GOOGLE_API_KEY（Gemini Flash）
                ├── Provider：github-claw（read-only PAT）+ gemini-flash
                ├── Filesystem：/sandbox（獨立，與 A 隔離）
                └── Network：依 claw_agent_policy.yaml
```

---

## Policy YAML 欄位詳解

> 2026-03-28 實測驗證後的正確 schema

### 頂層結構

```yaml
version: 1                    # 整數，不是字串 "1"
filesystem_policy: ...        # 不是 filesystem
landlock: ...
process: ...
network_policies: ...         # map 格式，不是 list
```

### filesystem_policy

```yaml
filesystem_policy:
  include_workdir: true       # 建議加上，讓工作目錄也受保護
  read_write:                 # 可讀寫的路徑（不是 writable）
    - /sandbox
    - /tmp
    - /dev/null
  read_only:                  # 唯讀路徑（不是 readable）
    - /usr
    - /lib
    - /proc
    - /etc
```

> **Live sandbox 限制**：已運行的 sandbox 只能**新增**路徑，不能移除已有路徑。
> 修改前先用 `openshell policy get <name> --full` 匯出現有 policy，在其上疊加修改。

### landlock

```yaml
landlock:
  compatibility: best_effort  # 建議加上，相容性較好
```

### process

```yaml
process:
  run_as_user: sandbox        # 固定用 sandbox，不是 agent
  run_as_group: sandbox
```

### network_policies

```yaml
network_policies:             # map 格式，key 是 policy ID（底線分隔）
  policy_key:                 # 例如：claude_code、github_rest_api
    name: policy-display-name # 必填，顯示用名稱（可用連字號）
    endpoints:                # 不是分開的 hosts + ports
      - { host: "example.com", port: 443 }            # 基本寫法
      - host: "api.example.com"
        port: 443
        protocol: rest        # rest | grpc（選填）
        tls: terminate        # terminate（選填）
        enforcement: enforce  # enforce | audit（在 endpoint 層，不是 policy 層）
        access: read-only     # read-only | full（選填）
    binaries:                 # 必填！省略會導致所有程式被 403 擋住
      - { path: /usr/bin/curl }
      - { path: "/sandbox/.venv/**" }   # 支援 glob
```

### 常見欄位錯誤對照

| ❌ 錯誤 | ✅ 正確 |
|---------|---------|
| `filesystem` | `filesystem_policy` |
| `writable` | `read_write` |
| `readable` | `read_only` |
| `network`（list） | `network_policies`（map） |
| `hosts` / `ports`（分開） | `endpoints: [{ host, port }]` |
| `allow_exec: true` | 不支援 |
| `enforcement` 放在 policy 層級 | `enforcement` 放在**每個 endpoint 內部** |
| 省略 `name` 欄位 | 每個 network policy 都需要 `name` |
| 省略 `binaries` | `binaries` **必須指定**，省略 → proxy 回 403 |
| `version: "1"`（字串） | `version: 1`（整數） |

### Claude Code binary 路徑陷阱

Claude Code 安裝後有三個路徑都需要列入 `binaries`：

```yaml
binaries:
  - { path: /usr/local/bin/claude }           # 全域 binary
  - { path: "/sandbox/.local/bin/claude" }    # user 安裝的 symlink
  - { path: "/sandbox/.local/share/claude/versions/**" }  # 實際 binary（glob）
  - { path: /usr/bin/node }                   # Claude 用 Node.js 執行
```

> Proxy 檢查的是**實際執行的 binary 路徑**，而非 symlink。
> `which claude` 在 sandbox 內解析到的是版本號目錄下的實際 binary。

---

## 學習路徑建議

1. **看懂架構**：閱讀本文件的「架構圖」部分
2. **跑一次安裝**：按 [installation.md](./installation.md) 手動跑一遍，了解每個步驟在做什麼
3. **觀察 policy 效果**：
   ```bash
   openshell logs claude-dev --tail    # 觀察 allow/deny 的 pattern
   ```
4. **實驗 policy 修改**：故意移除一個 endpoint，觀察 deny log，再加回去
5. **了解 sandbox 隔離**：`make verify` 驗證兩個 sandbox 確實互相隔離

---

## 相關官方資源

- OpenShell 官網：https://openshell.ai
- Claude Code 文件：https://claude.ai/code
- OpenClaw 文件：https://openclaw.dev
- OrbStack 官網：https://orbstack.dev
- Google AI Studio（取得 API Key）：https://aistudio.google.com/apikey
- GitHub Fine-grained PAT 設定：https://github.com/settings/personal-access-tokens/new
