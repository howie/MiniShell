# Changelog

## 2026-03-29

### 專案整理重構

- 建立目錄結構（`policies/`、`docs/`、`scripts/`）
- Policy YAML 移至 `policies/` 目錄
- `install_guide.md` 拆分為三份文件：
  - `docs/installation.md` — 安裝手冊（Phase 0~8 + 疑難排解）
  - `docs/usage.md` — 日常操作指南（Phase 9~10）
  - `docs/learning.md` — 概念說明、架構圖、Policy YAML 詳解
- 新增 `Makefile`（`make install` / `make setup-claude` / `make setup-claw` 等）
- 新增自動化腳本（`scripts/`）
- 新增 `README.md`

---

## 2026-03-28

### 初始建立（v5，實測修正版）

- 建立 `install_guide.md`：Mac Mini M4 上建置 OpenShell 雙 Sandbox 完整指南
- 建立 `claude_dev_policy.yaml`：Claude Code sandbox 網路 + 檔案系統 policy（v8，實測驗證）
- 建立 `claw_agent_policy.yaml`：OpenClaw sandbox policy

**重要修正（實測發現）：**
- Policy YAML `enforcement` 欄位位置：應在 endpoint 層級，不是 policy 層級
- `binaries` 欄位為必填，省略會導致 proxy 回 403
- Claude Code binary 路徑需同時列三條（全域、symlink、版本號 glob）
- Live sandbox 不支援移除已有的 `filesystem_policy` 路徑
- `git clone` 失敗需加 `GIT_SSL_CAINFO`（proxy TLS termination）
- Marketplace race condition 需手動 pre-clone 繞過
