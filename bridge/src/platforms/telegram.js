'use strict';

const TelegramBot = require('node-telegram-bot-api');
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

  const bot = new TelegramBot(token, { polling: true });

  console.log('[telegram] Bot started (polling mode).');

  /**
   * Handle an incoming message object.
   */
  async function handleMessage(msg) {
    const chatId = msg.chat && msg.chat.id;
    const userId = msg.from && msg.from.id;
    const text = msg.text || '';

    // Chat whitelist check
    if (allowed_chat_ids.length > 0 && !allowed_chat_ids.map(String).includes(String(chatId))) {
      return;
    }

    // User whitelist check (empty = allow all)
    if (allowed_user_ids.length > 0 && !allowed_user_ids.map(String).includes(String(userId))) {
      return;
    }

    // Extract prompt: strip /claude prefix if present
    let rawPrompt = text.replace(/^\/claude\s*/i, '').trim();
    if (!rawPrompt) return;

    const { safe: prompt } = sanitize(rawPrompt);
    if (!prompt.trim()) return;

    let processingMsgId;
    try {
      const sent = await bot.sendMessage(chatId, '⏳ 處理中...');
      processingMsgId = sent.message_id;
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
      await bot.editMessageText(chunks[0], {
        chat_id: chatId,
        message_id: processingMsgId,
      });
    } catch (err) {
      console.error('[telegram] Failed to edit processing message:', err);
    }

    // Send remaining chunks as new messages
    for (let i = 1; i < chunks.length; i++) {
      try {
        await bot.sendMessage(chatId, chunks[i]);
      } catch (err) {
        console.error(`[telegram] Failed to send chunk ${i}:`, err);
      }
    }
  }

  // Listen to regular text messages (private chats only)
  bot.on('message', (msg) => {
    if (msg.chat.type !== 'private') return;
    if (!msg.text) return;
    // Skip /claude command messages — handled by onText below
    if (/^\/claude(\s|$)/i.test(msg.text)) return;
    handleMessage(msg);
  });

  // Listen to /claude command specifically
  bot.onText(/^\/claude(\s|$)/i, (msg) => {
    handleMessage(msg);
  });

  bot.on('polling_error', (err) => {
    console.error('[telegram] Polling error:', err.message || err);
  });

  bot.on('error', (err) => {
    console.error('[telegram] Bot error:', err);
  });

  return bot;
}

module.exports = { start };
