'use strict';

/**
 * Split a long string into chunks no longer than maxLen characters.
 * Tries to split at newline boundaries when possible.
 * @param {string} text - The text to split.
 * @param {number} maxLen - Maximum characters per chunk.
 * @returns {string[]}
 */
function chunk(text, maxLen) {
  if (!text || text.length === 0) return [''];
  if (text.length <= maxLen) return [text];

  const chunks = [];
  let remaining = text;

  while (remaining.length > 0) {
    if (remaining.length <= maxLen) {
      chunks.push(remaining);
      break;
    }

    // Try to find a newline within the allowed window to split cleanly
    const window = remaining.slice(0, maxLen);
    const lastNewline = window.lastIndexOf('\n');

    let splitAt;
    if (lastNewline > 0) {
      // Include the newline character in the current chunk
      splitAt = lastNewline + 1;
    } else {
      // No newline found — hard-split at maxLen
      splitAt = maxLen;
    }

    chunks.push(remaining.slice(0, splitAt));
    remaining = remaining.slice(splitAt);
  }

  return chunks;
}

module.exports = { chunk };
