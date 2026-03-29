#!/bin/bash
# install-base.sh — Phase 0~3: 安裝基礎環境（Homebrew、基礎工具、OrbStack、OpenShell）
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

# ── 檢查 macOS 和 Apple Silicon ──────────────────────────────────────────────
echo "── 檢查環境 ─────────────────────────────────────────"
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "此腳本需要 Apple Silicon（arm64）Mac。目前架構：$(uname -m)" >&2
  exit 1
fi
info "Apple Silicon 確認"

# ── Homebrew ─────────────────────────────────────────────────────────────────
echo ""
echo "── Homebrew ─────────────────────────────────────────"
if command -v brew &>/dev/null; then
  info "Homebrew 已安裝，略過"
else
  warn "安裝 Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zshrc
  eval "$(/opt/homebrew/bin/brew shellenv)"
  info "Homebrew 安裝完成"
fi

# ── 基礎工具 ─────────────────────────────────────────────────────────────────
echo ""
echo "── 基礎工具 ─────────────────────────────────────────"
for tool in git node python3 uv jq; do
  if command -v "$tool" &>/dev/null; then
    info "$tool 已安裝"
  else
    warn "安裝 $tool..."
    brew install "$tool"
    info "$tool 安裝完成"
  fi
done

# ── OrbStack ─────────────────────────────────────────────────────────────────
echo ""
echo "── OrbStack ─────────────────────────────────────────"
if [ -d "/Applications/OrbStack.app" ]; then
  info "OrbStack 已安裝"
else
  warn "安裝 OrbStack..."
  brew install orbstack
  info "OrbStack 安裝完成"
fi

if ! pgrep -x "OrbStack" &>/dev/null; then
  warn "啟動 OrbStack..."
  open -a OrbStack
  echo "  請在 OrbStack 首次設定中選擇 Docker（不選 Kubernetes / Linux Machine）"
  echo "  設定完成後按 Enter 繼續..."
  read -r
fi

# 驗證 Docker
if ! docker info &>/dev/null; then
  echo "Docker 無法連線，請確認 OrbStack 已啟動且選擇了 Docker 模式。" >&2
  exit 1
fi
info "Docker 連線正常"

# 建立 symlink（預防 OpenClaw PATH 問題）
mkdir -p ~/.local/bin
if [ -f ~/.orbstack/bin/docker ]; then
  ln -sf ~/.orbstack/bin/docker ~/.local/bin/docker
  ln -sf ~/.orbstack/bin/docker-compose ~/.local/bin/docker-compose 2>/dev/null || true
  info "Docker symlink 建立完成"
fi

# ── OpenShell CLI ─────────────────────────────────────────────────────────────
echo ""
echo "── OpenShell CLI ────────────────────────────────────"
if command -v openshell &>/dev/null; then
  info "OpenShell 已安裝（$(openshell --version 2>/dev/null || echo '版本未知')）"
else
  warn "安裝 OpenShell..."
  uv tool install openshell
  info "OpenShell 安裝完成"
fi

echo ""
echo "── 啟動 Gateway ─────────────────────────────────────"
if openshell status 2>/dev/null | grep -q "Connected"; then
  info "Gateway 已在線"
else
  warn "啟動 Gateway（首次約需 2-5 分鐘）..."
  openshell gateway start
  info "Gateway 啟動完成"
fi

echo ""
info "基礎環境安裝完成！"
echo "  下一步：make setup-claude 或 make setup-claw"
