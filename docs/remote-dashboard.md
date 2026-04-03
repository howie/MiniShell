# 從區域網路遠端存取 OpenClaw Dashboard

本文說明如何從家中其他裝置（筆電）連線到運行在 Mac Mini OpenShell sandbox 裡的 OpenClaw Web Dashboard。

## 架構說明

```
筆電（notebook）
    │
    │ SSH tunnel（port 18789）
    ▼
Mac Mini（192.168.1.29）
    │
    │ ssh -L 0.0.0.0:18789 → openshell ssh-proxy
    ▼
claw-agent sandbox（127.0.0.1:18789）
    │
    └─ OpenClaw Gateway（前景執行）
```

OpenClaw dashboard 綁定在 sandbox 內部的 `127.0.0.1:18789`，不直接對外暴露，需要兩個步驟：
1. sandbox 內啟動 gateway
2. Mac Mini 上建立 SSH 隧道暴露到 LAN

---

## 完整步驟

### 步驟一：確認 gateway 在 sandbox 內運行

sandbox 使用 container 環境，systemd 不可用，需手動在背景啟動：

```bash
ssh openshell-claw-agent 'nohup openclaw gateway > /tmp/openclaw-gw.log 2>&1 &'
```

確認已啟動：

```bash
ssh openshell-claw-agent 'ss -tlnp | grep 18789'
```

有輸出表示 gateway 正常監聽。

### 步驟二：Mac Mini 建立 SSH 隧道（暴露到 LAN）

```bash
ssh -fN -L 0.0.0.0:18789:127.0.0.1:18789 openshell-claw-agent
```

- `-f`：進入背景
- `-N`：不開 shell，純轉發
- `0.0.0.0`：監聽所有網路介面，讓 LAN 其他裝置可連

若提示 port 已被佔用：

```bash
lsof -i :18789          # 找 PID
kill <PID>              # 殺掉舊的
# 再重新執行上面的 ssh 指令
```

### 步驟三：筆電開啟 Dashboard

> **重要**：瀏覽器 Secure Context 限制，請用 `localhost` 而非 LAN IP。
> 詳見下方「[Secure Context 說明](#secure-context)」。

在**筆電上**建立 SSH tunnel（一次性設定，之後可用 `make notebook-tunnel` 自動化）：

```bash
ssh -fN -L 18789:localhost:18789 doxa@192.168.1.29
```

接著在筆電瀏覽器輸入：

```
http://localhost:18789/#token=<你的token>
```

查詢目前的 token：

```bash
ssh openshell-claw-agent 'openclaw dashboard'
```

---

## Secure Context

OpenClaw Control UI 使用瀏覽器 Web Crypto API 產生 device identity。瀏覽器規定這個 API **只在 Secure Context 下可用**，即：

- `https://` 任何域名
- `http://localhost` 或 `http://127.0.0.1`

若直接用 `http://192.168.1.29:18789`（HTTP + 非 localhost），瀏覽器會拒絕提供 device identity，導致：

```
control ui requires device identity (use HTTPS or localhost secure context)
```

### 自動化：make notebook-tunnel

在**筆電**的 MiniShell 目錄下執行：

```bash
make notebook-tunnel
```

此指令會：
1. 停止舊的佔用程序（如有）
2. 建立 SSH tunnel：`localhost:18789 → Mac Mini → sandbox:18789`
3. 等待 tunnel 就緒
4. 自動取得 token 並顯示完整 URL

環境變數（可選）：

```bash
MINI_HOST=user@192.168.1.29 GATEWAY_PORT=18789 make notebook-tunnel
```

---

## 前置條件

| 條件 | 說明 |
|------|------|
| Mac Mini SSH 開啟 | 系統設定 → 一般 → 共享 → 遠端登入 |
| 同一個 LAN | 筆電與 Mac Mini 在同一個路由器下 |
| `~/.ssh/config` 已設定 | `openshell-claw-agent` Host（見下方） |

`~/.ssh/config` 的 `openshell-claw-agent` 設定：

```
Host openshell-claw-agent
    User sandbox
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    GlobalKnownHostsFile /dev/null
    LogLevel ERROR
    ProxyCommand /Users/doxa/.local/bin/openshell ssh-proxy --gateway-name openshell --name claw-agent
```

---

## 注意事項

- **Gateway 需要手動啟動**：sandbox 內 systemd 不可用，重開 sandbox 後需重新執行步驟一
- **Token 不會改變**：只要 sandbox 狀態未 reset，token 固定不變
- **`openshell forward` 無法使用**：在 sandbox 環境下 OpenShell gateway API 不可達，改用 SSH tunnel
- **必須用 localhost**：直接用 `http://192.168.1.29:18789` 會觸發 Secure Context 錯誤，需先建立筆電 tunnel

---

## 快速重啟（gateway 掛掉時）

```bash
# 1. 重啟 sandbox 內的 gateway
ssh openshell-claw-agent 'nohup openclaw gateway > /tmp/openclaw-gw.log 2>&1 &'

# 2. 確認
ssh openshell-claw-agent 'ss -tlnp | grep 18789'

# 3. Mac Mini 的 SSH tunnel 若斷了也重建
ssh -fN -L 0.0.0.0:18789:127.0.0.1:18789 openshell-claw-agent
```
