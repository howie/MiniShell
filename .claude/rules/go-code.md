---
paths:
  - "bridge-go/**/*.go"
  - "acp-gateway/**/*.go"
---

# Go 程式碼規範

## 日誌：使用 `log/slog`

不使用 `log.Printf` 或 `fmt.Println`。一律用結構化日誌：

```go
// 正確
slog.Info("server started", "addr", addr)
slog.Error("failed to load config", "err", err)

// 錯誤
log.Printf("server started on %s", addr)
fmt.Println("error:", err)
```

## 啟動 Pattern

遵循既有的三段式啟動結構：

```go
func main() {
    // 1. 載入並驗證設定
    cfg, err := loadConfig(configPath())
    if err != nil {
        slog.Error("failed to load config", "err", err)
        os.Exit(1)
    }

    // 2. 驗證必要欄位（fail-fast）
    if cfg.SomeToken == "" {
        slog.Error("SOME_TOKEN env var is required")
        os.Exit(1)
    }

    // 3. 啟動服務
}
```

## Graceful Shutdown

使用 `signal.NotifyContext` 處理 SIGTERM/SIGINT：

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()

// 啟動服務後等待 signal
<-ctx.Done()
// 執行清理
```

## Error Handling

- **啟動階段**失敗：`slog.Error(...) + os.Exit(1)`（快速中止，不要 panic）
- **運行階段**錯誤：回傳 `error`，由上層決定是否記錄或重試
- 不使用裸 `panic()`（除非是真正不可恢復的 invariant 違反）

## 兩個獨立 Go 模組

`bridge-go/` 和 `acp-gateway/` 是各自獨立的 Go module，有自己的 `go.mod`。修改時在對應目錄下執行 `go build`：

```bash
cd bridge-go && go build -o ../bridge .
cd acp-gateway && go build .
```
