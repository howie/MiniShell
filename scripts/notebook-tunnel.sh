#!/usr/bin/env bash
# notebook-tunnel.sh
# 在筆電上建立 SSH tunnel 到 Mac Mini，透過 localhost 存取 OpenClaw Dashboard。
# 目的：瀏覽器 Secure Context 要求（Web Crypto API 需要 HTTPS 或 localhost）。
#
# 使用方式：在筆電上執行（不要在 Mac Mini 上執行）
#   make notebook-tunnel
#   或直接 bash scripts/notebook-tunnel.sh

set -euo pipefail

MINI_HOST="${MINI_HOST:-doxa@192.168.1.29}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/doxa.agent_github}"

# 防呆：偵測是否在 Mac Mini 上執行
MINI_IP="${MINI_HOST##*@}"
LOCAL_IPS=$(ifconfig 2>/dev/null | grep 'inet ' | awk '{print $2}' || ip addr 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
if echo "${LOCAL_IPS}" | grep -qF "${MINI_IP}"; then
    echo "錯誤：這個指令必須在筆電上執行，不能在 Mac Mini 上執行。" >&2
    echo "" >&2
    echo "  Mac Mini IP（${MINI_IP}）是本機 IP，無法對自己建 tunnel。" >&2
    echo "" >&2
    echo "  請在筆電上執行：" >&2
    echo "    bash scripts/notebook-tunnel.sh" >&2
    echo "" >&2
    echo "  或直接在筆電上執行 SSH 指令：" >&2
    echo "    ssh -fN -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${MINI_HOST}" >&2
    exit 1
fi

echo "OpenClaw Dashboard tunnel (筆電 → Mac Mini)"
echo "  Mac Mini: ${MINI_HOST}"
echo "  Port:     ${GATEWAY_PORT}"
echo ""

# 驗證 SSH key
if [[ ! -f "${SSH_KEY}" ]]; then
    echo "錯誤：SSH key 不存在：${SSH_KEY}" >&2
    echo "  請設定 SSH_KEY 環境變數指向正確的金鑰路徑" >&2
    exit 1
fi

# 停止現有佔用 port 的 ssh 程序
if lsof -ti :"${GATEWAY_PORT}" &>/dev/null; then
    echo "停止舊的 tunnel（port ${GATEWAY_PORT} 已被佔用）..."
    STALE_PIDS=$(lsof -ti :"${GATEWAY_PORT}" -c ssh 2>/dev/null || true)
    if [[ -n "${STALE_PIDS}" ]]; then
        kill ${STALE_PIDS} 2>/dev/null || true
    else
        echo "  警告：port ${GATEWAY_PORT} 被非 SSH 程序佔用，跳過清理" >&2
    fi
    sleep 1
fi

# 建立 SSH tunnel
echo "建立 SSH tunnel: localhost:${GATEWAY_PORT} → ${MINI_HOST}:${GATEWAY_PORT}"
if ! ssh -fN \
    -i "${SSH_KEY}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=10 \
    -L "${GATEWAY_PORT}:localhost:${GATEWAY_PORT}" \
    "${MINI_HOST}"; then
    echo "錯誤：SSH tunnel 建立失敗" >&2
    echo "  主機：${MINI_HOST}，key：${SSH_KEY}" >&2
    echo "  請確認：" >&2
    echo "    1. Mac Mini 可連線（ping ${MINI_IP}）" >&2
    echo "    2. SSH key 已授權（cat ~/.ssh/doxa.agent_github.pub | ssh ${MINI_HOST} 'cat >> ~/.ssh/authorized_keys'）" >&2
    echo "    3. Mac Mini 已開啟遠端登入（系統設定 → 一般 → 共享 → 遠端登入）" >&2
    exit 1
fi

# 清理 trap：tunnel 啟動後如有失敗，自動停止
TUNNEL_PID=$(lsof -ti :"${GATEWAY_PORT}" -c ssh 2>/dev/null | head -1 || true)
cleanup() {
    if [[ -n "${TUNNEL_PID:-}" ]] && kill -0 "${TUNNEL_PID}" 2>/dev/null; then
        kill "${TUNNEL_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

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
        if ! lsof -ti :"${GATEWAY_PORT}" &>/dev/null; then
            echo "錯誤：SSH tunnel 已斷線（本地 port ${GATEWAY_PORT} 未監聽）" >&2
        else
            echo "錯誤：Dashboard 無回應，請確認 Mac Mini 已執行 make dashboard" >&2
        fi
        exit 1
    fi
done

# tunnel 建立成功，取消 cleanup trap
trap - EXIT INT TERM

# 取得 dashboard token
echo "取得 dashboard token..."
SSH_OUTPUT=$(ssh \
    -i "${SSH_KEY}" \
    -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR \
    -o ConnectTimeout=10 \
    "${MINI_HOST}" \
    "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR openshell-claw-agent 'openclaw dashboard 2>/dev/null'" \
    2>&1) && SSH_OK=true || SSH_OK=false

if [[ "${SSH_OK}" == "true" ]]; then
    TOKEN=$(printf '%s' "${SSH_OUTPUT}" | grep -o 'token=[^&# ]*' | head -1 | sed 's/token=//' || true)
else
    echo "  警告：無法從 sandbox 取得 token（SSH 錯誤）" >&2
    TOKEN=""
fi

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
