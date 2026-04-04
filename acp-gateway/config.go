package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type Config struct {
	Port      int             `json:"port"`
	Executor  ExecutorConfig  `json:"executor"`
	Session   SessionConfig   `json:"session"`
	RateLimit RateLimitConfig `json:"rate_limit"`
	// AuthToken is read from ACP_GATEWAY_TOKEN env var, not from JSON.
	AuthToken string `json:"-"`
}

type ExecutorConfig struct {
	TimeoutMs    int    `json:"timeout_ms"`
	ClaudeBinary string `json:"claude_binary"`
	// SystemPrompt is prepended to every request as --system-prompt.
	// If empty, the default provenance watermark is used.
	SystemPrompt string `json:"system_prompt,omitempty"`
	// AllowedCallers lists the agent identities permitted to call this gateway.
	// Logged in the provenance header for audit trail.
	AllowedCallers []string `json:"allowed_callers,omitempty"`
	// SSHHost is read from ACP_GATEWAY_SSH_HOST env var, not from JSON.
	SSHHost string `json:"-"`
}

type SessionConfig struct {
	TTLSeconds  int `json:"ttl_seconds"`
	MaxSessions int `json:"max_sessions"`
	MaxHistory  int `json:"max_history"`
}

type RateLimitConfig struct {
	RequestsPerMinute int `json:"requests_per_minute"`
	BurstSize         int `json:"burst_size"`
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

	// Apply defaults.
	if cfg.Port <= 0 {
		cfg.Port = 7865
	}
	if cfg.Executor.TimeoutMs <= 0 {
		cfg.Executor.TimeoutMs = 300_000
	}
	if cfg.Executor.ClaudeBinary == "" {
		cfg.Executor.ClaudeBinary = "claude"
	}
	if cfg.Session.TTLSeconds <= 0 {
		cfg.Session.TTLSeconds = 1800
	}
	if cfg.Session.MaxSessions <= 0 {
		cfg.Session.MaxSessions = 10
	}
	if cfg.Session.MaxHistory <= 0 {
		cfg.Session.MaxHistory = 20
	}
	if cfg.RateLimit.RequestsPerMinute <= 0 {
		cfg.RateLimit.RequestsPerMinute = 10
	}
	if cfg.RateLimit.BurstSize <= 0 {
		cfg.RateLimit.BurstSize = 3
	}

	// Read sensitive values from environment.
	cfg.AuthToken = os.Getenv("ACP_GATEWAY_TOKEN")
	cfg.Executor.SSHHost = os.Getenv("ACP_GATEWAY_SSH_HOST")

	return &cfg, nil
}

func configPath() string {
	if p := os.Getenv("ACP_GATEWAY_CONFIG_PATH"); p != "" {
		return p
	}
	home, _ := os.UserHomeDir()
	return home + "/.config/acp-gateway/config.json"
}
