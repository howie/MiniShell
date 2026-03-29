'use strict';

const { Client, GatewayIntentBits } = require('discord.js');
const { execute } = require('../executor');
const { sanitize } = require('../utils/sanitize');
const { chunk } = require('../utils/chunker');

const DISCORD_MAX_LEN = 1990;

/**
 * Start the Discord platform adapter.
 * @param {object} config - Discord configuration block from bridge.config.json.
 */
async function start(config) {
  if (!config || !config.enabled || !config.token) {
    console.log('[discord] Disabled or no token — skipping.');
    return null;
  }

  const {
    token,
    command_prefix = '!claude ',
    allowed_channel_ids = [],
    allowed_user_ids = [],
  } = config;

  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
    ],
  });

  client.on('ready', () => {
    console.log(`[discord] Logged in as ${client.user.tag}`);
  });

  client.on('messageCreate', async (message) => {
    // Ignore bots
    if (message.author.bot) return;

    // Channel check
    if (allowed_channel_ids.length > 0 && !allowed_channel_ids.includes(message.channel.id)) {
      return;
    }

    // User check
    if (allowed_user_ids.length > 0 && !allowed_user_ids.includes(message.author.id)) {
      return;
    }

    const botMention = `<@${client.user.id}>`;
    const botMentionNick = `<@!${client.user.id}>`;
    const isMentioned =
      message.content.startsWith(botMention) ||
      message.content.startsWith(botMentionNick);
    const isPrefixed = message.content.startsWith(command_prefix);

    if (!isPrefixed && !isMentioned) return;

    // Extract prompt
    let rawPrompt;
    if (isPrefixed) {
      rawPrompt = message.content.slice(command_prefix.length);
    } else {
      // Strip mention
      rawPrompt = message.content
        .replace(botMention, '')
        .replace(botMentionNick, '')
        .trim();
    }

    const { safe: prompt } = sanitize(rawPrompt);
    if (!prompt.trim()) return;

    let processingMsg;
    try {
      processingMsg = await message.reply('⏳ 處理中...');
    } catch (err) {
      console.error('[discord] Failed to send processing message:', err);
      return;
    }

    const result = await execute(prompt, null);

    const output = result.success
      ? result.output || '(no output)'
      : `Error: execution failed.\n${result.output}`;

    const chunks = chunk(output, DISCORD_MAX_LEN);

    // Edit the first placeholder message with the first chunk
    try {
      await processingMsg.edit(chunks[0]);
    } catch (err) {
      console.error('[discord] Failed to edit processing message:', err);
    }

    // Send remaining chunks as follow-up replies
    for (let i = 1; i < chunks.length; i++) {
      try {
        await message.reply(chunks[i]);
      } catch (err) {
        console.error(`[discord] Failed to send chunk ${i}:`, err);
      }
    }
  });

  client.on('error', (err) => {
    console.error('[discord] Client error:', err);
  });

  await client.login(token);
  return client;
}

module.exports = { start };
