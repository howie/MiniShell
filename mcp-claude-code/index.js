#!/usr/bin/env node
/**
 * mcp-claude-code — Stdio MCP server (fallback for OpenClaw)
 *
 * Reads JSON-RPC requests from stdin, proxies claude_code tool calls to
 * the ACP Gateway HTTP API, and writes JSON-RPC responses to stdout.
 *
 * Environment variables:
 *   ACP_GATEWAY_URL   — Gateway base URL (default: http://host.docker.internal:7865)
 *   ACP_GATEWAY_TOKEN — Bearer token for gateway authentication (required)
 */

import { createInterface } from "node:readline";
import { stdout, stderr, env, exit } from "node:process";

const GATEWAY_URL = env.ACP_GATEWAY_URL || "http://host.docker.internal:7865";
const GATEWAY_TOKEN = env.ACP_GATEWAY_TOKEN || "";

if (!GATEWAY_TOKEN) {
  stderr.write("ERROR: ACP_GATEWAY_TOKEN env var is required\n");
  exit(1);
}

const TOOL_SCHEMA = {
  type: "object",
  properties: {
    prompt: {
      type: "string",
      description: "The coding task or question for Claude Code",
    },
    timeout_ms: {
      type: "number",
      description: "Optional timeout in ms (default 300000)",
    },
  },
  required: ["prompt"],
};

function sendResponse(id, result) {
  const msg = JSON.stringify({ jsonrpc: "2.0", id, result });
  stdout.write(msg + "\n");
}

function sendError(id, code, message) {
  const msg = JSON.stringify({
    jsonrpc: "2.0",
    id,
    error: { code, message },
  });
  stdout.write(msg + "\n");
}

async function callGateway(prompt, timeoutMs) {
  const body = { prompt };
  if (timeoutMs > 0) body.timeout_ms = timeoutMs;

  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(),
    (timeoutMs || 300000) + 30000,
  );

  try {
    const resp = await fetch(`${GATEWAY_URL}/v1/prompt`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${GATEWAY_TOKEN}`,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    const data = await resp.json();
    return data;
  } finally {
    clearTimeout(timer);
  }
}

async function handleRequest(req) {
  if (req.jsonrpc !== "2.0") {
    sendError(req.id, -32600, "Invalid Request");
    return;
  }

  switch (req.method) {
    case "initialize":
      sendResponse(req.id, {
        protocolVersion: "2025-03-26",
        capabilities: { tools: {} },
        serverInfo: { name: "mcp-claude-code", version: "1.0.0" },
      });
      break;

    case "notifications/initialized":
      // No response for notifications.
      break;

    case "tools/list":
      sendResponse(req.id, {
        tools: [
          {
            name: "claude_code",
            description:
              "Send a coding task to Claude Code (Anthropic Claude Opus/Sonnet). Use for complex coding, debugging, code review, or tasks requiring deep reasoning beyond local model capabilities.",
            inputSchema: TOOL_SCHEMA,
          },
        ],
      });
      break;

    case "tools/call": {
      const params = req.params || {};
      if (params.name !== "claude_code") {
        sendError(req.id, -32602, `Unknown tool: ${params.name}`);
        return;
      }

      const args = params.arguments || {};
      if (!args.prompt) {
        sendError(req.id, -32602, "prompt is required");
        return;
      }

      try {
        const result = await callGateway(args.prompt, args.timeout_ms);
        sendResponse(req.id, {
          content: [{ type: "text", text: result.output || "(no output)" }],
          isError: !result.success,
        });
      } catch (err) {
        sendResponse(req.id, {
          content: [{ type: "text", text: `Gateway error: ${err.message}` }],
          isError: true,
        });
      }
      break;
    }

    case "ping":
      sendResponse(req.id, {});
      break;

    default:
      sendError(req.id, -32601, `Method not found: ${req.method}`);
  }
}

// Read JSON-RPC messages from stdin, one per line.
const rl = createInterface({ input: process.stdin, terminal: false });

rl.on("line", async (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    const req = JSON.parse(trimmed);
    await handleRequest(req);
  } catch (err) {
    sendError(null, -32700, "Parse error");
  }
});

rl.on("close", () => {
  exit(0);
});

stderr.write("[mcp-claude-code] stdio MCP server started\n");
