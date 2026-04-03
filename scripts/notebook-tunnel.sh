#!/usr/bin/env bash
# notebook-tunnel.sh
# 在筆電上建立 SSH tunnel 到 Mac Mini，透過 localhost 存取 OpenClaw Dashboard。
# 目的：瀏覽器 Secure Context 要求（Web Crypto API 需要 HTTPS 或 localhost）。
#
# 使用方式：在筆電上執行
#   make notebook-tunnel
#   或直接 bash scripts/notebook-tunnel.sh

set -euo pipefail

MINI_HOST="${MINI_HOST:-doxa@192.168.1.29}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"

echo "OpenClaw Dashboard tunnel (筆電 → Mac Mini)"
echo "  Mac Mini: ${MINI_HOST}"
echo "  Port:     ${GATEWAY_PORT}"
echo ""

# 停止現有佔用 port 的程序
if lsof -ti :"${GATEWAY_PORT}" &>/dev/null; then
    echo "停止舊的 tunnel（port ${GATEWAY_PORT} 已被佔用）..."
    lsof -ti :"${GATEWAY_PORT}" | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# 建立 SSH tunnel
echo "建立 SSH tunnel: localhost:${GATEWAY_PORT} → ${MINI_HOST}:${GATEWAY_PORT}"
ssh -fN \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -L "${GATEWAY_PORT}:localhost:${GATEWAY_PORT}" \
    "${MINI_HOST}"

# 等待 tunnel 就緒
echo -n "等待 tunnel 就緒..."
for i in $(seq 1 10); do
    if curl -s -o /dev/null --connect-timeout 1 "http://localhost:${GATEWAY_PORT}/" 2>/dev/null; then
        echo " OK"
        break
    fi
    echo -n "."
    sleep 1
    if [[ $i -eq 10 ]]; then
        echo ""
        echo "錯誤：tunnel 逾時，請確認 Mac Mini Dashboard 已啟動（make dashboard）"
        exit 1
    fi
done

# 取得 dashboard token
echo "取得 dashboard token..."
TOKEN=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "${MINI_HOST}" \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR openshell-claw-agent 'openclaw dashboard 2>/dev/null'" \
    2>/dev/null | grep -o 'token=[^&# ]*' | head -1 | sed 's/token=//' || true)

echo ""
echo "────────────────────────────────────────"
echo "Dashboard 已就緒（Secure Context：localhost）"
echo ""
if [[ -n "${TOKEN}" ]]; then
    echo "  http://localhost:${GATEWAY_PORT}/#token=${TOKEN}"
else
    echo "  http://localhost:${GATEWAY_PORT}/"
    echo ""
    echo "  Token 查詢失敗，請手動執行："
    echo "  ssh ${MINI_HOST} \"ssh openshell-claw-agent 'openclaw dashboard'\""
fi
echo "────────────────────────────────────────"
