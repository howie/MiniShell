'use strict';

const { App } = require('@slack/bolt');
const { HttpsProxyAgent } = require('https-proxy-agent');
const { execute } = require('../executor');
const { sanitize } = require('../utils/sanitize');
const { chunk } = require('../utils/chunker');

const SLACK_MAX_LEN = 2900;

/**
 * Start the Slack platform adapter (Socket Mode).
 * @param {object} config - Slack configuration block from bridge.config.json.
 */
async function start(config) {
  if (!config || !config.enabled || !config.bot_token) {
    console.log('[slack] Disabled or no token — skipping.');
    return null;
  }

  const {
    bot_token,
    app_token,
    signing_secret,
    allowed_channel_ids = [],
    allowed_user_ids = [],
  } = config;

  if (!app_token) {
    console.error('[slack] app_token is required for Socket Mode — skipping.');
    return null;
  }

  const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy;
  let agent;
  if (proxyUrl) {
    try {
      agent = new HttpsProxyAgent(proxyUrl);
      console.log(`[slack] Using proxy: ${proxyUrl}`);
    } catch (err) {
      console.error(`[slack] Invalid proxy URL in HTTPS_PROXY "${proxyUrl}": ${err.message}`);
      return null;
    }
  }

  const app = new App({
    token: bot_token,
    appToken: app_token,
    signingSecret: signing_secret,
    socketMode: true,
    agent,
  });

  /**
   * Check access and handle a prompt from a Slack event.
   */
  async function handleEvent({ event, say, client }) {
    const channelId = event.channel;
    const userId = event.user;
    const text = event.text || '';

    // Channel whitelist check
    if (allowed_channel_ids.length > 0 && !allowed_channel_ids.includes(channelId)) {
      return;
    }

    // User whitelist check
    if (allowed_user_ids.length > 0 && !allowed_user_ids.includes(userId)) {
      return;
    }

    // Strip bot mention from text
    const rawPrompt = text.replace(/<@[A-Z0-9]+>/g, '').trim();
    if (!rawPrompt) return;

    const { safe: prompt } = sanitize(rawPrompt);
    if (!prompt.trim()) return;

    // Send processing placeholder
    let processingTs;
    try {
      const sent = await say('⏳ 處理中...');
      processingTs = sent.ts;
    } catch (err) {
      console.error('[slack] Failed to send processing message:', err);
      return;
    }

    let result;
    try {
      result = await execute(prompt, null);
    } catch (err) {
      console.error('[slack] execute() threw:', err);
      try {
        await client.chat.update({ channel: channelId, ts: processingTs, text: '❌ 執行錯誤，請稍後再試。' });
      } catch (_) { /* best-effort */ }
      return;
    }

    const output = result.success
      ? result.output || '(no output)'
      : `Error: execution failed.\n${result.output}`;

    const chunks = chunk(output, SLACK_MAX_LEN);

    // Update the placeholder with the first chunk
    try {
      await client.chat.update({
        channel: channelId,
        ts: processingTs,
        text: chunks[0],
      });
    } catch (err) {
      console.error('[slack] Failed to update processing message:', err);
      // Fallback: send as new message so the result isn't lost
      try {
        await say(chunks[0]);
      } catch (e) {
        console.error('[slack] Failed to send fallback message:', e);
      }
    }

    // Post remaining chunks
    for (let i = 1; i < chunks.length; i++) {
      try {
        await say(chunks[i]);
      } catch (err) {
        console.error(`[slack] Failed to send chunk ${i}:`, err);
      }
    }
  }

  // Respond to app_mention events
  app.event('app_mention', async ({ event, say, client, ack }) => {
    if (typeof ack === 'function') await ack();
    await handleEvent({ event, say, client });
  });

  // Respond to DMs (message events in im channels)
  app.message(async ({ message, say, client, ack }) => {
    if (typeof ack === 'function') await ack();
    // Only handle DMs
    if (message.channel_type !== 'im') return;
    await handleEvent({ event: message, say, client });
  });

  app.error((err) => {
    console.error('[slack] App error:', err);
  });

  await app.start();
  console.log('[slack] App started (Socket Mode).');

  return app;
}

module.exports = { start };
