package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"sync"
	"syscall"
)

func main() {
	cfg, err := loadConfig(configPath())
	if err != nil {
		slog.Error("failed to load config", "err", err)
		os.Exit(1)
	}

	var platforms []Platform

	if cfg.Discord.Enabled {
		if cfg.Discord.Token == "" {
			slog.Error("discord enabled but token is empty")
			os.Exit(1)
		}
		platforms = append(platforms, NewDiscord(cfg.Discord, cfg.Executor))
	}
	if cfg.Telegram.Enabled {
		if cfg.Telegram.Token == "" {
			slog.Error("telegram enabled but token is empty")
			os.Exit(1)
		}
		platforms = append(platforms, NewTelegram(cfg.Telegram, cfg.Executor))
	}
	if cfg.Slack.Enabled {
		if cfg.Slack.BotToken == "" {
			slog.Error("slack enabled but bot_token is empty")
			os.Exit(1)
		}
		platforms = append(platforms, NewSlack(cfg.Slack, cfg.Executor))
	}

	if len(platforms) == 0 {
		slog.Error("no platforms enabled — check your bridge.config.json")
		os.Exit(1)
	}

	// Root context: cancelled on SIGTERM or SIGINT.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	var wg sync.WaitGroup
	for _, p := range platforms {
		wg.Add(1)
		go func(p Platform) {
			defer wg.Done()
			slog.Info("starting platform", "platform", p.Name())
			if err := p.Run(ctx); err != nil && ctx.Err() == nil {
				slog.Error("platform exited with error", "platform", p.Name(), "err", err)
			}
			slog.Info("platform stopped", "platform", p.Name())
		}(p)
	}

	slog.Info("bridge running", "platforms", len(platforms))
	wg.Wait()
	slog.Info("shutdown complete")
}
