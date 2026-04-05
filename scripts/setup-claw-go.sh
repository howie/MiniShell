#!/bin/bash
# setup-claw-go.sh — 在 claw-agent sandbox 安裝 Go 工具鏈與靜態 CLI binary
# 讓 OpenClaw bundled skills（blucli 等 Go-based skills）可自行安裝
# 冪等：重複執行安全
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "${BLUE}[→]${NC} $1"; }

GO_VERSION="1.24.2"
GO_TARBALL="go${GO_VERSION}.linux-arm64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
GO_INSTALL_DIR="/sandbox/.local/go"
GOPATH="/sandbox/.local/gopath"
VENV_BIN="/sandbox/.venv/bin"
LOCAL_BIN="/sandbox/.local/bin"
SANDBOX="openshell-claw-agent"

# ── 前置確認 ──────────────────────────────────────────────────────────────────
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi

if ! ssh "$SANDBOX" "echo ok" &>/dev/null; then
  echo "無法 SSH 到 claw-agent sandbox，請確認 sandbox 正在運行" >&2
  exit 1
fi

echo ""
echo "── 安裝 Go 工具鏈到 claw-agent sandbox ──────────────────"

# ── Step 1：安裝 Go（透過 host 下載，sandbox 無法存取 go.dev）──────────────
GO_INSTALLED=$(ssh "$SANDBOX" "test -x ${GO_INSTALL_DIR}/bin/go && ${GO_INSTALL_DIR}/bin/go version 2>/dev/null || echo 'not installed'")
if echo "$GO_INSTALLED" | grep -q "go${GO_VERSION}"; then
  info "Go ${GO_VERSION} 已安裝（${GO_INSTALLED}）"
else
  step "在 host 下載 Go ${GO_VERSION} for linux/arm64..."
  TMPFILE="/tmp/${GO_TARBALL}"
  if [[ ! -f "$TMPFILE" ]]; then
    curl -fsSL "$GO_URL" -o "$TMPFILE"
  fi
  info "下載完成：$(ls -lh "$TMPFILE" | awk '{print $5}')"

  step "傳送 Go tarball 到 sandbox..."
  scp "$TMPFILE" "${SANDBOX}:/tmp/${GO_TARBALL}"

  step "解壓安裝 Go..."
  ssh "$SANDBOX" "
    mkdir -p /sandbox/.local
    tar -C /sandbox/.local -xzf /tmp/${GO_TARBALL}
    rm /tmp/${GO_TARBALL}
  "
  info "Go ${GO_VERSION} 安裝完成"
fi

# ── Step 2：安裝靜態 binary（jq、rg、ffmpeg）─────────────────────────────────
echo ""
echo "── 安裝靜態 CLI binary ───────────────────────────────────"

ssh "$SANDBOX" "mkdir -p ${LOCAL_BIN}"

# jq
if ssh "$SANDBOX" "test -x ${LOCAL_BIN}/jq" 2>/dev/null; then
  info "jq 已安裝"
else
  step "安裝 jq 1.7.1 (ARM64)..."
  ssh "$SANDBOX" "curl -fsSL 'https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64' -o ${LOCAL_BIN}/jq && chmod +x ${LOCAL_BIN}/jq"
  info "jq $(ssh "$SANDBOX" "${LOCAL_BIN}/jq --version")"
fi

# ripgrep
if ssh "$SANDBOX" "test -x ${LOCAL_BIN}/rg" 2>/dev/null; then
  info "rg 已安裝"
else
  step "安裝 ripgrep 14.1.1 (ARM64)..."
  ssh "$SANDBOX" "
    curl -fsSL 'https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-aarch64-unknown-linux-gnu.tar.gz' -o /tmp/rg.tar.gz
    tar -xzf /tmp/rg.tar.gz -C /tmp
    cp /tmp/ripgrep-14.1.1-aarch64-unknown-linux-gnu/rg ${LOCAL_BIN}/rg
    chmod +x ${LOCAL_BIN}/rg
    rm -rf /tmp/rg.tar.gz /tmp/ripgrep-14.1.1-aarch64-unknown-linux-gnu
  "
  info "$(ssh "$SANDBOX" "${LOCAL_BIN}/rg --version" | head -1)"
fi

# ffmpeg
if ssh "$SANDBOX" "test -x ${LOCAL_BIN}/ffmpeg" 2>/dev/null; then
  info "ffmpeg 已安裝"
else
  step "安裝 ffmpeg (ARM64 static build)..."
  ssh "$SANDBOX" "
    curl -fsSL 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linuxarm64-gpl.tar.xz' -o /tmp/ffmpeg.tar.xz
    tar -xJf /tmp/ffmpeg.tar.xz -C /tmp
    cp /tmp/ffmpeg-master-latest-linuxarm64-gpl/bin/ffmpeg ${LOCAL_BIN}/ffmpeg
    chmod +x ${LOCAL_BIN}/ffmpeg
    rm -rf /tmp/ffmpeg.tar.xz /tmp/ffmpeg-master-latest-linuxarm64-gpl
  "
  info "$(ssh "$SANDBOX" "${LOCAL_BIN}/ffmpeg -version 2>&1 | head -1")"
fi

# ── Step 3：建立 symlink 到 OpenClaw PATH（/sandbox/.venv/bin）───────────────
echo ""
echo "── 建立 symlink 到 OpenClaw PATH ───────────────────────"

ssh "$SANDBOX" "
  ln -sf ${GO_INSTALL_DIR}/bin/go ${VENV_BIN}/go
  ln -sf ${LOCAL_BIN}/jq ${VENV_BIN}/jq
  ln -sf ${LOCAL_BIN}/rg ${VENV_BIN}/rg
  ln -sf ${LOCAL_BIN}/ffmpeg ${VENV_BIN}/ffmpeg
"
info "symlink 建立完成"

# ── Step 4：設定 OpenClaw env vars ────────────────────────────────────────────
echo ""
echo "── 設定 OpenClaw Go 環境變數 ────────────────────────────"

CURRENT_PATH=$(ssh "$SANDBOX" "openclaw config get env.PATH 2>/dev/null" | grep -v Warning | grep -v "^$" || true)
if echo "$CURRENT_PATH" | grep -q "gopath/bin"; then
  info "OpenClaw PATH 已含 Go paths"
else
  step "設定 OpenClaw PATH..."
  ssh "$SANDBOX" "openclaw config set env.PATH '${GOPATH}/bin:${GO_INSTALL_DIR}/bin:${VENV_BIN}:/usr/local/bin:/usr/bin:/bin' 2>&1 | grep -E 'Updated|Error'"
fi

for var_cmd in \
  "env.GOPATH ${GOPATH}" \
  "env.GOTOOLCHAIN local" \
  "env.GONOSUMDB *" \
  "env.GOBIN ${GOPATH}/bin"; do
  VAR=$(echo "$var_cmd" | awk '{print $1}')
  VAL=$(echo "$var_cmd" | awk '{print $2}')
  RESULT=$(ssh "$SANDBOX" "openclaw config set ${VAR} '${VAL}' 2>&1 | grep -E 'Updated|Error|already'" || true)
  if echo "$RESULT" | grep -q "Updated"; then
    info "設定 ${VAR}"
  else
    info "${VAR} 已設定"
  fi
done

# ── Step 5：重啟 gateway 讓 PATH 生效 ────────────────────────────────────────
echo ""
echo "── 重啟 OpenClaw gateway ────────────────────────────────"

# 用 bracket trick 避免 pkill 自殺：[o]penclaw 匹配 openclaw 但不匹配字面 [o]penclaw
# （見 memory: feedback_ansible_sandbox.md — pkill 透過 SSH 執行時會匹配到自己的命令列）
ssh "$SANDBOX" "pkill -f '[o]penclaw-gateway' 2>/dev/null || true"
sleep 2

# 分開第二次 SSH 啟動 gateway，避免 SSH session 結束後殺掉背景程序
ssh "$SANDBOX" "setsid openclaw gateway >> /tmp/openclaw-gw.log 2>&1 &"
sleep 3

# 第三次 SSH 驗證
GW_STATUS=$(ssh "$SANDBOX" "ss -tlnp 2>/dev/null | grep -q ':18789' && echo 'OK' || echo 'FAILED'")
if [[ "$GW_STATUS" == "OK" ]]; then
  info "Gateway 已重啟（port 18789）"
else
  warn "Gateway 啟動失敗，請手動執行：make gw-restart"
fi

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
info "Go 環境設定完成！"
echo ""
echo "  已安裝工具："
export REMOTE_PATH="${GOPATH}/bin:${GO_INSTALL_DIR}/bin:${VENV_BIN}:/usr/local/bin:/usr/bin:/bin"
echo "  go:     $(ssh "$SANDBOX" "PATH=${REMOTE_PATH} go version 2>/dev/null || echo 'not found'")"
echo "  jq:     $(ssh "$SANDBOX" "PATH=${REMOTE_PATH} jq --version 2>/dev/null || echo 'not found'")"
echo "  rg:     $(ssh "$SANDBOX" "PATH=${REMOTE_PATH} rg --version 2>/dev/null | head -1 || echo 'not found'")"
echo "  ffmpeg: $(ssh "$SANDBOX" "PATH=${REMOTE_PATH} ffmpeg -version 2>/dev/null | head -1 || echo 'not found'")"
echo ""
echo "  現在可以在 OpenClaw Dashboard 點 Install 安裝 Go-based skills"
echo "  或在 sandbox 內執行："
echo "    go install <module>@latest"
echo ""
warn "注意：policies/claw_agent_policy.yaml 的 golang policy 必須已套用"
warn "      Go 1.25+ toolchain path 需隨版本更新（目前：go1.25.8）"
echo ""
