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

使用 `signal.NotifyContext` 處理 SIGTERM/SIGINT。清理邏輯在 goroutine 中執行，主 goroutine 用 WaitGroup 等待所有工作完成：

```go
ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
defer stop()

// 逾時強制退出（在單獨的 goroutine 中）
go func() {
    <-ctx.Done()
    time.AfterFunc(10*time.Second, func() {
        slog.Error("shutdown timed out — forcing exit")
        os.Exit(1)
    })
}()

var wg sync.WaitGroup
for _, worker := range workers {
    wg.Add(1)
    go func() {
        defer wg.Done()
        if err := worker.Run(ctx); err != nil && ctx.Err() == nil {
            slog.Error("worker error", "err", err)
            stop() // cascade shutdown
        }
    }()
}
wg.Wait() // 主 goroutine 在此等待，不是在 <-ctx.Done()
```

## Error Handling

- **啟動階段**失敗：`slog.Error(...) + os.Exit(1)`（快速中止，不要 panic）
- **運行階段**錯誤：回傳 `error`，由上層決定是否記錄或重試
- 不使用裸 `panic()`（除非是真正不可恢復的 invariant 違反）

## 兩個獨立 Go 模組

`bridge-go/` 和 `acp-gateway/` 是各自獨立的 Go module，有自己的 `go.mod`。修改時在對應目錄下執行 `go build`：

```bash
cd bridge-go && go build .        # 產出 bridge-go/bridge-go
cd acp-gateway && go build .      # 產出 acp-gateway/acp-gateway
```

Binary 輸出在各自的模組目錄下，`.gitignore` 已排除這兩個路徑（`bridge-go/bridge-go`、`acp-gateway/acp-gateway`）。
