---
name: sandbox-git
description: Sandbox 內使用 Git 的快速參考 — clone、push、常見問題排除
user_invocable: true
---

# Sandbox Git 快速參考

## 進入 sandbox 並準備 git 環境

```bash
openshell sandbox connect claude-dev
source ~/.bashrc     # 載入 GIT_SSL_CAINFO（必要，否則 clone 失敗）
```

## 常用操作

```bash
# Clone
git clone https://github.com/你的/repo.git

# 日常工作流
cd /sandbox/repo
git pull
git add -p && git commit -m "message"
git push
```

## 設定確認

```bash
echo $GIT_SSL_CAINFO          # /etc/openshell-tls/openshell-ca.pem
echo $GITHUB_TOKEN             # github_pat_... （由 provider 注入）
git config --global credential.helper   # !f() { ... }
```

## 手動設定（setup-claude.sh 未跑過時）

```bash
echo 'export GIT_SSL_CAINFO=/etc/openshell-tls/openshell-ca.pem' >> ~/.bashrc
git config --global credential.helper \
  '!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f'
git config --global user.name "Claude Dev"
git config --global user.email "claude-dev@sandbox.local"
source ~/.bashrc
```

## 問題排除 Checklist

- [ ] `server certificate verification failed` → `source ~/.bashrc`（載入 GIT_SSL_CAINFO）
- [ ] `Authentication failed` → GITHUB_TOKEN 過期，到 sandbox 外更新 provider
- [ ] `403` on push → PAT 缺 Contents write，或 policy 未允許 push；查 deny log
- [ ] `Repository not found` → PAT 未授權此 repo，重新設定 repository access

## 查 deny log（sandbox 外執行）

```bash
openshell logs claude-dev --since 5m | grep "action=deny"
# 看 dst_host / binary → 加進 policies/claude_dev_policy.yaml → make apply-policies
```

## Token 輪替（每 30 天）

```bash
openshell provider update --name github-claude --credential GITHUB_TOKEN="新token"
openshell sandbox rm claude-dev && make setup-claude && make apply-policies
```

---

詳細教學：[docs/sandbox-git.md](../docs/sandbox-git.md)
