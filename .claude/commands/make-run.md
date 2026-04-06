# Smart Make Runner

執行 make 指令前的預檢和錯誤自動修復流程。避免 CWD 錯誤、依賴未同步、新檔案未 format 等常見問題。

## 使用者輸入

$ARGUMENTS — make target（例如 `check`, `test`, `format`, `test-back`, `test-front`, `dev`）

如果 $ARGUMENTS 為空，詢問使用者要執行哪個 target。

## 常數定義

- `MAIN_REPO=/Users/howie/Workspace/github/heyu-ai/yibi-mvp`
- `WORKTREE_BASE=/Users/howie/Workspace/github/heyu-ai/yibi-mvp-worktrees`

## Step 1: 環境偵測

```bash
pwd
git rev-parse --show-toplevel 2>/dev/null
ls Makefile 2>/dev/null
```

**判斷邏輯**：
- 取得 `WORK_DIR`（git toplevel 路徑）
- 確認 `WORK_DIR` 是主 repo 或 worktree（路徑在 `WORKTREE_BASE` 下）
- 確認 `Makefile` 存在於 `WORK_DIR`
- **Makefile 不存在** → 報錯並停止

### make 指令可執行性檢查

```bash
type make 2>&1
```

- 如果輸出包含 `function` → zsh function shadowing，後續所有 `make` 呼叫必須使用 `command make`
- 如果輸出包含 `/usr/bin/make` 或其他路徑 → 正常，但仍統一使用 `command make` 以防萬一

**後續所有 `make` 呼叫一律使用 `command make`**（`command` 是 POSIX built-in，跳過 function/alias lookup，直接找 `$PATH` 上的 binary），搭配 `-C $WORK_DIR` 避免 CWD 不持久問題。

## Step 2: 依賴預檢

**僅在 target 是 `check`, `test`, `test-back`, `test-front`, `lint`, `typecheck` 時執行。**
`format`, `dev`, `clean` 等 target 跳過此步。

```bash
# 檢查 backend virtualenv
ls $WORK_DIR/backend/.venv/bin/python 2>/dev/null

# 檢查 frontend node_modules
ls $WORK_DIR/frontend/node_modules/.package-lock.json 2>/dev/null
```

- backend `.venv` 不存在 → 執行 `cd $WORK_DIR/backend && uv sync --all-extras`
- frontend `node_modules` 不存在 → 執行 `cd $WORK_DIR/frontend && npm install`
- 都存在 → 跳過（不每次都 sync，太慢）

## Step 3: 新檔案預處理

**僅在 target 是 `check` 時執行。**

```bash
# 找出 staged 或 unstaged 新增的 .py 檔
cd $WORK_DIR && git diff --name-only --diff-filter=A HEAD 2>/dev/null
cd $WORK_DIR && git diff --name-only --diff-filter=A --cached 2>/dev/null
# 也找 untracked .py 檔
cd $WORK_DIR && git ls-files --others --exclude-standard '*.py'
```

對找到的 `.py` 新檔案執行：

```bash
cd $WORK_DIR && ruff format <files>
```

如果沒有新 `.py` 檔，跳過。

## Step 4: 智慧執行順序

根據 target 決定前置步驟：

### `check` target
- **先跑 `command make -C $WORK_DIR format`**，自動修復格式問題
- 再跑 `command make -C $WORK_DIR check`

### `test` / `test-back` target
- 檢查 migration 狀態：
  ```bash
  cd $WORK_DIR/backend && uv run alembic current 2>&1
  cd $WORK_DIR/backend && uv run alembic heads 2>&1
  ```
- current 與 heads 不同 → **警告使用者** migration 可能未跑，詢問是否先執行 `command make -C $WORK_DIR db-migrate`
- 相同 → 繼續

### 其他 target
- 直接執行，無前置步驟

## Step 5: 執行 make target

```bash
command make -C $WORK_DIR $TARGET
```

- 成功 → 報告結果，結束
- 失敗 → 進入 Step 6

## Step 6: 失敗自動修復（最多 1 輪）

分析錯誤輸出，匹配以下模式並嘗試修復：

| 錯誤模式 | 修復動作 | 重跑 |
|---------|---------|------|
| `ruff format` 差異 / formatting 失敗 | `command make -C $WORK_DIR format` | 是 |
| `ruff check` lint 錯誤 | `cd $WORK_DIR && ruff check --fix .` | 是 |
| `ModuleNotFoundError` / `ImportError` (backend) | `cd $WORK_DIR/backend && uv sync --all-extras` | 是 |
| `Cannot find module` / npm error (frontend) | `cd $WORK_DIR/frontend && npm install` | 是 |
| `eslint` 錯誤 | `cd $WORK_DIR/frontend && npx eslint --fix src/` | 是 |
| `function definition file not found` | zsh function shadowing — 用 `command make -C $WORK_DIR $TARGET` 重試 | 是 |
| `column "X" does not exist` / migration 相關 | **報告**：建議跑 `command make db-migrate`，不自動執行 | 否 |
| `multiple heads` | **報告**：建議跑 `alembic merge heads`，不自動執行 | 否 |
| 其他錯誤 | **報告**錯誤內容，不重試 | 否 |

**規則**：
- 最多自動修復 + 重跑 **1 次**。第二次仍失敗則報告錯誤，不再重試
- Migration 相關問題**永遠不自動修復**（可能影響資料），只報告並建議
- 自動修復前告知使用者正在做什麼

## 輸出格式

執行完成後輸出簡潔報告：

```
=== Make Run Report ===
Target:      make $TARGET
Directory:   $WORK_DIR
Pre-check:   ✅ deps synced / ⏭️ skipped
Pre-format:  ✅ new files formatted / ⏭️ skipped
Auto-fix:    ✅ applied & retried / ⏭️ not needed / ❌ failed
Result:      ✅ passed / ❌ failed
```
