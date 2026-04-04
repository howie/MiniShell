package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"strings"
	"time"
)

const (
	maxOutputBytes = 2 * 1024 * 1024 // 2 MB
	truncatedMsg   = "\n[output truncated, exceeded 2MB limit]"
)

// ExecResult holds the outcome of a claude execution.
type ExecResult struct {
	Success    bool
	Output     string
	TimedOut   bool
	Truncated  bool
	DurationMs int64
}

// Execute runs claude with the given prompt.
// If cfg.SSHHost is set, the command is sent via SSH into the claude-dev sandbox.
// The prompt is passed via stdin to avoid shell injection.
func Execute(ctx context.Context, cfg ExecutorConfig, prompt string) ExecResult {
	start := time.Now()

	timeout := time.Duration(cfg.TimeoutMs) * time.Millisecond
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	var cmd *exec.Cmd
	if cfg.SSHHost != "" {
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
			output = "(timed out - no output)"
		} else {
			output += "\n[execution timed out]"
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

// sanitizePrompt strips invisible chars, trims whitespace, and returns the
// cleaned prompt along with whether it was truncated to the 10k-rune limit.
func sanitizePrompt(raw string) (prompt string, truncated bool) {
	const maxRunes = 10_000

	// Strip invisible characters and NUL.
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r == 0x0000: // NUL
			return -1
		case r == 0x00AD: // soft hyphen
			return -1
		case r >= 0x200B && r <= 0x200D: // zero-width space/non-joiner/joiner
			return -1
		case r == 0x200E || r == 0x200F: // LTR/RTL mark
			return -1
		case r >= 0x202A && r <= 0x202E: // bidi embedding/override
			return -1
		case r >= 0x2060 && r <= 0x2064: // word joiner etc.
			return -1
		case r >= 0x2066 && r <= 0x2069: // bidi isolate
			return -1
		case r == 0xFEFF: // BOM / zero-width no-break space
			return -1
		default:
			return r
		}
	}, raw)

	runes := []rune(cleaned)
	if len(runes) > maxRunes {
		return strings.TrimSpace(string(runes[:maxRunes])), true
	}
	return strings.TrimSpace(cleaned), false
}
