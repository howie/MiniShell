# MiniShell vs NemoClaw 架構比較

> 研究日期：2026-03-30

## 架構概觀對比

| 面向 | MiniShell (本專案) | NemoClaw (NVIDIA) |
|------|-------------------|-------------------|
| **定位** | 個人開發者雙 AI sandbox 環境 | 企業級 OpenClaw 安全執行平台 |
| **架構層數** | 3 層 (Landlock + Credential + Network) | 4 層 (Plugin + Blueprint + Sandbox + Inference) |
| **容器化** | OrbStack + OpenShell (K3s) | Docker/Colima + OpenShell (K3s) |
| **支援 Agent** | Claude Code + OpenClaw（雙 sandbox） | 僅 OpenClaw（單 sandbox） |
| **推理路由** | 直連外部 API (Anthropic / Google) | Inference Router 攔截，支援 local/cloud 混合 |
| **安裝方式** | Makefile + shell scripts | `nemoclaw onboard` CLI 一鍵安裝 |
| **成本** | $0-5/月 (Pro/Max 訂閱另計) | 開源免費，NIM 推理另計 |

## 安全模型差異

| 機制 | MiniShell | NemoClaw |
|------|-----------|----------|
| Landlock | ✅ | ✅ |
| seccomp | ❌ | ✅（但 OrbStack 上有已知問題） |
| Network namespace | ❌（proxy-based） | ✅ |
| Per-binary enforcement | ✅ | ✅ |
| Inference 攔截 | ❌（直連 API） | ✅（Router 攔截） |
| 多 Agent 隔離 | ✅ | ❌ |
| 第三方安全稽核 | N/A | ❌（截至 2026/03 尚未公佈） |

## macOS / Apple Silicon 上的 VM 安全問題

### Landlock 在 macOS 上不存在
- Landlock 是 Linux kernel 功能（5.13+），macOS 沒有原生支持
- 兩個專案都依賴 OrbStack/Docker 建立的 Linux VM 來獲得 Landlock
- 隔離的實際邊界是 VM，不是 macOS 本身
- MiniShell 的 `compatibility: best_effort` 設定暗示了這個降級路徑

### seccomp 在 OrbStack 上的問題
- OrbStack VM 上執行 K3s 時，seccomp 支援有已知問題
- 錯誤：`failed to generate seccomp spec opts: seccomp is not supported`
- NemoClaw 號稱的 seccomp 隔離在 OrbStack 環境可能無法生效
- MiniShell 不使用 seccomp，反而避開了這個問題

### Apple Virtualization Framework vs QEMU
- OrbStack 使用 Apple 原生 Virtualization Framework（非 QEMU）
- 優點：更輕量、更快、更低記憶體
- 風險：Apple VF 的安全隔離程度不如傳統 hypervisor（如 Xen、KVM）
- Apple VF 設計目標是開發便利性，不是安全隔離

### VM Escape 風險
- 所有安全隔離最終依賴 VM 邊界
- macOS 上的 VM 技術（OrbStack/Docker Desktop/Colima）都未經過嚴格安全稽核
- NemoClaw 已有 Snyk Labs 發現的 sandbox escape 路徑（/tools/invoke endpoint + TOCTOU race condition）

### 本地推理的 DNS/網路問題
- NemoClaw macOS 上本地推理（Ollama）因 DNS bug 無法運作（Issue #260）
- Docker Model Runner 無法穿透 sandbox 的 network namespace
- MiniShell 不做本地推理，全部走雲端 API，反而避開此問題

## 優缺點總結

### MiniShell 的優勢
1. **雙 Agent 隔離**：Claude Code + OpenClaw 完全分離，NemoClaw 只支援單一 OpenClaw
2. **更輕量**：不需要 Inference Router 的 800MB+ 額外記憶體
3. **避開 seccomp 問題**：不依賴 OrbStack 上有問題的 seccomp
4. **Bridge 遠端控制**：提供 Discord/Telegram/Slack 整合，NemoClaw 沒有
5. **更簡單的故障面**：直連雲端 API，少了推理路由層

### MiniShell 的劣勢
1. **無 seccomp**：少了一層 syscall 過濾
2. **Proxy-based 而非 netns**：網路隔離靠 proxy gateway 而非 kernel-level namespace
3. **無推理攔截**：API Key 在 sandbox 內，API 請求直接發出
4. **手動維護**：缺少 NemoClaw 的 Blueprint CLI 管理工具

### 結論

對 macOS Apple Silicon 個人開發者而言，MiniShell 是更務實的選擇。NemoClaw 的額外安全層在 OrbStack/macOS 上實際效果存疑，且 MiniShell 的雙 sandbox 設計提供了 NemoClaw 缺乏的 multi-agent 隔離。

如果需要真正嚴格的安全隔離，應考慮 Linux bare-metal + KVM，而非任何 macOS + VM 方案。
