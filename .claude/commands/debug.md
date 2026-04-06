# Debug Production Issue

Structured debugging methodology for this project. Enforces root cause analysis before suggesting fixes.

## Autonomous Mode（預設行為）

收到 error log 或問題描述時，自主完成以下流程，不要問問題：
1. 閱讀相關腳本和設定，理解預期行為
2. 追蹤錯誤路徑，定位 root cause
3. 實作最小修復
4. 跑 `make verify` 驗證隔離正常，失敗就迭代修復
5. 全部通過後，建立 PR，描述 root cause 和修復內容

遇到模糊的設計決策時，選較安全/簡單的方案，並在 PR description 中註記。

## Phase 1: Triage — Understand the Error

Before touching any code:

1. Ask for (or parse from context): the **exact error message**, **affected component**, **log output**, and **when it started**.
2. Identify the error category:
   - **Policy deny** → OpenShell proxy 阻擋出站流量（`action=deny` 在 logs）
   - **Sandbox not running** → openshell sandbox 狀態異常
   - **Credential missing** → OAuth token 或 API key 未注入
   - **Script error** → `set -euo pipefail` 觸發的 bash 錯誤

## Phase 2: Sandbox / Policy State Check (CHECK EARLY)

大多數問題的 root cause 是 sandbox 狀態或 policy 設定。**在查腳本邏輯之前先排除。**

```bash
# 檢查 sandbox 狀態
openshell sandbox list

# 檢查 deny log（policy 擋住的請求）
openshell logs claude-dev --since 10m | grep "action=deny"
openshell logs claw-agent --since 10m | grep "action=deny"

# 驗證隔離
make verify
```

**快速判斷**：
- `action=deny` 在 log → policy YAML 缺少該 host/method 白名單
- sandbox 狀態 `stopped` → 執行 `openshell sandbox start <name>`
- `make verify` 失敗 → credential 未注入或 landlock 設定異常

## Phase 3: Config Shadowing Check

For policy/credential/networking issues:

```bash
# Check for conflicting policy files
ls -la policies/

# Check recent changes that may have caused regression
git log --oneline -10
git diff HEAD~5 -- policies/ scripts/ .env
```

**Common shadow issues:**
- `.env.local` overriding `.env` (not visible in git diff)
- Policy YAML `version` 欄位型別錯誤（必須是整數，不是字串）
- `binaries` 欄位遺漏導致 proxy 回 403

## Phase 4: Infrastructure Consistency Check

For policy or credential issues:

```bash
# Check all locations where a value is configured
grep -r "GEMINI_API_KEY\|CLAUDE" scripts/ policies/ .env.example

# Check openshell provider list
openshell provider list
```

Always verify these locations are consistent:
- `policies/claude_dev_policy.yaml` 和 `policies/claw_agent_policy.yaml`
- `scripts/setup-claude.sh` 和 `scripts/setup-claw.sh`（credential 注入邏輯）
- `.env` / `.env.example`（API key 設定）

## Phase 5: Apply Fix

Only after identifying root cause:
1. Apply the **minimal** fix.
2. If it's a migration: write and run the migration.
3. If it's a config: update ALL locations (see Phase 3).

## Phase 6: Verify — User-Facing Behavior (CRITICAL)

**Do NOT declare success based on error code change alone.**
- A 401 replacing a 500 is NOT a fix.
- Verify the actual user-facing behavior works end-to-end.

```bash
# 驗證隔離與 sandbox 狀態
make verify

# 測試特定 sandbox 的連線能力（例如確認 policy 允許的 host 可連）
openshell sandbox connect claude-dev -- curl -s https://api.anthropic.com/health 2>/dev/null || echo "check policy"
```

Only report success after confirming the original problem is resolved.

## Phase 7: Prevent Recurrence

After fixing, note:
- What was the root cause?
- What check would have caught this earlier?
- Should a test be added to prevent regression?

如已在自主模式下完成修復，建立 PR：
- `git add` 修復相關檔案（排除 debug logs、.env 變更）
- 使用 conventional commit format：`fix(scope): 簡短描述`
- `gh pr create` 並在 body 中包含 root cause 分析和修復說明
