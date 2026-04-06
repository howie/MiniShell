#!/bin/bash
# apply-policies.sh — 套用 policies/ 目錄下的 YAML 到對應 sandbox
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

# 找到專案根目錄（此腳本所在的 scripts/ 的上一層）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

CLAUDE_POLICY="$PROJECT_ROOT/policies/claude_dev_policy.yaml"
CLAW_POLICY="$PROJECT_ROOT/policies/claw_agent_policy.yaml"

# ── 確認前置條件 ──────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "openshell 未安裝，請先執行 make install-base" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

# ── 套用 Claude sandbox policy ────────────────────────────────────────────────
echo ""
echo "── Claude Code sandbox policy ───────────────────────"
if openshell sandbox list 2>/dev/null | grep -q "claude-dev"; then
  if [ -f "$CLAUDE_POLICY" ]; then
    warn "套用 $CLAUDE_POLICY → claude-dev..."
    openshell policy set claude-dev --policy "$CLAUDE_POLICY" --wait
    info "claude-dev policy 套用完成"
  else
    echo "找不到 $CLAUDE_POLICY" >&2
    exit 1
  fi
else
  warn "Sandbox 'claude-dev' 不存在，略過（執行 make setup-claude 建立）"
fi

# ── 套用 OpenClaw sandbox policy ──────────────────────────────────────────────
echo ""
echo "── OpenClaw sandbox policy ──────────────────────────"
if openshell sandbox list 2>/dev/null | grep -q "claw-agent"; then
  if [ -f "$CLAW_POLICY" ]; then
    warn "套用 $CLAW_POLICY → claw-agent..."
    openshell policy set claw-agent --policy "$CLAW_POLICY" --wait
    info "claw-agent policy 套用完成"
  else
    echo "找不到 $CLAW_POLICY" >&2
    exit 1
  fi
else
  warn "Sandbox 'claw-agent' 不存在，略過（執行 make setup-claw 建立）"
fi

# ── 套用 Quick OpenClaw sandbox policy（選配）───────────────────────────────
QUICK_POLICY="$PROJECT_ROOT/policies/claw_ollama_gemma4_policy.yaml"
if openshell sandbox list 2>/dev/null | grep -q "claw-ollama-gemma4"; then
  echo ""
  echo "── Quick OpenClaw sandbox policy ────────────────────"
  if [ -f "$QUICK_POLICY" ]; then
    warn "套用 $QUICK_POLICY → claw-ollama-gemma4..."
    openshell policy set claw-ollama-gemma4 --policy "$QUICK_POLICY" --wait
    info "claw-ollama-gemma4 policy 套用完成"
  else
    warn "找不到 ${QUICK_POLICY}（claw-ollama-gemma4 sandbox 存在但 policy 檔案遺失）"
  fi
fi

echo ""
info "Policy 套用完成！"
echo "  確認方式："
echo "    openshell policy get claude-dev"
echo "    openshell policy get claw-agent"
