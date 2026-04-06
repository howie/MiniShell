# Custom Git Cleanup Commands

這個目錄包含專案自訂的 Git 清理命令。

## 可用命令

### `/clean-merged`
清理所有已經 merged 的本地分支（包括透過 squash merge 合併的分支）。

**功能**:
- ✅ 檢查所有本地分支的 PR 狀態
- ✅ 自動清理已 merged 的分支
- ✅ 處理 worktree 關聯的分支
- ✅ 支援 GitHub 的 "Squash and merge" 策略
- ✅ 只刪除有 merged PR 的分支

**使用場景**:
- 定期清理已完成的 feature branches
- PR 已經 merged 但本地分支還在
- 使用 squash merge 後的清理

**用法**:
```
/clean-merged
```

### `/clean-gone`
增強版的 gone 分支清理命令。

**功能**:
- ✅ 清理標記為 [gone] 的分支（遠端已刪除）
- ✅ 可選：同時清理所有 merged PR 的分支
- ✅ 提供多種清理策略選項
- ✅ 更詳細的預覽和確認流程

**使用場景**:
- 遠端分支已被刪除
- 想要更彈性的清理選項
- 需要同時處理 [gone] 和 merged 分支

**用法**:
```
/clean-gone
```

### `/verify-deploy`
部署後結構化驗證。

**功能**:
- ✅ Health check（backend + frontend）
- ✅ API smoke test
- ✅ CORS 驗證
- ✅ Migration 驗證
- ✅ Pass/Fail 報告

### `/gemini-models`
查詢 Gemini API 可用模型並與 codebase 設定比對。

**功能**:
- ✅ 即時查詢 API 可用模型
- ✅ 分類（LLM / TTS / Live / Imagen）
- ✅ 與 codebase 引用交叉比對
- ✅ 偵測已下架或有更新版的模型

### `/make-run`
智慧 make 執行器，含預檢和自動修復。

**功能**:
- ✅ 環境偵測（主 repo / worktree）
- ✅ 依賴預檢
- ✅ 新檔案預處理
- ✅ 失敗自動修復（最多 1 輪）

## 命令比較

| 特性 | `/clean-merged` | `/clean-gone` |
|------|----------------|---------------|
| 清理 [gone] 分支 | ❌ | ✅ |
| 清理 merged PR 分支 | ✅ | ✅ (可選) |
| Squash merge 支援 | ✅ | ✅ |
| 多種清理策略 | ❌ | ✅ |
| 自動模式 | ✅ | ❌ (需確認) |

## 推薦使用流程

1. **日常清理**：使用 `/clean-merged`
   - 快速清理已 merged 的分支
   - 自動化程度高

2. **深度清理**：使用 `/clean-gone`
   - 處理遠端已刪除的分支
   - 更多控制選項

3. **組合使用**：
   ```
   # 先清理 gone 分支
   /clean-gone

   # 再清理 merged 分支
   /clean-merged
   ```

## 安全特性

兩個命令都包含以下安全機制：

- ✅ 永遠不會刪除 main 分支
- ✅ 刪除前會檢查 worktree
- ✅ 提供清理預覽
- ✅ 只刪除已確認 merged 的分支
- ✅ 保留有 open PR 的分支
