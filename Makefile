SHELL := /bin/bash
SCRIPTS := scripts
ANSIBLE_PLAYBOOK := uvx --from ansible-core ansible-playbook

# Colors for output
CYAN  := \033[36m
GREEN := \033[32m
YELLOW:= \033[33m
RESET := \033[0m

.PHONY: help install install-hooks lint check \
        setup-host install-base setup-claude setup-claw apply-policies verify setup-ollama \
        setup-bridge setup-bridge-go status dashboard gw-restart sandbox-check notebook-tunnel

# 預設 target：顯示說明
help:
	@echo ""
	@echo "$(CYAN)OpenShell 雙 Sandbox 環境管理$(RESET)"
	@echo ""
	@echo "$(GREEN)安裝指令:$(RESET)"
	@echo "  make install          完整安裝（host → base → claude → claw → policies → verify）"
	@echo "  make install-hooks    安裝 pre-commit hooks"
	@echo ""
	@echo "$(GREEN)程式碼品質:$(RESET)"
	@echo "  make lint             shellcheck 檢查所有 scripts/*.sh"
	@echo "  make check            同 lint（shellcheck 不自動修正）"
	@echo ""
	@echo "$(GREEN)Sandbox 建立:$(RESET)"
	@echo "  make setup-host       主機優化（防火牆、TCP Keepalive、Power Nap）"
	@echo "  make install-base     安裝基礎環境（Homebrew、工具、OrbStack、OpenShell）"
	@echo "  make setup-claude     建立 Claude Code sandbox"
	@echo "  make setup-claw       建立 OpenClaw sandbox"
	@echo "  make apply-policies   套用 Policy YAML（policies/ 目錄）"
	@echo "  make verify           驗證沙箱隔離"
	@echo "  make setup-ollama     安裝本地 Ollama + Gemma 4 e4b 並設定 inference routing"
	@echo "  make setup-bridge     安裝 Go Messaging Bridge（選配：Discord/Telegram/Slack）"
	@echo "  make status           查看目前 sandbox 狀態"
	@echo ""
	@echo "$(GREEN)Ansible 自動化:$(RESET)"
	@echo "  make dashboard        一鍵啟動 OpenClaw Dashboard（設定 config + gateway + LAN tunnel）"
	@echo "  make notebook-tunnel  從筆電建立 SSH tunnel（解決 Secure Context，在筆電上執行）"
	@echo "  make gw-restart       重啟 claw-agent gateway"
	@echo "  make sandbox-check    健康檢查（所有 sandbox + tunnel）"
	@echo ""

# =============================================================================
# Installation
# =============================================================================

install: install-hooks setup-host install-base setup-claude setup-ollama setup-claw apply-policies verify

install-hooks:
	uvx pre-commit install
	cp scripts/no-push-to-main.sh .git/hooks/pre-push
	chmod +x .git/hooks/pre-push
	@echo "$(GREEN)✓ pre-commit hooks 已安裝（pre-commit + pre-push）$(RESET)"

# =============================================================================
# Code Quality
# =============================================================================

lint:
	@echo "$(CYAN)shellcheck scripts/*.sh...$(RESET)"
	shellcheck scripts/*.sh
	@echo "$(GREEN)✓ shellcheck 通過$(RESET)"

check: lint

# =============================================================================
# Sandbox Setup
# =============================================================================

# 完整安裝（不含 install-hooks，避免重複）


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

# 本地推理（已含在 install 流程中，也可獨立執行）
setup-ollama:
	@chmod +x $(SCRIPTS)/setup-ollama.sh
	@$(SCRIPTS)/setup-ollama.sh

# Messaging Bridge — Go 版（選配）
setup-bridge: setup-bridge-go

setup-bridge-go:
	@chmod +x $(SCRIPTS)/setup-bridge-go.sh
	@$(SCRIPTS)/setup-bridge-go.sh

# Dashboard LAN 存取（Ansible）
dashboard:
	@echo "啟動 OpenClaw Dashboard（設定 config + gateway + LAN tunnel）..."
	@cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.yml playbooks/claw-dashboard.yml

# 筆電 localhost tunnel（解決 Secure Context，在筆電上執行）
notebook-tunnel:
	@chmod +x $(SCRIPTS)/notebook-tunnel.sh
	@$(SCRIPTS)/notebook-tunnel.sh

# 重啟 claw-agent gateway（Ansible）
gw-restart:
	@echo "重啟 OpenClaw Gateway..."
	@cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.yml playbooks/claw-gateway.yml

# Sandbox 健康檢查（Ansible）
sandbox-check:
	@echo "執行健康檢查..."
	@cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.yml playbooks/sandbox-status.yml

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
