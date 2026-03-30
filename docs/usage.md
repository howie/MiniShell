# 日常使用指南

## 常用指令速查

### Sandbox 操作

```bash
openshell sandbox list                          # 列出所有 sandbox
openshell sandbox connect claude-dev            # 進入 Claude sandbox
openshell sandbox connect claw-agent            # 進入 OpenClaw sandbox
openshell logs claude-dev --tail                # 即時看 log
openshell logs claude-dev --since 10m           # 近 10 分鐘 log
openshell term                                  # TUI dashboard（視覺化監控）
```

### Policy 熱更新（不需重啟 sandbox）

```bash
openshell policy get claude-dev                 # 查看目前 policy 摘要
openshell policy get claude-dev --full          # 查看完整 policy（修改前先匯出）
openshell policy set claude-dev \
  --policy policies/claude_dev_policy.yaml \
  --wait                                        # 套用並等待生效

openshell policy set claw-agent \
  --policy policies/claw_agent_policy.yaml \
  --wait
```

### Port Forwarding

```bash
openshell forward start 18789 claw-agent        # 把 claw-agent 的 18789 port 對外
openshell forward list
openshell forward stop 18789
```

### Gateway 管理

```bash
openshell status                                # 查看 gateway 狀態
openshell gateway start                         # 啟動 gateway
openshell gateway restart                       # 重啟 gateway（OrbStack 重啟後需要）
openshell gateway stop
```

### Provider 管理

```bash
openshell provider list                         # 列出所有 provider
openshell provider get github-claude            # 查看特定 provider
openshell provider update \
  --name gemini-flash \
  --credential GOOGLE_API_KEY="新key"          # 更新 credential
openshell provider delete 舊provider名          # 刪除 provider
```

### 在 Claude sandbox 內

```bash
claude                                          # 啟動 Claude Code
/status                                         # 確認訂閱狀態（應顯示 Pro 或 Max）
/logout && /login                               # 重新認證
```

### Git 操作（在 Claude sandbox 內）

```bash
source ~/.bashrc                                # 載入 GIT_SSL_CAINFO（每次進入 sandbox 後建議執行）
git clone https://github.com/user/repo.git     # Clone repo
git push                                        # 推送（需要 PAT Contents write 權限）
```

> 詳細說明、手動設定方法、常見問題請參考 [sandbox-git.md](./sandbox-git.md)

### 在 OpenClaw sandbox 內

```bash
openclaw                                        # 啟動 OpenClaw
/model google/gemini-3-flash                    # 切換到 Gemini 3 Flash
/model google/gemini-3.1-pro                    # 切換到 Gemini 3.1 Pro
```

---

## 每日工作流程

```bash
# 1. 確認 gateway 在線
openshell status

# 2. 啟動 sandbox（如果停了）
# Sandbox 通常保持運行，不需要手動啟動

# 3. 進入工作
openshell sandbox connect claude-dev
# 在 sandbox 內開始工作...

# 4. 監控 deny log（若懷疑 policy 擋到正常請求）
openshell logs claude-dev --since 1h | grep "action=deny"
```

---

## Token 輪替

> 每 30 天執行一次，GitHub PAT 到期前提早輪替

> ⚠️ **重要**：重建 sandbox 之前，確認 sandbox 內的所有工作已 `git push`！

```bash
# Step 1：到 GitHub 產新 token（same repo + 同樣權限）
# https://github.com/settings/personal-access-tokens

# Step 2：更新 provider
openshell provider update \
  --name github-claude \
  --credential GITHUB_TOKEN="github_pat_新的claude-dev-token"

openshell provider update \
  --name github-claw \
  --credential GITHUB_TOKEN="github_pat_新的claw-agent-token"

# Step 3：重建 sandbox（provider credential 不能熱更新到運行中的 sandbox）
openshell sandbox rm claude-dev
openshell sandbox create \
  --name claude-dev \
  --provider github-claude \
  -- claude

openshell sandbox rm claw-agent
openshell sandbox create \
  --name claw-agent \
  --provider github-claw \
  --provider gemini-flash \
  --from openclaw

# Step 4：重新套用 policy
make apply-policies

# Step 5：重新初始化 Claude sandbox（Path、marketplace）
openshell sandbox connect claude-dev
# 重新執行 Phase 5 初始化步驟
```

---

## 常見情境

### OrbStack 重啟後 gateway 斷線

```bash
open -a OrbStack          # 確保 OrbStack 在跑
openshell gateway restart
openshell status          # 應顯示 Connected
```

### Policy 新增一個 host

```bash
# 1. 查 deny log 確認被擋的 host
openshell logs claude-dev --since 10m | grep "action=deny"
# 範例輸出：dst_host=storage.googleapis.com dst_port=443 binary=/usr/bin/curl

# 2. 編輯 policies/claude_dev_policy.yaml，在對應 policy block 新增 endpoint 和 binary

# 3. 熱更新
openshell policy set claude-dev \
  --policy policies/claude_dev_policy.yaml \
  --wait
```

### 確認 sandbox 是否互相隔離

```bash
make verify
```
