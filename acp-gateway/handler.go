package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// PromptRequest is the request body for POST /v1/prompt.
type PromptRequest struct {
	Prompt    string `json:"prompt"`
	TimeoutMs int    `json:"timeout_ms,omitempty"`
	// Caller identifies the agent sending this request (e.g. "openclaw/claw-agent").
	// Logged for audit trail and included in provenance metadata.
	Caller string `json:"caller,omitempty"`
}

// PromptResponse is the response body for POST /v1/prompt.
type PromptResponse struct {
	Output     string `json:"output"`
	Success    bool   `json:"success"`
	DurationMs int64  `json:"duration_ms"`
	Truncated  bool   `json:"truncated"`
	TimedOut   bool   `json:"timed_out,omitempty"`
}

// HealthResponse is the response body for GET /health.
type HealthResponse struct {
	Status   string `json:"status"`
	Sessions int    `json:"sessions"`
	Uptime   int64  `json:"uptime_seconds"`
}

var startTime = time.Now()

func handleHealth(pool *SessionPool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		resp := HealthResponse{
			Status:   "ok",
			Sessions: pool.Count(),
			Uptime:   int64(time.Since(startTime).Seconds()),
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

func handlePrompt(execCfg ExecutorConfig, pool *SessionPool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req PromptRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
			return
		}

		if req.Prompt == "" {
			http.Error(w, `{"error":"prompt is required"}`, http.StatusBadRequest)
			return
		}

		// Log caller identity for audit trail.
		caller := req.Caller
		if caller == "" {
			caller = "unknown"
		}
		slog.Info("prompt request", "caller", caller, "prompt_len", len(req.Prompt))

		// Sanitize the prompt.
		prompt, truncated := sanitizePrompt(req.Prompt)
		if truncated {
			slog.Warn("prompt truncated", "original_len", len(req.Prompt), "caller", caller)
		}

		// Apply per-request timeout override.
		cfg := execCfg
		if req.TimeoutMs > 0 {
			cfg.TimeoutMs = req.TimeoutMs
		}

		result := Execute(r.Context(), cfg, prompt)

		resp := PromptResponse{
			Output:     result.Output,
			Success:    result.Success,
			DurationMs: result.DurationMs,
			Truncated:  result.Truncated,
			TimedOut:   result.TimedOut,
		}

		w.Header().Set("Content-Type", "application/json")
		if !result.Success {
			w.WriteHeader(http.StatusInternalServerError)
		}
		json.NewEncoder(w).Encode(resp)
	}
}
