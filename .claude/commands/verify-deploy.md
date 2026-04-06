# Verify Apply — Policy / Script 套用後驗證

執行 `make apply-policies`、`make install` 或腳本變更後，執行結構化驗證確保 sandbox 正常運作。避免過早宣告成功。

## Step 1: Sandbox 狀態確認

```bash
openshell sandbox list
```

- ✅ `claude-dev` 和 `claw-agent` 狀態均為 `running`
- ❌ 任一 sandbox `stopped` → 執行 `openshell sandbox start <name>` 後繼續

## Step 2: Policy 生效確認

```bash
# 確認 policy 已套用（顯示目前 active policy）
openshell policy get claude-dev
openshell policy get claw-agent
```

- ✅ 回傳 policy 名稱和 hash 與剛套用的一致
- ❌ hash 不符或 policy 為空 → 重跑 `make apply-policies`

## Step 3: Deny Log 檢查（無誤報）

```bash
openshell logs claude-dev --since 5m | grep "action=deny"
openshell logs claw-agent --since 5m | grep "action=deny"
```

- ✅ 無 `action=deny` 或 deny 的 host 確實不在白名單內（預期行為）
- ❌ 預期可用的 host 被 deny → 檢查 policy YAML 的 `endpoints` 設定

## Step 4: 隔離驗證

```bash
make verify
```

- ✅ 所有 isolation check 通過
- ❌ 任一 check 失敗 → 查看 `make verify` 輸出定位問題

## Step 5: Pass/Fail Report

```
=== Apply Verification ===
Sandboxes:    ✅ claude-dev running, claw-agent running
Policies:     ✅ claude_dev_policy applied, claw_agent_policy applied
Deny logs:    ✅ no unexpected denies
Isolation:    ✅ make verify passed
────────────────────────────────
Verdict: ✅ PASS — changes applied and sandboxes healthy
```

如果任何項目 ❌，列出具體問題和建議的下一步（查 log、重套 policy、重啟 sandbox）。
