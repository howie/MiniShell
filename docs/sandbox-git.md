# Sandbox 內使用 Git 教學

> 適用 sandbox：`claude-dev`（claude_dev_policy.yaml）

---

## 為什麼需要特殊設定？

OpenShell Gateway 對所有出站流量做 **TLS termination**（中間人解密再轉送）。這表示 git 連線時看到的是 Gateway 自簽的 CA 憑證，而非 GitHub 的憑證。如果沒有設定 `GIT_SSL_CAINFO`，git 會拒絕連線：

```
fatal: unable to access 'https://github.com/...': server certificate verification failed
```

此外，git HTTPS 認證走 **GITHUB_TOKEN**（由 OpenShell Provider 注入環境），而非 SSH key 或帳號密碼。

---

## 前置條件

確認以下三件事已完成，再開始使用 git：

1. **sandbox 已建立** 且 provider `github-claude` 已綁定
2. **`make setup-claude`（或 Phase 5 初始化）已執行** — 會自動設好 GIT_SSL_CAINFO、credential helper、user config
3. **policy 已套用** 且包含 `git-receive-pack`（push 需要）

驗證：

```bash
# 在 sandbox 外確認
openshell sandbox list          # 確認 claude-dev 存在
openshell provider list         # 確認 github-claude 存在且有 GITHUB_TOKEN

# 在 sandbox 內確認
openshell sandbox connect claude-dev
echo $GITHUB_TOKEN              # 應顯示 github_pat_...
echo $GIT_SSL_CAINFO            # 應顯示 /etc/openshell-tls/openshell-ca.pem
git config --global credential.helper   # 應顯示 !f() { ... }
```

---

## 基本操作

### 進入 sandbox 並載入環境

```bash
openshell sandbox connect claude-dev

# 確保 ~/.bashrc 已載入（GIT_SSL_CAINFO 在 .bashrc 裡設定）
source ~/.bashrc
```

### Clone

```bash
# 直接 clone（.bashrc 已設定 GIT_SSL_CAINFO）
git clone https://github.com/你的組織/repo.git

# 或者一次性設定（不修改 .bashrc）
GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem \
  git clone https://github.com/你的組織/repo.git
```

### Push / Pull

```bash
cd /sandbox/你的repo

git pull                        # 拉取最新
git add -p
git commit -m "your message"
git push                        # 推送（需要 PAT 有 Contents write 權限）
```

### 確認認證身份

```bash
# 查看目前 git user config
git config --global user.name
git config --global user.email

# 測試 GitHub API 認證（確認 GITHUB_TOKEN 有效）
curl -H "Authorization: token $GITHUB_TOKEN" \
     --cacert /etc/openshell-tls/openshell-ca.pem \
     https://api.github.com/user | grep login
```

---

## 手動設定（setup-claude.sh 尚未執行時）

如果 sandbox 是手動建立或 setup-claude.sh 沒有跑完，需要手動設定：

```bash
openshell sandbox connect claude-dev

# 1. GIT_SSL_CAINFO（proxy TLS）
echo 'export GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem' >> ~/.bashrc

# 2. PATH（確保 ~/.local/bin 可用）
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

source ~/.bashrc

# 3. Credential helper（用 GITHUB_TOKEN 認證）
git config --global credential.helper \
  '!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f'

# 4. Git user config
git config --global user.name "Claude Dev"
git config --global user.email "claude-dev@sandbox.local"
```

---

## Policy 設定確認

git push 需要 policy 允許 `git-receive-pack`。確認 `policies/claude_dev_policy.yaml` 的 `github_ssh_over_https` block 包含正確設定：

```yaml
network_policies:
  github_ssh_over_https:
    name: github-ssh-over-https
    endpoints:
      - host: github.com
        port: 443
        protocol: rest
        tls: terminate
        enforcement: enforce
        rules:
          - allow:
              method: POST
              path: "/**/git-receive-pack"
    binaries:
      - { path: /usr/bin/git }
```

如果 push 被 403 擋住，查 deny log：

```bash
# 在 sandbox 外執行
openshell logs claude-dev --since 5m | grep "action=deny"
# 看 dst_host、dst_port、binary 欄位，加到 policy 後熱更新
```

---

## 常見問題排除

| 錯誤訊息 | 原因 | 解法 |
|----------|------|------|
| `server certificate verification failed` | `GIT_SSL_CAINFO` 未設定 | `source ~/.bashrc` 或手動 `export GIT_SSL_CAINFO=...` |
| `Authentication failed` | `GITHUB_TOKEN` 過期或未注入 | 到 sandbox 外執行 `openshell provider update --name github-claude --credential GITHUB_TOKEN="新token"` |
| `403` on push | PAT 缺少 Contents write 權限，或 policy 未允許 | 確認 PAT 權限；確認 policy 包含 `git-receive-pack`，並套用 `make apply-policies` |
| `Repository not found` | PAT 未授權此 repo | 到 GitHub 重新設定 PAT 的 repository access |
| `git: command not found` | PATH 問題 | `source ~/.bashrc` |
| `fatal: not a git repository` | 不在 repo 目錄內 | `cd /sandbox/你的repo` |

---

## Token 輪替

GitHub PAT 每 30 天到期。到期前執行：

```bash
# sandbox 外
openshell provider update \
  --name github-claude \
  --credential GITHUB_TOKEN="github_pat_新token"

# 重建 sandbox（provider credential 不能熱更新到已運行的 sandbox）
openshell sandbox rm claude-dev
make setup-claude
make apply-policies
```

詳細步驟請參考 [usage.md — Token 輪替](./usage.md#token-輪替)。
