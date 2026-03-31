package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"time"
)

const (
	maxOutputBytes = 2 * 1024 * 1024 // 2 MB
	truncatedMsg   = "\n[輸出已截斷，超過 2MB 上限]"
)

// ExecResult holds the outcome of a claude-sandbox execution.
type ExecResult struct {
	Success    bool
	Output     string
	TimedOut   bool
	Truncated  bool
	DurationMs int64
}

// FormatForDisplay returns a user-facing string from the result.
func (r ExecResult) FormatForDisplay() string {
	output := r.Output
	if output == "" {
		output = "(no output)"
	}
	if !r.Success {
		return "Error: execution failed.\n" + output
	}
	return output
}

// Execute runs claude-sandbox with the given prompt.
// If cfg.SSHHost is set, the command is sent via SSH.
// The prompt is passed via stdin to avoid shell injection.
// The execution is bounded by both the parent ctx and cfg.TimeoutMs.
func Execute(ctx context.Context, cfg ExecutorConfig, prompt string) ExecResult {
	start := time.Now()

	timeout := time.Duration(cfg.TimeoutMs) * time.Millisecond
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	var cmd *exec.Cmd
	if cfg.SSHHost != "" {
		// Pass prompt via stdin to avoid shell injection through SSH argument joining.
		cmd = exec.CommandContext(ctx, "ssh", cfg.SSHHost,
			cfg.ClaudeBinary, "--output-format", "text")
	} else {
		cmd = exec.CommandContext(ctx, cfg.ClaudeBinary, "--output-format", "text")
	}

	cmd.Stdin = bytes.NewBufferString(prompt)

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		slog.Error("executor: StdoutPipe failed", "err", err, "ssh_host", cfg.SSHHost)
		return ExecResult{
			Output:     fmt.Sprintf("Failed to start process: %v", err),
			DurationMs: time.Since(start).Milliseconds(),
		}
	}
	var stderrBuf bytes.Buffer
	cmd.Stderr = &stderrBuf

	if err := cmd.Start(); err != nil {
		slog.Error("executor: cmd.Start failed", "err", err, "ssh_host", cfg.SSHHost)
		return ExecResult{
			Output:     fmt.Sprintf("Failed to start process: %v", err),
			DurationMs: time.Since(start).Milliseconds(),
		}
	}

	// Read stdout with 2MB cap.
	limited := io.LimitReader(stdout, maxOutputBytes+1)
	raw, readErr := io.ReadAll(limited)
	if readErr != nil {
		slog.Warn("executor: read stdout error", "err", readErr)
	}

	truncated := len(raw) > maxOutputBytes
	if truncated {
		raw = raw[:maxOutputBytes]
	}

	waitErr := cmd.Wait()
	duration := time.Since(start).Milliseconds()

	timedOut := ctx.Err() == context.DeadlineExceeded

	if stderrBuf.Len() > 0 {
		if waitErr != nil {
			slog.Error("executor stderr", "output", stderrBuf.String(), "ssh_host", cfg.SSHHost)
		} else {
			slog.Debug("executor stderr", "output", stderrBuf.String())
		}
	}

	output := string(raw)
	if truncated {
		output += truncatedMsg
	}
	if timedOut {
		if output == "" {
			output = "(timed out — no output)"
		} else {
			output += "\n[執行逾時]"
		}
	}

	success := waitErr == nil && !timedOut

	return ExecResult{
		Success:    success,
		Output:     output,
		TimedOut:   timedOut,
		Truncated:  truncated,
		DurationMs: duration,
	}
}
