#!/bin/bash
# measure-channels.sh — 測量 Telegram Channels 端到端延遲
# 從 openshell proxy logs 解析各段請求時間
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

SANDBOX="${1:-claude-dev}"
SINCE="${2:-10m}"

echo -e "${BOLD}Telegram Channels 延遲分析 — sandbox: $SANDBOX, 最近 $SINCE${NC}"
echo "────────────────────────────────────────────────────────"

# 擷取 logs（分開執行以便偵測 openshell 本身失敗）
if ! log_output=$(openshell logs "$SANDBOX" --since "$SINCE" 2>&1); then
  echo "錯誤：openshell logs 指令失敗（sandbox: $SANDBOX）" >&2
  echo "$log_output" >&2
  exit 1
fi

raw=$(echo "$log_output" \
  | grep "action=allow" \
  | grep -E "dst_host=(api\.telegram\.org|api\.anthropic\.com|mcp-proxy\.anthropic\.com)" \
  | grep -oE '\[([0-9]+\.[0-9]+)\].*dst_host=([^ ]+)' \
  | sed 's/\[\([0-9.]*\)\].*dst_host=\([^ ]*\)/\1 \2/' \
  | sort -n || true)

if [[ -z "$raw" ]]; then
  echo "無資料（$SINCE 內無 allow 記錄）"
  exit 0
fi

# 找出每次 Telegram getUpdates → 第一次 Anthropic call 的配對
echo -e "${CYAN}原始時間線：${NC}"
echo "$raw" | while read -r ts host; do
  label=""
  case "$host" in
    api.telegram.org) label="📨 Telegram" ;;
    api.anthropic.com) label="🤖 Anthropic" ;;
    mcp-proxy.anthropic.com) label="🔌 MCP-proxy" ;;
  esac
  printf "  %s  %s\n" "$ts" "$label"
done

echo ""
echo -e "${CYAN}配對分析（Telegram → Anthropic 請求對）：${NC}"

prev_telegram=""
prev_ts=""
request_num=0

while IFS=' ' read -r ts host; do
  if [[ "$host" == "api.telegram.org" ]]; then
    prev_telegram="$ts"
  elif [[ "$host" == "api.anthropic.com" && -n "$prev_telegram" ]]; then
    request_num=$((request_num + 1))
    gap=$(echo "$ts - $prev_telegram" | bc)
    printf "  請求 #%d: Telegram收訊 %.3f → Anthropic %.3f  ${GREEN}延遲: %.1fs${NC}\n" \
      "$request_num" "$prev_telegram" "$ts" "$gap"
    prev_telegram=""  # 消費掉，等下一個 telegram
  fi
done <<< "$raw"

echo ""
echo -e "${YELLOW}說明：${NC}"
echo "  • Telegram→Anthropic 延遲 = MCP channel overhead + Claude 接收時間"
echo "  • 理想值: <2s（目前觀測: ~1s）"
echo "  • Telegram polling interval (bun): ~10-30s（訊息等待時間）"
echo ""
echo -e "${BOLD}完整分析請搭配 openshell logs:${NC}"
echo "  openshell logs $SANDBOX --since $SINCE | grep -E 'telegram|anthropic'"
