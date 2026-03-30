'use strict';

const { Bot } = require('grammy');
const { HttpsProxyAgent } = require('https-proxy-agent');
const { execute } = require('../executor');
const { sanitize } = require('../utils/sanitize');
const { chunk } = require('../utils/chunker');

const TELEGRAM_MAX_LEN = 4000;

/**
 * Start the Telegram platform adapter.
 * @param {object} config - Telegram configuration block from bridge.config.json.
 */
async function start(config) {
  if (!config || !config.enabled || !config.token) {
    console.log('[telegram] Disabled or no token — skipping.');
    return null;
  }

  const {
    token,
    allowed_chat_ids = [],
    allowed_user_ids = [],
  } = config;

  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy;
  const agent = proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;

  const bot = new Bot(token, {
    client: { baseFetchConfig: { agent } },
  });

  /**
   * Check access and handle a prompt.
   */
  async function handleMessage(ctx) {
    const chatId = ctx.chat && ctx.chat.id;
    const userId = ctx.from && ctx.from.id;
    const text = ctx.message && ctx.message.text || '';

    // Chat whitelist check
    if (allowed_chat_ids.length > 0 && !allowed_chat_ids.map(String).includes(String(chatId))) {
      return;
    }

    // User whitelist check
    if (allowed_user_ids.length > 0 && !allowed_user_ids.map(String).includes(String(userId))) {
      return;
    }

    // Strip /claude prefix if present
    let rawPrompt = text.replace(/^\/claude\s*/i, '').trim();
    if (!rawPrompt) return;

    const { safe: prompt } = sanitize(rawPrompt);
    if (!prompt.trim()) return;

    let processingMsg;
    try {
      processingMsg = await ctx.reply('⏳ 處理中...');
    } catch (err) {
      console.error('[telegram] Failed to send processing message:', err);
      return;
    }

    const result = await execute(prompt, null);

    const output = result.success
      ? result.output || '(no output)'
      : `Error: execution failed.\n${result.output}`;

    const chunks = chunk(output, TELEGRAM_MAX_LEN);

    // Edit the processing placeholder with the first chunk
    try {
      await ctx.api.editMessageText(chatId, processingMsg.message_id, chunks[0]);
    } catch (err) {
      console.error('[telegram] Failed to edit processing message:', err);
    }

    // Send remaining chunks
    for (let i = 1; i < chunks.length; i++) {
      try {
        await ctx.reply(chunks[i]);
      } catch (err) {
        console.error(`[telegram] Failed to send chunk ${i}:`, err);
      }
    }
  }

  // Handle /claude command (private chats only)
  bot.command('claude', (ctx) => {
    if (ctx.chat.type !== 'private') return;
    handleMessage(ctx);
  });

  // Handle plain messages in private chats
  bot.on('message:text', (ctx) => {
    if (ctx.chat.type !== 'private') return;
    if (/^\/claude(\s|$)/i.test(ctx.message.text)) return; // handled by command
    handleMessage(ctx);
  });

  bot.catch((err) => {
    console.error('[telegram] Bot error:', err.message || err);
  });

  bot.start({ drop_pending_updates: true })
    .then(() => console.log('[telegram] Bot started (long polling).'))
    .catch((err) => console.error('[telegram] bot.start() error:', err.message || err));

  return bot;
}

module.exports = { start };
