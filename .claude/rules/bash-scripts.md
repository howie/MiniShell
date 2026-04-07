---
paths:
  - "scripts/**/*.sh"
---

# Bash 腳本規範

## 嚴格模式（必要）

每個腳本的 shebang 和 comment header 之後必須緊接著：

```bash
set -euo pipefail
```

- `-e`：任何指令失敗立即退出
- `-u`：使用未定義變數時報錯
- `-o pipefail`：pipe 中任一段失敗就算失敗

## 冪等性

腳本必須可以安全重複執行。常見模式：

```bash
# 檢查再建立
if ! openshell provider list | grep -q "provider-name"; then
  # 建立動作
fi

# 檢查工具是否已安裝
if ! command -v some-tool &>/dev/null; then
  # 安裝動作
fi
```

## Color Helper Pattern

新增輸出時，複用既有的三個 helper 函式，不要用裸 `echo`：

```bash
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }   # 成功/完成
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }  # 警告/略過
step()  { echo -e "${BLUE}[→]${NC} $1"; }    # 進行中步驟
```

## 前置條件檢查

腳本開頭必須驗證依賴工具和環境狀態：

```bash
if ! command -v openshell &>/dev/null; then
  echo "請先執行 make install-base" >&2
  exit 1
fi
```

錯誤訊息輸出到 `stderr`（`>&2`），exit code 非零。

## Makefile 整合

腳本由 Makefile 呼叫前會先 `chmod +x`，無需在腳本中自行處理。
