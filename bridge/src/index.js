'use strict';

const fs = require('fs');
const path = require('path');

const CONFIG_PATH = '/sandbox/messaging-bridge/bridge.config.json';

async function main() {
  // Load configuration
  let config;
  try {
    const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
    config = JSON.parse(raw);
  } catch (err) {
    console.error(`[bridge] Failed to read config from ${CONFIG_PATH}:`, err.message);
    process.exit(1);
  }

  // Load platform adapters
  const discord = require('./platforms/discord');
  const telegram = require('./platforms/telegram');
  const slack = require('./platforms/slack');

  // Track running platform instances for graceful shutdown
  const instances = {};

  // Start platforms
  const results = await Promise.allSettled([
    discord.start(config.discord || {}).then((inst) => { instances.discord = inst; }),
    telegram.start(config.telegram || {}).then((inst) => { instances.telegram = inst; }),
    slack.start(config.slack || {}).then((inst) => { instances.slack = inst; }),
  ]);

  results.forEach((r, i) => {
    if (r.status === 'rejected') {
      const names = ['discord', 'telegram', 'slack'];
      console.error(`[bridge] Platform ${names[i]} failed to start:`, r.reason);
    }
  });

  // Check if at least one platform is active
  const anyActive = Object.values(instances).some((inst) => inst != null);
  if (!anyActive) {
    console.warn('[bridge] WARNING: No messaging platforms are enabled. Exiting.');
    process.exit(1);
  }

  console.log('[bridge] Messaging bridge running.');

  // Graceful shutdown handler
  async function shutdown(signal) {
    console.log(`[bridge] Received ${signal} — shutting down...`);

    const shutdownTasks = [];

    if (instances.discord) {
      shutdownTasks.push(
        instances.discord.destroy().catch((e) =>
          console.error('[bridge] Error destroying Discord client:', e)
        )
      );
    }

    if (instances.telegram) {
      shutdownTasks.push(
        instances.telegram.stop().catch((e) =>
          console.error('[bridge] Error stopping Telegram bot:', e)
        )
      );
    }

    if (instances.slack) {
      shutdownTasks.push(
        instances.slack.stop().catch((e) =>
          console.error('[bridge] Error stopping Slack app:', e)
        )
      );
    }

    await Promise.allSettled(shutdownTasks);
    console.log('[bridge] Shutdown complete.');
    process.exit(0);
  }

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

main().catch((err) => {
  console.error('[bridge] Fatal error:', err);
  process.exit(1);
});
