#!/bin/bash
set -euo pipefail
cd /sandbox/messaging-bridge
mkdir -p logs
if [ -f bridge.pid ] && kill -0 "$(cat bridge.pid)" 2>/dev/null; then
  echo "[bridge] 已在運行中（PID $(cat bridge.pid)），請先停止後再啟動。"
  exit 1
fi
nohup node src/index.js >> logs/bridge.log 2>&1 &
echo $! > bridge.pid
echo "[bridge] 已啟動，PID: $(cat bridge.pid)"
echo "[bridge] Log: /sandbox/messaging-bridge/logs/bridge.log"
