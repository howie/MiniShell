---
paths:
  - "Makefile"
---

# Makefile 規範

## .PHONY 宣告

每個新增的 target 必須同時加到 `.PHONY` 宣告，否則若目錄下有同名檔案會出錯：

```makefile
.PHONY: help install setup-host new-target
```

## 腳本呼叫模式

所有 shell 腳本透過以下固定模式呼叫：

```makefile
SCRIPTS := scripts

new-target:
	@chmod +x $(SCRIPTS)/new-script.sh
	@$(SCRIPTS)/new-script.sh
```

`@` 前綴抑制指令回顯，`chmod +x` 確保執行權限。

## help Target 格式

`help` target 的說明格式固定為兩空格縮排 + 對齊的中文說明：

```makefile
help:
	@echo "  make new-target     做某件事的簡短說明"
```

新增 target 時同步在 help 中加入說明。

## 變數規範

| 變數 | 值 | 用途 |
|------|-----|------|
| `SCRIPTS` | `scripts` | 腳本目錄路徑 |
| `ANSIBLE_PLAYBOOK` | `uvx --from ansible-core ansible-playbook` | `ansible-playbook` 不需全域安裝，透過 `uvx` 執行 |

不要在 target 中硬寫路徑，使用變數引用。

## `make lint` 規範驗證

提交前可用 `make lint` 自動驗證規範合規性：

```makefile
lint:
	@find $(SCRIPTS) -name "*.sh" -exec shellcheck {} \;    # Bash 嚴格模式檢查
	@find policies -name "*.yaml" -exec yamllint -d relaxed {} \;  # Policy YAML 格式
```

需要安裝：`brew install shellcheck yamllint`

## Ansible Target 模式

```makefile
some-playbook:
	$(ANSIBLE_PLAYBOOK) -i ansible/inventory.yml ansible/playbooks/some-playbook.yml
```
