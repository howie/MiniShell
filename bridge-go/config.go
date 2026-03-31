package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	Executor ExecutorConfig  `json:"executor"`
	Discord  DiscordConfig   `json:"discord"`
	Telegram TelegramConfig  `json:"telegram"`
	Slack    SlackConfig     `json:"slack"`
}

type ExecutorConfig struct {
	TimeoutMs    int    `json:"timeout_ms"`
	ClaudeBinary string `json:"claude_binary"`
	// SSHHost is read from BRIDGE_SSH_HOST env var, not from JSON.
	SSHHost string `json:"-"`
}

type DiscordConfig struct {
	Enabled           bool     `json:"enabled"`
	Token             string   `json:"token"`
	CommandPrefix     string   `json:"command_prefix"`
	AllowedChannelIDs []string `json:"allowed_channel_ids"`
	AllowedUserIDs    []string `json:"allowed_user_ids"`
}

type TelegramConfig struct {
	Enabled        bool     `json:"enabled"`
	Token          string   `json:"token"`
	AllowedChatIDs []string `json:"allowed_chat_ids"`
	AllowedUserIDs []string `json:"allowed_user_ids"`
}

type SlackConfig struct {
	Enabled           bool     `json:"enabled"`
	BotToken          string   `json:"bot_token"`
	AppToken          string   `json:"app_token"`
	AllowedChannelIDs []string `json:"allowed_channel_ids"`
	AllowedUserIDs    []string `json:"allowed_user_ids"`
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config %s: %w", path, err)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}

	// Apply defaults
	if cfg.Executor.TimeoutMs <= 0 {
		cfg.Executor.TimeoutMs = 300_000
	}
	if cfg.Executor.ClaudeBinary == "" {
		cfg.Executor.ClaudeBinary = "/sandbox/.local/bin/claude-sandbox"
	}
	if cfg.Discord.CommandPrefix == "" {
		cfg.Discord.CommandPrefix = "!claude "
	}

	// Read SSH host from environment
	cfg.Executor.SSHHost = os.Getenv("BRIDGE_SSH_HOST")

	return &cfg, nil
}

// configPath returns the config file path from env or a default.
func configPath() string {
	if p := os.Getenv("BRIDGE_CONFIG_PATH"); p != "" {
		return p
	}
	return "/sandbox/messaging-bridge/bridge.config.json"
}
