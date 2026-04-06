SHELL := /bin/bash
SCRIPTS := scripts
ANSIBLE_PLAYBOOK := uvx --from ansible-core ansible-playbook

.PHONY: help install setup-host install-base setup-claude setup-claw apply-policies verify setup-ollama setup-bridge setup-bridge-go setup-acp-gateway quick-claw tier-setup status dashboard gw-restart sandbox-check notebook-tunnel

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
	@echo "  make setup-claw-go    安裝 Go 工具鏈到 claw-agent（解鎖 Go-based skills）"
	@echo "  make apply-policies   套用 Policy YAML（policies/ 目錄）"
	@echo "  make verify           驗證沙箱隔離"
	@echo "  make quick-claw       一鍵啟動 OpenClaw（本地 Ollama，不需任何 API key）"
	@echo "  make setup-ollama     安裝本地 Ollama + Gemma 4 e2b 並設定 inference routing"
	@echo "  make tier-setup       三層推理分層設定（T1 本地/T2 Gemini Flash/T3 Claude Code）"
	@echo "  make setup-bridge     安裝 Go Messaging Bridge（選配：Discord/Telegram/Slack）"
	@echo "  make setup-acp-gateway 安裝 ACP Gateway（選配：讓 OpenClaw 使用 Claude Code）"
	@echo "  make status           查看目前 sandbox 狀態"
	@echo ""
	@echo "Ansible 自動化："
	@echo "  make dashboard        一鍵啟動 OpenClaw Dashboard（設定 config + gateway + LAN tunnel）"
	@echo "  make notebook-tunnel  從筆電建立 SSH tunnel（解決 Secure Context，在筆電上執行）"
	@echo "  make gw-restart       重啟 claw-agent gateway"
	@echo "  make sandbox-check    健康檢查（所有 sandbox + tunnel）"
	@echo ""

# 完整安裝
install: setup-host install-base setup-claude setup-ollama setup-claw apply-policies verify

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

# Go 工具鏈 + 靜態 binary（jq/rg/ffmpeg）→ 解鎖 Go-based OpenClaw skills
setup-claw-go:
	@chmod +x $(SCRIPTS)/setup-claw-go.sh
	@$(SCRIPTS)/setup-claw-go.sh

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

# Quick OpenClaw — 一鍵本地 AI sandbox（Ollama + OpenClaw，不需 API key）
quick-claw:
	@chmod +x $(SCRIPTS)/setup-quick-claw.sh
	@$(SCRIPTS)/setup-quick-claw.sh $(MODEL)

# Messaging Bridge — Go 版（選配）
setup-bridge: setup-bridge-go

setup-bridge-go:
	@chmod +x $(SCRIPTS)/setup-bridge-go.sh
	@$(SCRIPTS)/setup-bridge-go.sh

# 三層推理分層設定
# T1：claw-ollama-gemma4 → gemma4:e2b（本地快速）
# T2：claw-agent → Gemini 2.5 Flash（雲端標準）
# T3：claude-code MCP tool → Claude Code（重度推理）
tier-setup: setup-ollama setup-claw setup-acp-gateway
	@chmod +x $(SCRIPTS)/setup-quick-claw.sh
	@$(SCRIPTS)/setup-quick-claw.sh gemma4:e2b
	@echo ""
	@echo "════════════════════════════════════════════════════"
	@echo "  分層推理設定完成"
	@echo "  T1 快速（<1s）  : claw-ollama-gemma4 → gemma4:e2b（本地）"
	@echo "  T2 標準（1-3s） : claw-agent → Gemini 2.5 Flash（雲端）"
	@echo "  T3 重度（10-60s）: claude-code MCP tool → Claude Code"
	@echo "════════════════════════════════════════════════════"

# ACP Gateway — 讓 OpenClaw 使用 Claude Code（選配）
setup-acp-gateway:
	@chmod +x $(SCRIPTS)/setup-acp-gateway.sh
	@$(SCRIPTS)/setup-acp-gateway.sh

# Dashboard LAN 存取（Ansible）
dashboard:
	@echo "啟動 OpenClaw Dashboard（設定 config + gateway + LAN tunnel）..."
	@cd ansible && $(ANSIBLE_PLAYBOOK) -i inventory.yml playbooks/claw-dashboard.yml

# 筆電 localhost tunnel（解決 Secure Context，在筆電上執行）
# 用法：make notebook-tunnel                            → claw-agent (port 18789)
#       make notebook-tunnel SANDBOX=claw-ollama-gemma4 → quick-claw (port 18790)
notebook-tunnel:
	@chmod +x $(SCRIPTS)/notebook-tunnel.sh
	@SANDBOX=$(SANDBOX) $(SCRIPTS)/notebook-tunnel.sh

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
