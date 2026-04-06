package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	cfg, err := loadConfig(configPath())
	if err != nil {
		slog.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	if cfg.AuthToken == "" {
		slog.Error("ACP_GATEWAY_TOKEN env var is required")
		os.Exit(1)
	}

	pool := NewSessionPool(
		time.Duration(cfg.Session.TTLSeconds)*time.Second,
		cfg.Session.MaxSessions,
		cfg.Session.MaxHistory,
	)

	mux := http.NewServeMux()

	// Health endpoint (no auth).
	mux.HandleFunc("GET /health", handleHealth(pool))

	// Prompt endpoint (auth required).
	mux.HandleFunc("POST /v1/prompt", handlePrompt(cfg.Executor, pool))

	// MCP streamable-http endpoint (auth required).
	mux.HandleFunc("POST /mcp", handleMCP(cfg.Executor, pool))
	// MCP also needs GET for server-sent events and DELETE for session cleanup.
	mux.HandleFunc("GET /mcp", handleMCPGet())
	mux.HandleFunc("DELETE /mcp", handleMCPDelete())

	// Wrap with auth middleware.
	handler := authMiddleware(cfg.AuthToken, mux)

	addr := fmt.Sprintf(":%d", cfg.Port)
	srv := &http.Server{
		Addr:         addr,
		Handler:      handler,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: time.Duration(cfg.Executor.TimeoutMs+30_000) * time.Millisecond,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown on SIGTERM/SIGINT.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	go func() {
		<-ctx.Done()
		slog.Info("shutting down server...")
		shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutCtx); err != nil {
			slog.Error("server shutdown error", "err", err)
		}
	}()

	// Start session cleanup goroutine.
	go pool.CleanupLoop(ctx)

	slog.Info("acp-gateway starting", "addr", addr, "ssh_host", cfg.Executor.SSHHost)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		slog.Error("server error", "err", err)
		os.Exit(1)
	}
	slog.Info("shutdown complete")
}
