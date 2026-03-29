# 安裝手冊：OpenShell 雙 Sandbox 環境設定

> **版本**：v5（2026-03-28 實測修正）
> **自動化**：大多數步驟可用 `make install` 執行，本文件為手動參考版本

---

## Phase 0：帳號與金鑰申請

### 0.1 帳號清單

| # | 服務 | 用途 | 費用 | 產出 |
|---|------|------|------|------|
| 1 | **Google AI Studio** | OpenClaw 的 Gemini Flash | 免費額度起步 | `GOOGLE_API_KEY`（AIza...） |
| 2 | **GitHub** | 兩把 Fine-grained PAT | 免費 | 兩把 token（見下方） |
| 3 | **Anthropic 帳號** | Claude Code OAuth 登入 | 現有 Pro/Max 訂閱 | 瀏覽器登入（不需 API Key） |

> **不需要 Anthropic API Key。** Claude Code 走 OAuth `/login`。
>
> **不需要 Docker Hub 帳號。** OrbStack 不需要登入。

### 0.2 取得 Google AI Studio API Key

```
1. 前往 https://aistudio.google.com/apikey
2. 用 Google 帳號登入
3. "Create API Key" → 選擇或建立 Google Cloud Project
4. 複製 key（AIza...）→ 存到密碼管理器
```

### 0.3 建立兩把 GitHub Fine-grained PAT

前往 https://github.com/settings/personal-access-tokens/new → 選 **Fine-grained personal access token**

#### Token 1：Claude Code 開發用

| 欄位 | 值 |
|------|-----|
| Token name | `openshell-claude-dev` |
| Expiration | 30 天 |
| Repository access | **Only select repositories** → 勾開發用 repo |

| 權限 | 層級 |
|------|------|
| Contents | Read and write |
| Metadata | Read-only（必須） |
| Pull requests | Read and write（選配） |

#### Token 2：OpenClaw agent 用

| 欄位 | 值 |
|------|-----|
| Token name | `openshell-claw-agent` |
| Expiration | 30 天 |
| Repository access | **Only select repositories** → 只勾 agent 需要的 repo |

| 權限 | 層級 |
|------|------|
| Contents | Read-only |
| Metadata | Read-only（必須） |

---

## Phase 1：Mac Mini 基礎環境

> 自動化：`make install-base`

```bash
sw_vers          # macOS 13+
uname -m         # arm64

# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
source ~/.zshrc

# 基礎工具
brew install git node python3 uv jq
```

---

## Phase 2：安裝 OrbStack

> 自動化：`make install-base`

```bash
brew install orbstack
open -a OrbStack
```

**首次設定：Docker / Kubernetes / Linux → 選 Docker**

- ❌ 不選 Kubernetes（OpenShell 自帶 K3s）
- ❌ 不選 Linux Machine
- ✅ 選 Docker

**系統彈窗：** 「improve Docker socket compatibility」→ 允許

**資源設定：** OrbStack → Preferences → Memory limit: 8 GB（16GB 機器）

**驗證：**

```bash
docker --version
docker run --rm hello-world
ls -la /var/run/docker.sock
```

**預防 OpenClaw PATH 問題：**

```bash
mkdir -p ~/.local/bin
ln -sf ~/.orbstack/bin/docker ~/.local/bin/docker
ln -sf ~/.orbstack/bin/docker-compose ~/.local/bin/docker-compose
```

---

## Phase 3：安裝 OpenShell CLI

> 自動化：`make install-base`

```bash
uv tool install openshell
openshell --version
openshell gateway start       # 首次約 2-5 分鐘
openshell status              # Gateway → Connected
```

---

## Phase 4：建立 Providers

> 自動化：`make setup-claude`（會互動式詢問 token）

### 語法

```
openshell provider create --name <名稱> --type <類型> --credential KEY="value"
openshell provider create --name <名稱> --type <類型> --credential KEY        # 從 env 讀
openshell provider create --name <名稱> --type <類型> --from-existing          # 自動偵測

# type 可用值: claude, opencode, codex, generic, openai, anthropic, nvidia, gitlab, github, outlook
```

### 建立

```bash
# GitHub: Claude Code 用（read/write）
openshell provider create \
  --name github-claude \
  --type github \
  --credential GITHUB_TOKEN="github_pat_你的claude-dev-token"

# GitHub: OpenClaw 用（read-only）
openshell provider create \
  --name github-claw \
  --type github \
  --credential GITHUB_TOKEN="github_pat_你的claw-agent-token"

# Gemini: OpenClaw 用（type 用 generic）
openshell provider create \
  --name gemini-flash \
  --type generic \
  --credential GOOGLE_API_KEY="AIza你的key"

# 確認
openshell provider list
```

---

## Phase 5：建立 Sandbox A — Claude Code（OAuth）

> 自動化：`make setup-claude`

```bash
openshell sandbox create \
  --name claude-dev \
  --provider github-claude \
  -- claude
```

### 首次進入 sandbox：修 PATH 與初始化

sandbox 內的 `~/.local/bin` 可能不在 PATH 中，且需要手動完成兩個初始化步驟：

```bash
openshell sandbox connect claude-dev

# 1. 修 PATH
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# 2. 設定 git SSL CA（proxy TLS termination 需要）
echo 'export GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem' >> ~/.bashrc

source ~/.bashrc

# 3. 手動 pre-clone marketplace（繞過 Claude Code 的 race condition）
mkdir -p ~/.claude/plugins/marketplaces
GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem \
  git clone --depth 1 \
  https://github.com/anthropics/claude-plugins-official.git \
  ~/.claude/plugins/marketplaces/claude-plugins-official

mkdir -p ~/.claude/plugins
cat > ~/.claude/plugins/known_marketplaces.json << 'HEREDOC'
{
  "claude-plugins-official": {
    "source": {
      "source": "github",
      "repo": "anthropics/claude-plugins-official"
    },
    "installLocation": "/sandbox/.claude/plugins/marketplaces/claude-plugins-official",
    "lastUpdated": "2026-03-28T11:10:00.000Z"
  }
}
HEREDOC

# 4. 啟動 claude
claude
```

### OAuth 認證

```
1. claude 啟動 → 印出認證連結
2. 瀏覽器開啟 → 用 Anthropic Pro/Max 登入
3. /status → 確認顯示 "Pro" 或 "Max"
```

如果顯示 "API Usage Billing"：

```bash
unset ANTHROPIC_API_KEY
/logout
/login
```

如果碰到 `Invalid bearer token`：

```bash
sed -i '/"apiKeyHelper"/d' ~/.claude/settings.json
```

### 連線 Editor

```bash
openshell sandbox ssh-config claude-dev >> ~/.ssh/config
# VS Code / Cursor → Remote-SSH → claude-dev
```

---

## Phase 6：建立 Sandbox B — OpenClaw（Gemini Flash）

> 自動化：`make setup-claw`

```bash
openshell sandbox create \
  --name claw-agent \
  --provider github-claw \
  --provider gemini-flash \
  --from openclaw
```

### 設定 OpenClaw

```bash
openshell sandbox connect claw-agent
openclaw onboard --auth-choice google-api-key
```

或手動編輯 `~/.openclaw/openclaw.json`：

```json
{
  "models": {
    "providers": {
      "google": { "apiKey": "$GOOGLE_API_KEY" }
    },
    "defaults": {
      "provider": "google",
      "model": "google/gemini-3-flash"
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-3-flash" }
    }
  },
  "gateway": { "bind": "loopback" }
}
```

---

## Phase 7：套用 Policy YAML

> 自動化：`make apply-policies`

Policy 檔案位於 `policies/` 目錄，詳細的欄位說明請參考 [learning.md](./learning.md#policy-yaml-欄位詳解)。

```bash
# 套用 Claude sandbox policy
openshell policy set claude-dev \
  --policy policies/claude_dev_policy.yaml \
  --wait

# 套用 OpenClaw sandbox policy
openshell policy set claw-agent \
  --policy policies/claw_agent_policy.yaml \
  --wait
```

### 當 deny log 出現時如何新增 host

```bash
# 1. 查 log 找被擋的 host 和 binary
openshell logs claude-dev --since 10m | grep "action=deny"

# 2. 從 log 讀取關鍵資訊：
#    - dst_host / dst_port → 加到對應 policy 的 endpoints
#    - binary → 確認該 binary 在該 policy 的 binaries 清單中

# 3. 熱更新（不用重啟 sandbox）
openshell policy set claude-dev --policy policies/claude_dev_policy.yaml --wait

# 4. 查看目前完整 policy（建議修改前先匯出）
openshell policy get claude-dev --full
```

---

## Phase 8：驗證沙箱隔離

> 自動化：`make verify`

```bash
# 檔案系統隔離驗證
openshell sandbox connect claude-dev
echo "secret" > /sandbox/test.txt && exit
openshell sandbox connect claw-agent
cat /sandbox/test.txt  # → No such file or directory

# Credential 隔離驗證
openshell sandbox connect claude-dev
echo $GOOGLE_API_KEY    # → 空
exit
openshell sandbox connect claw-agent
echo $GOOGLE_API_KEY    # → AIza...
```

---

## Troubleshooting

| 問題 | 解法 |
|------|------|
| `connection refused (os error 61)` | `open -a OrbStack` |
| Claude Code 顯示 "API Usage Billing" | `unset ANTHROPIC_API_KEY` → `/logout` → `/login` |
| `Invalid bearer token` | `sed -i '/"apiKeyHelper"/d' ~/.claude/settings.json` |
| `~/.local/bin is not in your PATH` | `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc` |
| `Failed to install Anthropic marketplace`（每次啟動） | Race condition，手動 pre-clone（見 Phase 5） |
| `action=deny` in logs | 從 log 的 `dst_host` 取 host、`binary` 取 binary，兩個都要加進 policy |
| Policy YAML parse error: `unknown field 'enforcement'` | `enforcement` 必須放在**每個 endpoint 內部**，不是 policy 層級 |
| Policy YAML parse error: 其他欄位 | 用正確 schema：`filesystem_policy`、`network_policies`（map）、每個 policy 需有 `name` 欄位 |
| proxy 回 403（CONNECT tunnel failed） | policy 有 endpoint 但缺 `binaries`，proxy 不知道允許哪個程式 |
| proxy 回 403 但 endpoint 和 binaries 都有填 | Binary 路徑不匹配：需同時列 `/usr/local/bin/claude`、`/sandbox/.local/bin/claude`、`/sandbox/.local/share/claude/versions/**` |
| `filesystem read_only path cannot be removed on a live sandbox` | live sandbox 只能**新增**路徑，不能刪除。先 `openshell policy get <name> --full` 再疊加修改 |
| `git clone` 失敗：`server certificate verification failed` | 加 `export GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem` 到 `~/.bashrc` |
| MCP servers (Canva/Gmail/Figma) 全部 `Connection failed` | `mcp-proxy.anthropic.com:443` 未加到 `claude_code` policy |
| `unexpected argument '--env'` | 用 `--credential KEY=VALUE` |
| git push 403 | PAT 到期，走 Token 輪替（見 [usage.md](./usage.md#token-輪替)) |
| npm install 慢 | 在 sandbox 內 clone repo，不要 bind mount |

---

## 附錄：每月成本

| 項目 | 月費 (USD) |
|------|-----------|
| OrbStack | $0 |
| OpenShell | $0 |
| OpenClaw | $0 |
| Claude Code | $0 額外（Pro/Max 訂閱涵蓋） |
| Gemini Flash | $0 ~ $5 |
| **合計** | **$0 ~ $5**（加上現有 Claude 訂閱） |
