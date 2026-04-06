# Verify Deployment — 部署後驗證

部署後執行結構化驗證，確保服務正常運作。避免過早宣告成功。

需要使用者提供：`$ARGUMENTS` 格式為 `<frontend-url> [backend-url]`
如果只提供 frontend URL，backend URL 預設為同 host 的 `/api/v1`。

## Step 1: Health Check

```bash
# Backend health
curl -sf <backend-url>/api/v1/health | head -100
echo "Backend: $?"

# Frontend reachable
curl -sf -o /dev/null -w "HTTP %{http_code}" <frontend-url>
echo "Frontend: $?"
```

- ✅ Backend 回 200 + JSON
- ✅ Frontend 回 200

## Step 2: API Smoke Test

```bash
# 未認證 endpoint 應回 200
curl -sf <backend-url>/api/v1/health

# 需認證 endpoint 應回 401（不是 500）
curl -s -o /dev/null -w "%{http_code}" <backend-url>/api/v1/tts/providers
```

- ✅ Public endpoint → 200
- ✅ Protected endpoint → 401（不是 500、502、503）
- ❌ 500 → 表示 server error，需要查 log

## Step 3: CORS Header 驗證

```bash
curl -s -I -X OPTIONS <backend-url>/api/v1/health \
  -H "Origin: <frontend-url>" \
  -H "Access-Control-Request-Method: GET" \
  | grep -i "access-control"
```

- ✅ `Access-Control-Allow-Origin` 包含 frontend URL
- ❌ 缺少 CORS headers → 檢查 backend CORS config 和 `CORS_ORIGINS` 環境變數

## Step 4: Migration 驗證

測試最近 migrate 過的 table 相關 endpoint：

```bash
# 如果最近有 migration，測試相關 endpoint 能回資料（不是 500）
curl -s -o /dev/null -w "%{http_code}" <backend-url>/api/v1/<recent-migrated-endpoint>
```

## Step 5: Pass/Fail Report

```
=== Deployment Verification ===
Health (backend):  ✅ 200 OK
Health (frontend): ✅ 200 OK
Auth gate:         ✅ 401 (not 500)
CORS:              ✅ headers present
Migration:         ✅ endpoints responding
────────────────────────────────
Verdict: ✅ PASS — deployment looks healthy
```

如果任何項目 ❌，列出具體問題和建議的下一步（查 log、rollback、hotfix）。
