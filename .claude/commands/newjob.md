# New Job — 開啟新工作前準備（Worktree-First）

開始新 feature 或 fix 之前，執行此結構化流程確保環境乾淨並建立隔離工作空間。

**自主執行原則**：執行所有步驟，不要問問題。任何步驟失敗時，診斷並修復後繼續。只在全部通過後才告知環境就緒。

**常數定義**（整個流程中使用絕對路徑）：
- `MAIN_REPO=/Users/doxa/workspace/github/MiniShell`
- `WORKTREE_BASE=/Users/doxa/workspace/github/MiniShell-worktrees`

## Step 1: 環境偵測

```bash
git rev-parse --show-toplevel
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

根據使用者描述推導 branch 和 worktree 名稱（簡短有意義，例如 `fix-policy-path`、`feat-sandbox-monitor`）。

```bash
# 確保 main 是最新的
git -C /Users/doxa/workspace/github/MiniShell fetch origin main

# 建立 worktree + branch
git -C /Users/doxa/workspace/github/MiniShell worktree add /Users/doxa/workspace/github/MiniShell-worktrees/<name> -b <name> origin/main

# ⚠️ 必做：修正 push tracking，避免 push.default=upstream 把 push 走到 origin/main
git -C /Users/doxa/workspace/github/MiniShell-worktrees/<name> branch --unset-upstream
git -C /Users/doxa/workspace/github/MiniShell-worktrees/<name> push origin HEAD:<name>
git -C /Users/doxa/workspace/github/MiniShell-worktrees/<name> branch -u origin/<name>
```

**注意**：使用 `git -C $MAIN_REPO` 確保在主 repo 執行，不依賴 Bash `cd` 持久性。

### 2b. ⚠️ Push 安全驗證（必做，不論 worktree 建立方式）

無論是用 `git worktree add` 還是 `EnterWorktree` 工具建立 worktree，都必須確認 push tracking 不是 `origin/main`。
`push.default=upstream` + 追蹤 `origin/main` = commit 直推 main，繞過 PR 流程。

```bash
WT=/Users/doxa/workspace/github/MiniShell-worktrees/<name>  # 或 .claude/worktrees/<name>

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

**用 `EnterWorktree` 建立的 worktree 路徑**在 `.claude/worktrees/<name>`，記得替換 `WT` 路徑。

### 2a. 複製 Gitignored 開發檔案

Worktree 建立後，從主 repo 複製被 `.gitignore` 排除但開發必需的檔案。

```bash
MAIN_REPO=/Users/doxa/workspace/github/MiniShell
WT=/Users/doxa/workspace/github/MiniShell-worktrees/<name>

for f in \
  .env \
; do
  [ -f "$MAIN_REPO/$f" ] && cp "$MAIN_REPO/$f" "$WT/$f" && echo "  ✓ copied $f"
done
```

## Step 3: Environment Validation

在目標工作目錄中執行（worktree 路徑或當前 repo），使用絕對路徑。**每個步驟若失敗，診斷並修復後再繼續。**

### 3a. 確認 Lint 乾淨

```bash
make -C <工作目錄> lint
```

Lint 失敗時診斷 shell script 問題並修復，確保通過。

## Step 4: Go/No-Go Report

全部通過後才輸出就緒報告：

```
=== New Job Report ===
Branch:      <name>
Worktree:    /Users/doxa/workspace/github/MiniShell-worktrees/<name>
Lint:        ✅ clean
Issues fixed: <若有，列出修復的項目>
─────────────────────────
✅ Environment is ready.
```

如有任何步驟無法修復，列出具體錯誤並停在此，請使用者介入。

## Step 5: 引導切換（僅 Worktree 模式）

印出明確指令讓使用者切換到新 worktree：

```
📂 Worktree 已就緒！請在終端機執行：

   cd /Users/doxa/workspace/github/MiniShell-worktrees/<name>

⚠️ 當前 Claude Code session 的工作目錄仍在原位置。
   建議在新目錄開啟新的 Claude Code session 以獲得正確的 cwd。
```
