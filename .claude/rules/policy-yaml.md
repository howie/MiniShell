---
paths:
  - "policies/**/*.yaml"
---

# Policy YAML 規範

## Schema 正確寫法

```yaml
version: 1   # 整數，不是字串 "1"

network_policies:
  policy_name:
    name: policy-name
    endpoints:
      - host: api.example.com
        port: 443
    binaries:           # binaries 必填，不可省略
      - { path: /path/to/binary }
```

## 常見錯誤

| 錯誤 | 正確 |
|------|------|
| `version: "1"` | `version: 1` |
| endpoint 層級放 `enforcement` | policy 頂層放 `enforcement` |
| 省略 `binaries` | 每個 policy 都必須有 `binaries` |

## Claude Code Binary 三條路徑

所有涉及 Claude Code 的 policy 必須同時列出三條路徑，少一條就會 403：

```yaml
binaries:
  - { path: /usr/local/bin/claude }
  - { path: "/sandbox/.local/bin/claude" }
  - { path: "/sandbox/.local/share/claude/versions/**" }
```

如果有 `claude-runner`（renamed binary），也要加上：
```yaml
  - { path: "/sandbox/.local/bin/claude-runner" }
```

## Live Sandbox 限制

運行中的 sandbox 透過熱更新（`openshell policy set ... --wait`）：
- **可以**：新增網路路徑（endpoint / binary）
- **不可以**：移除已有路徑（需重啟 sandbox 才生效）

套用後用以下指令確認：
```bash
openshell logs <sandbox-name> --since 5m | grep "action=deny"
```

## 修改後套用

```bash
make apply-policies
# 或指定單一 sandbox
openshell policy set claude-dev --policy policies/claude_dev_policy.yaml --wait
```
