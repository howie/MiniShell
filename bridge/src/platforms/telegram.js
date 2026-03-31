'use strict';

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

  const { Bot } = require('grammy');
  const { HttpsProxyAgent } = require('https-proxy-agent');

  const {
    token,
    allowed_chat_ids = [],
    allowed_user_ids = [],
  } = config;

  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy;
  let agent;
  if (proxyUrl) {
    try {
      agent = new HttpsProxyAgent(proxyUrl);
      console.log(`[telegram] Using proxy: ${proxyUrl}`);
    } catch (err) {
      console.error(`[telegram] Invalid proxy URL in HTTPS_PROXY "${proxyUrl}": ${err.message}`);
      return null;
    }
  }

  const bot = new Bot(token, {
    client: { baseFetchConfig: { agent } },
  });

  /**
   * Check access and handle a prompt.
   */
  async function handleMessage(ctx) {
    const chatId = ctx.chat && ctx.chat.id;
    const userId = ctx.from && ctx.from.id;
    const text = ctx.message?.text || '';

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

    let result;
    try {
      result = await execute(prompt, null);
    } catch (err) {
      console.error('[telegram] execute() threw:', err);
      try {
        await ctx.api.editMessageText(chatId, processingMsg.message_id, '❌ 執行錯誤，請稍後再試。');
      } catch (_) { /* best-effort */ }
      return;
    }

    const output = result.success
      ? result.output || '(no output)'
      : `Error: execution failed.\n${result.output}`;

    const chunks = chunk(output, TELEGRAM_MAX_LEN);

    // Edit the processing placeholder with the first chunk
    try {
      await ctx.api.editMessageText(chatId, processingMsg.message_id, chunks[0]);
    } catch (err) {
      console.error('[telegram] Failed to edit processing message:', err);
      // Fallback: send as new message so the result isn't lost
      try {
        await ctx.reply(chunks[0]);
      } catch (e) {
        console.error('[telegram] Failed to send fallback reply:', e);
      }
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
  bot.command('claude', async (ctx) => {
    if (ctx.chat.type !== 'private') return;
    await handleMessage(ctx);
  });

  // Handle plain messages in private chats
  bot.on('message:text', async (ctx) => {
    if (ctx.chat.type !== 'private') return;
    if (/^\/claude(\s|$)/i.test(ctx.message.text)) return; // handled by command
    await handleMessage(ctx);
  });

  bot.catch((err) => {
    const updateInfo = err.ctx?.update ? JSON.stringify(err.ctx.update) : 'N/A';
    console.error('[telegram] Bot error — update:', updateInfo);
    console.error('[telegram] Bot error — cause:', err.error || err);
  });

  await new Promise((resolve, reject) => {
    bot.start({
      drop_pending_updates: true,
      onStart: () => {
        console.log('[telegram] Bot started (long polling).');
        resolve();
      },
    }).catch(reject);
  });

  return bot;
}

module.exports = { start };
