'use strict';

const { spawn } = require('child_process');

const CLAUDE_BIN = '/sandbox/.local/bin/claude-sandbox';
const DEFAULT_TIMEOUT_MS = 300000; // 5 minutes
const MAX_OUTPUT_BYTES = 2 * 1024 * 1024; // 2MB

/**
 * Execute a prompt via the claude-sandbox binary.
 *
 * @param {string} prompt - The user prompt to pass to Claude.
 * @param {function(string): void} onChunk - Streaming callback; called with
 *   each stdout chunk as it arrives.
 * @param {number} [timeoutMs] - Timeout in milliseconds (default 300000).
 * @returns {Promise<{ success: boolean, output: string, duration_ms: number }>}
 */
async function execute(prompt, onChunk, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const startTime = Date.now();

  return new Promise((resolve) => {
    const args = ['-p', prompt, '--output-format', 'text'];

    let child;
    try {
      child = spawn(CLAUDE_BIN, args, {
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (err) {
      console.error('[executor] Failed to spawn claude-sandbox:', err);
      resolve({
        success: false,
        output: 'Failed to start claude-sandbox process.',
        duration_ms: Date.now() - startTime,
      });
      return;
    }

    let outputBuffer = '';
    let timedOut = false;
    let outputTruncated = false;

    const timer = setTimeout(() => {
      timedOut = true;
      console.error('[executor] Timeout — sending SIGTERM to child process');
      child.kill('SIGTERM');
    }, timeoutMs);

    child.stdout.on('data', (data) => {
      if (outputTruncated) return;
      const text = data.toString();
      outputBuffer += text;
      if (Buffer.byteLength(outputBuffer, 'utf8') > MAX_OUTPUT_BYTES) {
        outputTruncated = true;
        console.error('[executor] Output exceeded 2MB limit — sending SIGTERM to child process');
        child.kill('SIGTERM');
        return;
      }
      if (typeof onChunk === 'function') {
        onChunk(text);
      }
    });

    child.stderr.on('data', (data) => {
      console.error('[executor] stderr:', data.toString().trimEnd());
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      const duration_ms = Date.now() - startTime;

      if (timedOut) {
        resolve({
          success: false,
          output: outputBuffer || '(timed out — no output)',
          duration_ms,
        });
        return;
      }

      const finalOutput = outputTruncated
        ? outputBuffer + '\n[輸出已截斷，超過 2MB 上限]'
        : outputBuffer;

      resolve({
        success: code === 0,
        output: finalOutput,
        duration_ms,
      });
    });

    child.on('error', (err) => {
      clearTimeout(timer);
      console.error('[executor] Process error:', err);
      resolve({
        success: false,
        output: `Process error: ${err.message}`,
        duration_ms: Date.now() - startTime,
      });
    });
  });
}

module.exports = { execute };
