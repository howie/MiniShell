# New Job — 開啟新工作前準備（Worktree-First）

開始新 feature 或 fix 之前，執行此結構化流程確保環境乾淨並建立隔離工作空間。

**自主執行原則**：執行所有步驟，不要問問題。任何步驟失敗時，診斷並修復後繼續。只在全部通過後才告知環境就緒。

## Step 1: 環境偵測

```bash
MAIN_REPO=$(git rev-parse --show-toplevel)
WORKTREE_BASE="$MAIN_REPO/.claude/worktrees"
git status --short
```

**判斷邏輯**：

1. **已在 worktree**（`--show-toplevel` 路徑在 `WORKTREE_BASE` 下）：
   - 告知使用者「偵測到已在 worktree 中」
   - 跳過 Step 2，直接執行 Step 3（Environment Validation）→ Step 4（Report）

2. **在主 repo 或其他位置**：
   - 如有 uncommitted changes，**警告**使用者（提醒 stash 或 commit）
   - 根據使用者提供的 feature name 自動建立 worktree（執行 Step 2）

## Step 2: 建立 Worktree

根據使用者描述推導 branch 和 worktree 名稱（簡短有意義，例如 `fix-policy-path`、`feat-bridge-discord`）。

```bash
MAIN_REPO=$(git rev-parse --show-toplevel)
WORKTREE_BASE="$MAIN_REPO/.claude/worktrees"

# 確保 main 是最新的
git -C "$MAIN_REPO" fetch origin main

# 建立 worktree + branch
git -C "$MAIN_REPO" worktree add "$WORKTREE_BASE/<name>" -b "<name>" origin/main

# ⚠️ 必做：修正 push tracking，避免 push.default=upstream 把 push 走到 origin/main
git -C "$WORKTREE_BASE/<name>" branch --unset-upstream
git -C "$WORKTREE_BASE/<name>" push origin HEAD:<name>
git -C "$WORKTREE_BASE/<name>" branch -u origin/<name>
```

### 2b. ⚠️ Push 安全驗證（必做）

無論是用 `git worktree add` 還是 `EnterWorktree` 工具建立 worktree，都必須確認 push tracking 不是 `origin/main`。

```bash
WT="$WORKTREE_BASE/<name>"

UPSTREAM=$(git -C "$WT" rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo "none")
if [ "$UPSTREAM" = "origin/main" ]; then
  echo "⚠️ DANGER: branch 追蹤 origin/main，修正中..."
  git -C "$WT" branch --unset-upstream
  git -C "$WT" push origin HEAD:<name>
  git -C "$WT" branch -u origin/<name>
  echo "✓ 修正完成，現在追蹤 origin/<name>"
else
  echo "✓ Push tracking OK: $UPSTREAM"
fi
```

### 2a. 複製 Gitignored 開發檔案

Worktree 建立後，從主 repo 複製被 `.gitignore` 排除但開發必需的檔案。

```bash
MAIN_REPO=$(git rev-parse --show-toplevel)
WT="$WORKTREE_BASE/<name>"

# 逐一檢查並複製（檔案存在才複製，避免報錯）
for f in \
  .env \
  bridge-go/.env \
; do
  [ -f "$MAIN_REPO/$f" ] && cp "$MAIN_REPO/$f" "$WT/$f" && echo "  ✓ copied $f"
done
```

**維護提示**：若日後新增其他 gitignored 開發檔案，在上方 `for` 清單中加入路徑即可。

## Step 3: Environment Validation

在目標工作目錄中執行（worktree 路徑或當前 repo）。**每個步驟若失敗，診斷並修復後再繼續。**

### 3a. 確認工具已安裝

```bash
which openshell || echo "⚠️ openshell 未安裝，執行 make install-base"
which orbctl    || echo "⚠️ OrbStack 未安裝"
brew list | grep -q openshell && echo "✓ openshell 已安裝"
```

### 3b. 確認 Sandbox 狀態

```bash
openshell sandbox list
```

預期看到 `claude-dev` 和 `claw-agent` 兩個 sandbox。若未建立，提示執行對應的 `make setup-claude` / `make setup-claw`。

### 3c. 驗證隔離

```bash
make -C "$(git rev-parse --show-toplevel)" verify
```

`make verify` 失敗時為 **blocker**。診斷 root cause（policy 設定、credential 注入）並修復。

### 3d. 確認 Policy 乾淨

```bash
ls policies/
```

確認 `claude_dev_policy.yaml` 和 `claw_agent_policy.yaml` 存在且無語法錯誤（用 `yq` 或 `python3 -c "import yaml; yaml.safe_load(open('policies/claude_dev_policy.yaml'))"` 驗證）。

## Step 4: Go/No-Go Report

全部通過後才輸出就緒報告：

```
=== New Job Report ===
Branch:      <name>
Worktree:    .claude/worktrees/<name>
openshell:   ✅ 已安裝
Sandboxes:   ✅ claude-dev, claw-agent running
Verify:      ✅ isolation checks passed
Policies:    ✅ claude_dev_policy.yaml, claw_agent_policy.yaml valid
Issues fixed: <若有，列出修復的項目>
─────────────────────────
✅ Environment is ready.
```

如有任何步驟無法修復，列出具體錯誤並停在此，請使用者介入。

## Step 5: 引導切換（僅 Worktree 模式）

印出明確指令讓使用者切換到新 worktree：

```
📂 Worktree 已就緒！請在終端機執行：

   cd .claude/worktrees/<name>

⚠️ 當前 Claude Code session 的工作目錄仍在原位置。
   建議在新目錄開啟新的 Claude Code session 以獲得正確的 cwd。
   或使用 EnterWorktree 工具在當前 session 切換。
```
