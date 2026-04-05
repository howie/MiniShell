package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// MCP JSON-RPC types for the streamable-http transport.
// See: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports#streamable-http

type jsonRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type jsonRPCResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      any         `json:"id,omitempty"`
	Result  any         `json:"result,omitempty"`
	Error   *rpcError   `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// MCP protocol types.

type mcpServerInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

type mcpCapabilities struct {
	Tools *struct{} `json:"tools,omitempty"`
}

type mcpInitializeResult struct {
	ProtocolVersion string          `json:"protocolVersion"`
	Capabilities    mcpCapabilities `json:"capabilities"`
	ServerInfo      mcpServerInfo   `json:"serverInfo"`
}

type mcpTool struct {
	Name        string          `json:"name"`
	Description string          `json:"description"`
	InputSchema json.RawMessage `json:"inputSchema"`
}

type mcpToolsListResult struct {
	Tools []mcpTool `json:"tools"`
}

type mcpCallToolParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments"`
}

type mcpContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

type mcpCallToolResult struct {
	Content []mcpContent `json:"content"`
	IsError bool         `json:"isError,omitempty"`
}

// Tool input schema for claude_code.
var claudeCodeInputSchema = json.RawMessage(`{
	"type": "object",
	"properties": {
		"prompt": {
			"type": "string",
			"description": "The coding task or question for Claude Code"
		},
		"timeout_ms": {
			"type": "number",
			"description": "Optional timeout in ms (default 300000)"
		}
	},
	"required": ["prompt"]
}`)

func handleMCP(execCfg ExecutorConfig, pool *SessionPool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req jsonRPCRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeRPCError(w, nil, -32700, "Parse error")
			return
		}

		if req.JSONRPC != "2.0" {
			writeRPCError(w, req.ID, -32600, "Invalid Request: jsonrpc must be 2.0")
			return
		}

		switch req.Method {
		case "initialize":
			writeRPCResult(w, req.ID, mcpInitializeResult{
				ProtocolVersion: "2025-03-26",
				Capabilities:    mcpCapabilities{Tools: &struct{}{}},
				ServerInfo: mcpServerInfo{
					Name:    "acp-gateway",
					Version: "1.0.0",
				},
			})

		case "notifications/initialized":
			// Client notification, no response needed for notifications.
			w.WriteHeader(http.StatusAccepted)

		case "tools/list":
			writeRPCResult(w, req.ID, mcpToolsListResult{
				Tools: []mcpTool{
					{
						Name:        "claude_code",
						Description: "Send a coding task to Claude Code (Anthropic Claude Opus/Sonnet). Use for complex coding, debugging, code review, or tasks requiring deep reasoning beyond local model capabilities.",
						InputSchema: claudeCodeInputSchema,
					},
				},
			})

		case "tools/call":
			var params mcpCallToolParams
			if err := json.Unmarshal(req.Params, &params); err != nil {
				writeRPCError(w, req.ID, -32602, "Invalid params")
				return
			}

			if params.Name != "claude_code" {
				writeRPCError(w, req.ID, -32602, "Unknown tool: "+params.Name)
				return
			}

			// Parse tool arguments.
			var args struct {
				Prompt    string `json:"prompt"`
				TimeoutMs int    `json:"timeout_ms"`
			}
			if err := json.Unmarshal(params.Arguments, &args); err != nil {
				writeRPCError(w, req.ID, -32602, "Invalid tool arguments")
				return
			}

			if args.Prompt == "" {
				writeRPCError(w, req.ID, -32602, "prompt is required")
				return
			}

			prompt, truncated := sanitizePrompt(args.Prompt)
			if truncated {
				slog.Warn("mcp: prompt truncated", "original_len", len(args.Prompt))
			}

			cfg := execCfg
			if args.TimeoutMs > 0 {
				cfg.TimeoutMs = args.TimeoutMs
			}

			result := Execute(r.Context(), cfg, prompt)

			toolResult := mcpCallToolResult{
				Content: []mcpContent{{Type: "text", Text: result.Output}},
				IsError: !result.Success,
			}
			writeRPCResult(w, req.ID, toolResult)

		case "ping":
			writeRPCResult(w, req.ID, struct{}{})

		default:
			writeRPCError(w, req.ID, -32601, "Method not found: "+req.Method)
		}
	}
}

// handleMCPGet handles GET /mcp for SSE-based server-to-client streaming.
// For v1, we return 405 as we don't support SSE streaming yet.
func handleMCPGet() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, `{"error":"SSE streaming not supported in v1"}`, http.StatusMethodNotAllowed)
	}
}

// handleMCPDelete handles DELETE /mcp for session cleanup.
func handleMCPDelete() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}
}

func writeRPCResult(w http.ResponseWriter, id any, result any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(jsonRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	}); err != nil {
		slog.Error("mcp: failed to encode JSON-RPC result", "err", err)
	}
}

func writeRPCError(w http.ResponseWriter, id any, code int, message string) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(jsonRPCResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error:   &rpcError{Code: code, Message: message},
	}); err != nil {
		slog.Error("mcp: failed to encode JSON-RPC error", "err", err)
	}
}
