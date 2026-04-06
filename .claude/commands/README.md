# Custom Commands

這個目錄包含 MiniShell 專案自訂的 Claude Code slash commands。

## 可用命令

### `/clean-merged`
清理所有已經 merged 的本地分支（包括透過 squash merge 合併的分支）。

**功能**:
- ✅ 檢查所有本地分支的 PR 狀態
- ✅ 自動清理已 merged 的分支
- ✅ 處理 worktree 關聯的分支
- ✅ 支援 GitHub 的 "Squash and merge" 策略
- ✅ 只刪除有 merged PR 的分支

### `/clean-gone`
增強版的 gone 分支清理命令。

**功能**:
- ✅ 清理標記為 [gone] 的分支（遠端已刪除）
- ✅ 可選：同時清理所有 merged PR 的分支
- ✅ 提供多種清理策略選項
- ✅ 更詳細的預覽和確認流程

### `/newjob`
開始新 feature 或 fix 前的環境準備。建立 worktree、驗證 sandbox 狀態、確認 policy 正常。

**功能**:
- ✅ 偵測當前位置（主 repo 或 worktree）
- ✅ 建立 `.claude/worktrees/<name>` worktree 並修正 push tracking
- ✅ 複製 gitignored 開發檔案（`.env`）
- ✅ 驗證 openshell/sandbox/policy 狀態
- ✅ Go/No-Go 報告

### `/pr`
自動化 PR 工作流程：驗證 → commit → push → create/update PR。

**功能**:
- ✅ 確認不在 main 分支
- ✅ 執行 `make verify` 品質檢查
- ✅ Stage 並 commit 未提交的變更
- ✅ Push 並建立/更新 PR

### `/debug`
結構化 debug 方法論，強制 root cause 分析後才建議修復。

**功能**:
- ✅ 7 個 phase 的系統化調查流程
- ✅ 優先檢查 sandbox/policy 狀態和 deny log
- ✅ Config shadowing 偵測
- ✅ 只在確認 root cause 後才實作修復

### `/debug-to-pr`
Debug 完成後，將修復轉為乾淨的 PR。

**功能**:
- ✅ 分類 fix files / debug artifacts / unrelated changes
- ✅ 執行 `make verify` 品質確認
- ✅ Selective staging（排除 debug log、.env 變更）
- ✅ Conventional commit + PR 建立

### `/verify-deploy`
套用 policy 或執行安裝腳本後的結構化驗證。

**功能**:
- ✅ Sandbox 狀態確認（claude-dev、claw-agent）
- ✅ Policy 生效確認
- ✅ Deny log 檢查
- ✅ `make verify` 隔離驗證
- ✅ Pass/Fail 報告

### `/gemini-models`
查詢 Gemini API 可用模型並與 codebase 設定比對。

**功能**:
- ✅ 即時查詢 API 可用模型
- ✅ 分類（LLM / Live API / Imagen）
- ✅ 與 scripts/、policies/、.env.example 交叉比對
- ✅ 偵測已下架或有更新版的模型

### `/spectra:*`
Spectra workflow 系列命令（位於 `spectra/` 子目錄）。

| 命令 | 說明 |
|------|------|
| `/spectra:propose` | 建立完整 change proposal |
| `/spectra:apply` | 實作 Spectra change 的任務 |
| `/spectra:ingest` | 從 plan 或對話更新 change |
| `/spectra:discuss` | 聚焦討論並收斂結論 |
| `/spectra:ask` | 查詢 openspec 文件（唯讀） |
| `/spectra:audit` | 安全稽核（3-adversary framework） |
| `/spectra:debug` | 4-phase debug 流程 |
| `/spectra:archive` | 歸檔已完成的 change |

## 命令比較

| 特性 | `/clean-merged` | `/clean-gone` |
|------|----------------|---------------|
| 清理 [gone] 分支 | ❌ | ✅ |
| 清理 merged PR 分支 | ✅ | ✅ (可選) |
| Squash merge 支援 | ✅ | ✅ |
| 多種清理策略 | ❌ | ✅ |
| 自動模式 | ✅ | ❌ (需確認) |

## 安全特性

所有 git 相關命令包含以下安全機制：

- ✅ 永遠不會刪除 main 分支
- ✅ 刪除前會檢查 worktree
- ✅ 提供清理預覽
- ✅ 只刪除已確認 merged 的分支
- ✅ 保留有 open PR 的分支
