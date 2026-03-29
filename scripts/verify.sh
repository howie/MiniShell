#!/bin/bash
# verify.sh — 驗證兩個 sandbox 確實互相隔離（Phase 8）
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
fail()  { echo -e "${RED}[FAIL]${NC} $1"; FAILED=1; }
warn()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }

FAILED=0

# ── 確認 sandbox 存在 ─────────────────────────────────────────────────────────
echo ""
echo "── 前置檢查 ─────────────────────────────────────────"

if ! command -v openshell &>/dev/null; then
  fail "openshell 未安裝"
  exit 1
fi

HAS_CLAUDE=0
HAS_CLAW=0
openshell sandbox list 2>/dev/null | grep -q "claude-dev" && HAS_CLAUDE=1
openshell sandbox list 2>/dev/null | grep -q "claw-agent" && HAS_CLAW=1

if [[ $HAS_CLAUDE -eq 0 ]]; then
  warn "Sandbox 'claude-dev' 不存在，略過相關測試"
fi
if [[ $HAS_CLAW -eq 0 ]]; then
  warn "Sandbox 'claw-agent' 不存在，略過相關測試"
fi

if [[ $HAS_CLAUDE -eq 0 && $HAS_CLAW -eq 0 ]]; then
  echo "兩個 sandbox 都不存在，請先執行 make setup-claude 和 make setup-claw" >&2
  exit 1
fi

# ── 檔案系統隔離 ──────────────────────────────────────────────────────────────
echo ""
echo "── 檔案系統隔離 ─────────────────────────────────────"

if [[ $HAS_CLAUDE -eq 1 && $HAS_CLAW -eq 1 ]]; then
  # 在 claude-dev 寫入測試檔案
  TEST_CONTENT="verify-$(date +%s)"
  openshell sandbox connect claude-dev -- bash -c "echo '$TEST_CONTENT' > /sandbox/verify_test.txt" 2>/dev/null
  WRITTEN=$(openshell sandbox connect claude-dev -- bash -c "cat /sandbox/verify_test.txt 2>/dev/null" 2>/dev/null || echo "")

  # 在 claw-agent 嘗試讀取
  VISIBLE=$(openshell sandbox connect claw-agent -- bash -c "cat /sandbox/verify_test.txt 2>/dev/null" 2>/dev/null || echo "")

  if [[ "$WRITTEN" == "$TEST_CONTENT" && -z "$VISIBLE" ]]; then
    pass "claude-dev 寫入的檔案在 claw-agent 中不可見"
  elif [[ -z "$WRITTEN" ]]; then
    warn "無法在 claude-dev 建立測試檔案（可能 policy 問題）"
  else
    fail "claw-agent 可以讀取 claude-dev 的檔案！隔離失敗"
  fi

  # 清除測試檔案
  openshell sandbox connect claude-dev -- bash -c "rm -f /sandbox/verify_test.txt" 2>/dev/null || true
else
  warn "需要兩個 sandbox 才能測試檔案系統隔離"
fi

# ── Credential 隔離 ───────────────────────────────────────────────────────────
echo ""
echo "── Credential 隔離 ──────────────────────────────────"

if [[ $HAS_CLAUDE -eq 1 ]]; then
  GOOGLE_IN_CLAUDE=$(openshell sandbox connect claude-dev -- bash -c "echo \$GOOGLE_API_KEY" 2>/dev/null || echo "")
  if [[ -z "$GOOGLE_IN_CLAUDE" ]]; then
    pass "claude-dev sandbox 中沒有 GOOGLE_API_KEY"
  else
    fail "claude-dev sandbox 中發現 GOOGLE_API_KEY（應隔離）"
  fi
fi

if [[ $HAS_CLAW -eq 1 ]]; then
  GOOGLE_IN_CLAW=$(openshell sandbox connect claw-agent -- bash -c "echo \$GOOGLE_API_KEY" 2>/dev/null || echo "")
  if [[ -n "$GOOGLE_IN_CLAW" ]]; then
    pass "claw-agent sandbox 中存在 GOOGLE_API_KEY"
  else
    warn "claw-agent sandbox 中沒有 GOOGLE_API_KEY（provider 可能未設定）"
  fi
fi

# ── Gateway 狀態 ──────────────────────────────────────────────────────────────
echo ""
echo "── Gateway 狀態 ─────────────────────────────────────"
if openshell status 2>/dev/null | grep -q "Connected"; then
  pass "Gateway 在線"
else
  fail "Gateway 未連線"
fi

# ── 結果摘要 ──────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────"
if [[ $FAILED -eq 0 ]]; then
  echo -e "${GREEN}所有驗證通過！${NC}"
else
  echo -e "${RED}有驗證項目失敗，請檢查上方輸出。${NC}"
  exit 1
fi
