#!/usr/bin/env bash
# notebook-tunnel.sh
# 在筆電上建立 SSH tunnel 到 Mac Mini，透過 localhost 存取 OpenClaw Dashboard。
# 目的：瀏覽器 Secure Context 要求（Web Crypto API 需要 HTTPS 或 localhost）。
#
# 使用方式：在筆電上執行
#   make notebook-tunnel                                # 預設連 claw-agent (port 18789)
#   make notebook-tunnel SANDBOX=claw-ollama-gemma4     # 連 quick-claw sandbox (port 18790)
#
# 支援的 sandbox 與對應 port：
#   claw-agent          → localhost:18789
#   claw-ollama-gemma4  → localhost:18790

set -euo pipefail

MINI_HOST="${MINI_HOST:-doxa@192.168.1.29}"
SANDBOX="${SANDBOX:-claw-agent}"

# ── Port mapping ──────────────────────────────────────────────────────────────
# 每個 sandbox 的 OpenClaw gateway 都跑在內部 port 18789，
# 用不同的 local port 區分不同 sandbox。
case "${SANDBOX}" in
  claw-agent)
    LOCAL_PORT=18789
    SSH_HOST="openshell-claw-agent"
    ;;
  claw-ollama-gemma4)
    LOCAL_PORT=18790
    SSH_HOST="openshell-claw-ollama-gemma4"
    ;;
  *)
    echo "不支援的 sandbox: ${SANDBOX}" >&2
    echo "支援的 sandbox: claw-agent, claw-ollama-gemma4" >&2
    exit 1
    ;;
esac

GATEWAY_PORT=18789  # sandbox 內部的 gateway port（所有 sandbox 都一樣）

echo "OpenClaw Dashboard tunnel (筆電 → Mac Mini → ${SANDBOX})"
echo "  Mac Mini:  ${MINI_HOST}"
echo "  Sandbox:   ${SANDBOX}"
echo "  Local URL: http://localhost:${LOCAL_PORT}/"
echo ""

# ── 1. 確保 Mac Mini 有 sandbox 的 SSH config ────────────────────────────────
echo "確認 Mac Mini 上的 SSH config..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "${MINI_HOST}" "
    if ! grep -q '${SSH_HOST}' ~/.ssh/config 2>/dev/null; then
        echo '匯入 ${SSH_HOST} SSH config...'
        openshell sandbox ssh-config ${SANDBOX} >> ~/.ssh/config
    fi
"

# ── 2. 建立 Mac Mini host → sandbox tunnel ───────────────────────────────────
echo "建立 Mac Mini 內部 tunnel（host:${LOCAL_PORT} → ${SANDBOX}:${GATEWAY_PORT}）..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "${MINI_HOST}" "
    # 停掉舊的 tunnel（同 port）
    lsof -ti :${LOCAL_PORT} 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
    # 建立 host → sandbox tunnel
    ssh -fN \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -L 0.0.0.0:${LOCAL_PORT}:127.0.0.1:${GATEWAY_PORT} \
        ${SSH_HOST}
"

# ── 3. 停止本機佔用 port 的程序 ──────────────────────────────────────────────
if lsof -ti :"${LOCAL_PORT}" &>/dev/null; then
    echo "停止本機舊的 tunnel（port ${LOCAL_PORT}）..."
    lsof -ti :"${LOCAL_PORT}" | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# ── 4. 建立筆電 → Mac Mini tunnel ───────────────────────────────────────────
echo "建立 SSH tunnel: localhost:${LOCAL_PORT} → ${MINI_HOST}:${LOCAL_PORT}"
ssh -fN \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -L "${LOCAL_PORT}:localhost:${LOCAL_PORT}" \
    "${MINI_HOST}"

# ── 5. 等待 tunnel 就緒 ─────────────────────────────────────────────────────
echo -n "等待 tunnel 就緒..."
for i in $(seq 1 10); do
    if curl -s -o /dev/null --connect-timeout 1 "http://localhost:${LOCAL_PORT}/" 2>/dev/null; then
        echo " OK"
        break
    fi
    echo -n "."
    sleep 1
    if [[ $i -eq 10 ]]; then
        echo ""
        echo "錯誤：tunnel 逾時，請確認 sandbox ${SANDBOX} 的 gateway 已啟動"
        echo "  進入 sandbox：openshell sandbox connect ${SANDBOX}"
        echo "  啟動 gateway：openclaw gateway run &"
        exit 1
    fi
done

# ── 6. 取得 dashboard token ──────────────────────────────────────────────────
echo "取得 dashboard token..."
TOKEN=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    "${MINI_HOST}" \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ${SSH_HOST} 'openclaw dashboard 2>/dev/null'" \
    2>/dev/null | grep -o 'token=[^&# ]*' | head -1 | sed 's/token=//' || true)

echo ""
echo "────────────────────────────────────────"
echo "Dashboard 已就緒（Secure Context：localhost）"
echo "  Sandbox: ${SANDBOX}"
echo ""
if [[ -n "${TOKEN}" ]]; then
    echo "  http://localhost:${LOCAL_PORT}/#token=${TOKEN}"
else
    echo "  http://localhost:${LOCAL_PORT}/"
    echo ""
    echo "  Token 查詢失敗，請手動執行："
    echo "  ssh ${MINI_HOST} \"ssh ${SSH_HOST} 'openclaw dashboard'\""
fi
echo "────────────────────────────────────────"
