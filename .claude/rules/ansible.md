---
paths:
  - "ansible/**/*.yml"
  - "ansible/**/*.yaml"
---

# Ansible 規範

## Module FQCN（必要）

一律使用 **Fully Qualified Collection Name**，避免多 Collection 環境下的模組衝突：

```yaml
# 正確
ansible.builtin.shell:
ansible.builtin.wait_for:
ansible.builtin.debug:

# 錯誤（短名可能衝突）
shell:
wait_for:
debug:
```

## Task 命名

Task name 使用繁體中文，清楚描述動作目標：

```yaml
tasks:
  - name: 檢查 tunnel 是否已存在
  - name: 停止舊的 tunnel
  - name: 建立 SSH tunnel（LAN 暴露）
```

## 冪等性報告

Shell task 必須設定 `changed_when` 和 `failed_when`，避免誤報：

```yaml
- name: 取得目前狀態
  ansible.builtin.shell:
    cmd: "some-command"
  register: result
  changed_when: false    # 查詢動作不算 changed
  failed_when: false     # 允許非零退出碼
```

## SSH 連線設定

連接 sandbox（openshell-claw-agent / openshell-claude-dev）時統一用：

```yaml
ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
```

Inventory 已預設這組設定（`ansible/inventory.yml`），role/playbook 不需重複指定。

## 執行方式

透過 Makefile，不要直接呼叫 `ansible-playbook`：

```bash
make dashboard        # claw-gateway role + LAN tunnel
make gw-restart       # 重啟 gateway
make sandbox-check    # 健康檢查
```

直接執行時用 `uvx`（從 repo 根目錄，使用完整相對路徑）：
```bash
uvx --from ansible-core ansible-playbook -i ansible/inventory.yml ansible/playbooks/foo.yml
```

注意：Makefile 的各 ansible target 用的是 `cd ansible &&` 前綴，inventory 和 playbook 路徑因此相對於 `ansible/` 目錄。直接執行時不需 `cd`，使用 repo 根目錄的路徑即可。

## Inventory 結構

- `sandboxes` group：`claw-agent`、`claude-dev`（透過 openshell SSH alias）
- `localhost` group：`mac-mini`（ansible_connection: local）

新增 sandbox 時同時更新 `ansible/inventory.yml`。
