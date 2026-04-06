# Debug Production Issue

Structured debugging methodology for this project. Enforces root cause analysis before suggesting fixes.

## Autonomous Mode（預設行為）

收到 error log 或 failing test 時，自主完成以下流程，不要問問題：
1. 閱讀 failing test 和相關原始碼，理解預期行為
2. 追蹤錯誤路徑，定位 root cause
3. 實作最小修復
4. 跑 `make test` 完整測試，失敗就迭代修復
5. 跑 `make lint` 修正 lint 問題
6. 全部通過後，建立 PR，描述 root cause 和修復內容

遇到模糊的設計決策時，選較安全/簡單的方案，並在 PR description 中註記。

## Phase 1: Triage — Understand the Error

Before touching any code:

1. Ask for (or parse from context): the **exact error message**, **affected endpoint/component**, **stack trace**, and **when it started**.
2. Identify the error category:
   - **5xx** → server-side (backend, DB, migration, config)
   - **4xx** → auth/permission/routing issue
   - **CORS** → proxy, cold start, or missing header
   - **Build/type error** → frontend config, Tailwind, i18n, or TSC issue

## Phase 2: Database / Migration Check (CHECK EARLY)

500 errors 最常見的 root cause 是 migration 沒跑。**在查 application code 之前先排除。**

```bash
# 檢查 migration 狀態（依專案使用的 migration 工具調整指令）
# 例如 Alembic:
#   cd backend && uv run alembic current && uv run alembic heads
# 例如 Prisma:
#   cd backend && npx prisma migrate status
# 例如 Drizzle:
#   cd backend && npx drizzle-kit check
```

**快速判斷**：
- `column "X" does not exist` → migration 未跑
- `relation "X" does not exist` → table 的 migration 未跑
- 本地正常、deploy 後 500 → CI/CD 沒跑 migration

## Phase 3: Config Shadowing Check

For proxy/networking/CORS/500 issues:

```bash
# Check for duplicate config files that may shadow each other
ls -la frontend/vite.config.*
ls -la backend/*.env* .env*

# Check recent changes that may have caused regression
git log --oneline -10
git diff HEAD~5 -- frontend/vite.config.ts backend/src/main.py
```

**Common shadow issues:**
- `vite.config.js` shadowing `vite.config.ts`
- `.env.local` overriding `.env` (not visible in git diff)
- Docker environment missing variables that work locally

## Phase 4: Infrastructure Consistency Check

For port changes, env var changes, or deployment issues:

```bash
# Check all locations where this value is configured
grep -r "PORT\|8000\|8888" backend/ frontend/ --include="*.py" --include="*.ts" --include="*.env*" Dockerfile* docker-compose.yml
```

Always verify these locations are consistent:
- Backend app config (e.g., `backend/src/main.py`)
- Frontend proxy config (e.g., `frontend/vite.config.ts`)
- `Dockerfile` and `docker-compose.yml`
- Deployment config (CI/CD env vars)
- OAuth redirect URIs (if applicable)

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
# Run full test suite
make test

# Test the specific endpoint/behavior that was broken
curl -v http://localhost:8888/api/v1/<affected-endpoint>
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
