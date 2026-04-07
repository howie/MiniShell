---
paths:
  - "mcp-claude-code/**/*.js"
---

# MCP Server（Node.js）規範

## 模組系統

`mcp-claude-code/package.json` 設定 `"type": "module"`，使用 ESM：

```js
import { createInterface } from "node:readline";
import { stdout, stderr, env, exit } from "node:process";
```

不使用 CommonJS (`require`)，不引入第三方套件（`dependencies: {}`）。

## stdin/stdout 職責分離

這個 MCP server 透過 stdio 與 OpenClaw 通訊：

| Stream | 用途 |
|--------|------|
| `stdout` | **只**用於輸出 JSON-RPC 2.0 response（`sendResponse` / `sendError`）|
| `stderr` | 所有 debug/error log、startup 訊息 |
| `stdin` | 讀取 JSON-RPC requests（用 `readline` 逐行解析）|

**不得用 `console.log`**（輸出到 stdout，會污染 JSON-RPC stream），改用 `stderr.write()`。

## 環境變數驗證

啟動時 fail-fast 驗證必要 env var：

```js
const GATEWAY_TOKEN = env.ACP_GATEWAY_TOKEN || "";
if (!GATEWAY_TOKEN) {
  stderr.write("ERROR: ACP_GATEWAY_TOKEN env var is required\n");
  exit(1);
}
```

## JSON-RPC Response 格式

```js
// 成功
stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");

// 錯誤
stdout.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n");
```

每個 response 必須以 `\n` 結尾（newline-delimited JSON）。

## Gateway 呼叫 Pattern

使用原生 `fetch` + `AbortController` 做 timeout 控制，不引入 axios 等套件：

```js
const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), timeoutMs + 30000);
try {
  const resp = await fetch(url, { signal: controller.signal, ... });
} finally {
  clearTimeout(timer);
}
```
