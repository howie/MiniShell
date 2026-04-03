SHELL := /bin/bash
SCRIPTS := scripts

.PHONY: help install setup-host install-base setup-claude setup-claw apply-policies verify setup-ollama setup-bridge setup-bridge-go status

# 預設 target：顯示說明
help:
	@echo ""
	@echo "OpenShell 雙 Sandbox 環境管理"
	@echo ""
	@echo "  make install          完整安裝（host → base → claude → claw → policies → verify）"
	@echo "  make setup-host       主機優化（防火牆、TCP Keepalive、Power Nap）"
	@echo "  make install-base     安裝基礎環境（Homebrew、工具、OrbStack、OpenShell）"
	@echo "  make setup-claude     建立 Claude Code sandbox"
	@echo "  make setup-claw       建立 OpenClaw sandbox"
	@echo "  make apply-policies   套用 Policy YAML（policies/ 目錄）"
	@echo "  make verify           驗證沙箱隔離"
	@echo "  make setup-ollama     安裝本地 Ollama 並設定 inference routing（選配）"
	@echo "  make setup-bridge     安裝 Go Messaging Bridge（選配：Discord/Telegram/Slack）"
	@echo "  make status           查看目前 sandbox 狀態"
	@echo ""

# 完整安裝
install: setup-host install-base setup-claude setup-claw apply-policies verify

# Phase 0：主機層級優化
setup-host:
	@chmod +x $(SCRIPTS)/setup-host.sh
	@$(SCRIPTS)/setup-host.sh

# Phase 1~3：基礎環境
install-base:
	@chmod +x $(SCRIPTS)/install-base.sh
	@$(SCRIPTS)/install-base.sh

# Phase 4~5：Claude Code sandbox
setup-claude:
	@chmod +x $(SCRIPTS)/setup-claude.sh
	@$(SCRIPTS)/setup-claude.sh

# Phase 4+6：OpenClaw sandbox
setup-claw:
	@chmod +x $(SCRIPTS)/setup-claw.sh
	@$(SCRIPTS)/setup-claw.sh

# Phase 7：套用 policy
apply-policies:
	@chmod +x $(SCRIPTS)/apply-policies.sh
	@$(SCRIPTS)/apply-policies.sh

# Phase 8：驗證隔離
verify:
	@chmod +x $(SCRIPTS)/verify.sh
	@$(SCRIPTS)/verify.sh

# 本地推理（選配）
setup-ollama:
	@chmod +x $(SCRIPTS)/setup-ollama.sh
	@$(SCRIPTS)/setup-ollama.sh

# Messaging Bridge — Go 版（選配）
setup-bridge: setup-bridge-go

setup-bridge-go:
	@chmod +x $(SCRIPTS)/setup-bridge-go.sh
	@$(SCRIPTS)/setup-bridge-go.sh

# 狀態查看
status:
	@echo ""
	@echo "── Gateway ──────────────────────────────────────"
	@openshell status 2>/dev/null || echo "  (openshell 未安裝)"
	@echo ""
	@echo "── Sandboxes ────────────────────────────────────"
	@openshell sandbox list 2>/dev/null || echo "  (無法取得 sandbox 列表)"
	@echo ""
	@echo "── Providers ────────────────────────────────────"
	@openshell provider list 2>/dev/null || echo "  (無法取得 provider 列表)"
	@echo ""
