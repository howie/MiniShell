#!/bin/bash
# setup-host.sh — 主機層級優化：防火牆、TCP Keepalive、Power Nap
# 解決 Claude Code 在 Mac Mini 上頻繁出現 ConnectionRefused 的問題
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[->]${NC} $1"; }

# ── 檢查 macOS ────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "此腳本僅適用於 macOS。" >&2
  exit 1
fi

echo ""
echo "── 取得 sudo 權限 ───────────────────────────────"
sudo -v
# 在腳本執行期間保持 sudo 存活
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null || true' EXIT

# ── A. macOS Application Firewall ─────────────────────
echo ""
echo "── A. Application Firewall ──────────────────────"

FIREWALL_BIN="/usr/libexec/ApplicationFirewall/socketfilterfw"

if [[ ! -f "$FIREWALL_BIN" ]]; then
  warn "找不到 $FIREWALL_BIN，略過防火牆設定"
  FIREWALL_BIN=""
else
  FIREWALL_STATE=$(sudo "$FIREWALL_BIN" --getglobalstate 2>/dev/null || echo "")
  if echo "$FIREWALL_STATE" | grep -q "enabled"; then
    info "Application Firewall 已啟用"
  else
    warn "Application Firewall 未啟用，略過允許清單設定"
    FIREWALL_BIN=""
  fi
fi

if [[ -n "$FIREWALL_BIN" ]]; then
  # 找到需要加入的 binary 路徑
  BINARIES_TO_ADD=()

  # claude
  if [[ -f "/opt/homebrew/bin/claude" ]]; then
    BINARIES_TO_ADD+=("/opt/homebrew/bin/claude")
  else
    warn "找不到 /opt/homebrew/bin/claude，略過"
  fi

  # bun（支援 asdf / homebrew / 直接安裝）
  BUN_PATH=""
  if command -v asdf &>/dev/null && asdf which bun &>/dev/null 2>&1; then
    BUN_PATH="$(asdf which bun 2>/dev/null)"
  elif [[ -f "/opt/homebrew/bin/bun" ]]; then
    BUN_PATH="/opt/homebrew/bin/bun"
  elif command -v bun &>/dev/null; then
    BUN_PATH="$(command -v bun)"
  fi
  if [[ -n "$BUN_PATH" ]]; then
    BINARIES_TO_ADD+=("$BUN_PATH")
  else
    warn "找不到 bun，略過"
  fi

  # node（支援 asdf / homebrew / 直接安裝）
  NODE_PATH=""
  if command -v asdf &>/dev/null && asdf which node &>/dev/null 2>&1; then
    NODE_PATH="$(asdf which node 2>/dev/null)"
  elif [[ -f "/opt/homebrew/bin/node" ]]; then
    NODE_PATH="/opt/homebrew/bin/node"
  elif command -v node &>/dev/null; then
    NODE_PATH="$(command -v node)"
  fi
  if [[ -n "$NODE_PATH" ]]; then
    BINARIES_TO_ADD+=("$NODE_PATH")
  else
    warn "找不到 node，略過"
  fi

  # 加入防火牆允許清單（冪等：已存在則跳過）
  for bin in "${BINARIES_TO_ADD[@]}"; do
    if sudo "$FIREWALL_BIN" --listapps 2>/dev/null | grep -qF "$bin"; then
      info "$(basename "$bin") 已在允許清單"
    else
      step "新增 $(basename "$bin") 到防火牆允許清單..."
      sudo "$FIREWALL_BIN" --add "$bin" >/dev/null
      sudo "$FIREWALL_BIN" --unblockapp "$bin" >/dev/null
      info "$(basename "$bin") 已加入"
    fi
  done
fi

# ── B. TCP Keepalive ──────────────────────────────────
echo ""
echo "── B. TCP Keepalive ─────────────────────────────"

KEEPALIVE_VAL=$(sysctl -n net.inet.tcp.always_keepalive 2>/dev/null || echo "0")
if [[ "$KEEPALIVE_VAL" == "1" ]]; then
  info "TCP always_keepalive 已啟用"
else
  step "啟用 TCP always_keepalive..."
  sudo sysctl -w net.inet.tcp.always_keepalive=1 >/dev/null
  info "TCP always_keepalive 已啟用（當前生效）"
fi

# 持久化：launchd plist（macOS 不讀 /etc/sysctl.conf，需用 LaunchDaemon）
LAUNCHDAEMON_PLIST="/Library/LaunchDaemons/com.openshell.tcp-keepalive.plist"
if [[ -f "$LAUNCHDAEMON_PLIST" ]]; then
  info "TCP keepalive LaunchDaemon 已存在"
else
  step "建立 LaunchDaemon 使重開機後持續生效..."
  sudo tee "$LAUNCHDAEMON_PLIST" >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openshell.tcp-keepalive</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sysctl</string>
        <string>-w</string>
        <string>net.inet.tcp.always_keepalive=1</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST
  info "已建立 $LAUNCHDAEMON_PLIST"
fi

# ── C. Power Nap ──────────────────────────────────────
echo ""
echo "── C. Power Nap ─────────────────────────────────"

POWERNAP_VAL=$(pmset -g 2>/dev/null | awk '/powernap/{print $2}' || echo "")
if [[ "$POWERNAP_VAL" == "0" ]]; then
  info "Power Nap 已關閉"
else
  step "關閉 Power Nap..."
  sudo pmset -a powernap 0
  info "Power Nap 已關閉"
fi

# ── D. DNS 備用提示 ───────────────────────────────────
echo ""
echo "── D. 備用 DNS ──────────────────────────────────"
CURRENT_DNS=$(scutil --dns 2>/dev/null | awk '/nameserver/{print $3}' | head -3 | tr '\n' ' ')
echo "  目前 DNS：${CURRENT_DNS:-（無法取得）}"
if echo "$CURRENT_DNS" | grep -qE '1\.1\.1\.1|8\.8\.8\.8'; then
  info "已有公共 DNS 備用"
else
  warn "建議手動新增備用 DNS 以提高穩定性："
  echo "  System Settings → Network → 選擇網路介面 → Details → DNS"
  echo "  新增：1.1.1.1（Cloudflare）和 8.8.8.8（Google）"
fi

# ── E. 驗證 ───────────────────────────────────────────
echo ""
echo "── 驗證結果 ─────────────────────────────────────"
echo "  防火牆允許清單（claude/bun/node）："
if [[ -n "$FIREWALL_BIN" ]]; then
  sudo "$FIREWALL_BIN" --listapps 2>/dev/null | grep -iE 'claude|bun|node' | sed 's/^/    /' || echo "    （無符合項目）"
else
  echo "    （防火牆未啟用或不可用）"
fi
echo "  net.inet.tcp.always_keepalive：$(sysctl -n net.inet.tcp.always_keepalive)"
echo "  powernap：$(pmset -g 2>/dev/null | awk '/powernap/{print $2}')"

echo ""
info "主機優化完成！"
echo "  下一步：make install-base"
