# Manual Test — 一鍵啟動 yibi-mvp 開發環境

按照以下步驟依序執行，啟動完整的開發環境進行手動測試。

---

## Step 1: 清除舊 process

Kill 佔用 port 8000 (backend) 和 5173 (frontend) 的舊 process：

```bash
lsof -ti:8000 | xargs kill 2>/dev/null || true
lsof -ti:5173 | xargs kill 2>/dev/null || true
```

---

## Step 2: 確認 Database 與 Redis

策略：共用 voice-lab 的 Docker 容器（postgres:16 在 5432，redis:7 在 6379）。

確認 postgres 和 redis 正在運行：

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "postgres|redis"
```

如果沒有運行，嘗試啟動：

```bash
docker start $(docker ps -a --format "{{.Names}}" | grep postgres) 2>/dev/null || true
docker start $(docker ps -a --format "{{.Names}}" | grep redis) 2>/dev/null || true
```

在既有 postgres 中建立 `yibi` database 和 user（如果不存在）。
注意：voice-lab 的 superuser 是 `voicelab`，需指定 `-d voicelab_dev` 來連接：

```bash
docker exec -i voice-lab-postgres psql -U voicelab -d voicelab_dev -c "SELECT 1 FROM pg_roles WHERE rolname='yibi'" | grep -q 1 || \
  docker exec -i voice-lab-postgres psql -U voicelab -d voicelab_dev -c "CREATE USER yibi WITH PASSWORD 'yibi';"

docker exec -i voice-lab-postgres psql -U voicelab -d voicelab_dev -c "SELECT 1 FROM pg_database WHERE datname='yibi'" | grep -q 1 || \
  docker exec -i voice-lab-postgres psql -U voicelab -d voicelab_dev -c "CREATE DATABASE yibi OWNER yibi;"
```

---

## Step 3: 建立 `.env`

如果 `backend/.env` 不存在，從 `.env.example` 複製並填入測試用值：

```bash
if [ ! -f backend/.env ]; then
  cp backend/.env.example backend/.env
  sed -i '' 's/your-secret-key-at-least-32-characters-long/dev-test-secret-key-for-local-development-only-32chars/' backend/.env
  sed -i '' 's/your-google-client-id.apps.googleusercontent.com/fake-google-client-id-for-dev/' backend/.env
  echo "✓ backend/.env created from .env.example"
else
  echo "✓ backend/.env already exists"
fi
```

---

## Step 4: 執行 Alembic Migration

```bash
cd backend && uv run alembic upgrade head
```

如果 migration 版本檔不存在，先產生：

```bash
cd backend && uv run alembic revision --autogenerate -m "initial tables"
cd backend && uv run alembic upgrade head
```

---

## Step 5: 背景啟動 Backend

```bash
cd backend && uv run uvicorn src.main:app --reload --host 0.0.0.0 --port 8000 &
```

等待 backend 啟動（最多 10 秒）：

```bash
for i in $(seq 1 10); do
  curl -s http://localhost:8000/api/v1/health > /dev/null 2>&1 && break
  sleep 1
done
```

---

## Step 6: 背景啟動 Frontend

```bash
cd frontend && bun dev &
```

等待 frontend 啟動（最多 10 秒）：

```bash
for i in $(seq 1 10); do
  curl -s http://localhost:5173 > /dev/null 2>&1 && break
  sleep 1
done
```

---

## Step 7: 驗證

### Health Check

```bash
curl -s http://localhost:8000/api/v1/health | python3 -m json.tool
```

預期：`{"status": "ok"}`

### 註冊測試

```bash
curl -s -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "TestPass123!", "display_name": "Test User"}' | python3 -m json.tool
```

預期：201 + JWT token

### 登入測試

```bash
curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "TestPass123!"}' | python3 -m json.tool
```

預期：200 + JWT token

### 前端頁面

用瀏覽器開啟 http://localhost:5173 確認看到登入頁面。

---

## Cleanup

測試完成後，清理所有背景 process：

```bash
lsof -ti:8000 | xargs kill 2>/dev/null || true
lsof -ti:5173 | xargs kill 2>/dev/null || true
```

如果要清除測試資料，可以 drop database：

```bash
docker exec -i voice-lab-postgres psql -U voicelab -d voicelab_dev -c "DROP DATABASE IF EXISTS yibi;"
```
