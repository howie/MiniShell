#!/bin/bash
# setup-claude.sh — 建立 Claude Code sandbox（Phase 4-5）
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

# ── 確認前置條件 ──────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi

if ! openshell status 2>/dev/null | grep -q "Connected"; then
  echo "OpenShell Gateway 未在線，請先執行 openshell gateway start" >&2
  exit 1
fi

# ── 建立 GitHub Provider ──────────────────────────────────────────────────────
echo ""
echo "── GitHub Provider（Claude Code 用）────────────────"
if openshell provider list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "github-claude"; then
  info "Provider 'github-claude' 已存在，略過"
else
  step "建立 github-claude provider"
  echo "  需要 GitHub Fine-grained PAT（openshell-claude-dev）"
  echo "  權限：Contents read/write、Metadata read-only"
  echo -n "  請輸入 GitHub PAT: "
  read -rs GITHUB_PAT
  echo ""

  if [[ -z "$GITHUB_PAT" ]]; then
    echo "PAT 不能為空" >&2
    exit 1
  fi

  openshell provider create \
    --name github-claude \
    --type github \
    --credential GITHUB_TOKEN="$GITHUB_PAT"
  info "Provider 'github-claude' 建立完成"
fi

# ── 建立 Sandbox ──────────────────────────────────────────────────────────────
echo ""
echo "── 建立 claude-dev sandbox ──────────────────────────"
if openshell sandbox list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -q "claude-dev"; then
  info "Sandbox 'claude-dev' 已存在，略過"
else
  step "建立 claude-dev sandbox..."
  openshell sandbox create \
    --name claude-dev \
    --provider github-claude \
    -- claude
  info "Sandbox 建立完成"
fi

# ── 初始化 sandbox 內環境 ─────────────────────────────────────────────────────
echo ""
echo "── 初始化 sandbox 內部環境 ──────────────────────────"
warn "即將在 sandbox 內執行初始化腳本（PATH、GIT_SSL_CAINFO、marketplace pre-clone）"
echo "  這需要進入 sandbox 執行指令..."

openshell sandbox connect claude-dev -- bash -c '
set -euo pipefail

# 修 PATH
if ! grep -q "HOME/.local/bin" ~/.bashrc 2>/dev/null; then
  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> ~/.bashrc
  echo "[init] PATH 設定完成"
fi

# GIT_SSL_CAINFO（proxy TLS）
if ! grep -q "GIT_SSL_CAINFO" ~/.bashrc 2>/dev/null; then
  echo '"'"'export GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem'"'"' >> ~/.bashrc
  echo "[init] GIT_SSL_CAINFO 設定完成"
fi

# Marketplace pre-clone（繞過 race condition）
if [ ! -d ~/.claude/plugins/marketplaces/claude-plugins-official ]; then
  mkdir -p ~/.claude/plugins/marketplaces
  GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem \
    git clone --depth 1 \
    https://github.com/anthropics/claude-plugins-official.git \
    ~/.claude/plugins/marketplaces/claude-plugins-official
  echo "[init] Marketplace pre-clone 完成"
fi

# known_marketplaces.json
if [ ! -f ~/.claude/plugins/known_marketplaces.json ]; then
  mkdir -p ~/.claude/plugins
  cat > ~/.claude/plugins/known_marketplaces.json << '"'"'HEREDOC'"'"'
{
  "claude-plugins-official": {
    "source": {
      "source": "github",
      "repo": "anthropics/claude-plugins-official"
    },
    "installLocation": "/sandbox/.claude/plugins/marketplaces/claude-plugins-official",
    "lastUpdated": "2026-03-29T00:00:00.000Z"
  }
}
HEREDOC
  echo "[init] known_marketplaces.json 建立完成"
fi

# claude-sandbox wrapper（跳過權限確認）
if [ ! -f ~/.local/bin/claude-sandbox ]; then
  mkdir -p ~/.local/bin
  cat > ~/.local/bin/claude-sandbox << '"'"'WRAPPER'"'"'
#!/bin/bash
set -euo pipefail
exec claude --dangerously-skip-permissions "$@"
WRAPPER
  chmod +x ~/.local/bin/claude-sandbox
  echo "[init] claude-sandbox wrapper 建立完成"
fi

# claude alias（互動式方便用）
if ! grep -q "alias claude=" ~/.bashrc 2>/dev/null; then
  echo "alias claude='"'"'claude-sandbox'"'"'" >> ~/.bashrc
  echo "[init] claude alias 設定完成"
fi
'

echo ""
info "Sandbox 初始化完成！"
echo ""
echo "  下一步："
echo "  1. openshell sandbox connect claude-dev"
echo "  2. 執行 claude 並完成 OAuth 認證（用瀏覽器登入 Anthropic Pro/Max）"
echo "  3. /status → 確認顯示 Pro 或 Max"
echo ""
echo "  如果顯示 'API Usage Billing'："
echo "    unset ANTHROPIC_API_KEY → /logout → /login"
