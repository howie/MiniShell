'use strict';

// Zero-width and invisible characters to strip
const ZERO_WIDTH_RE = /[\u200B-\u200D\uFEFF\u00AD\u200E\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069]/g;

/**
 * Sanitize user input text.
 * @param {string} text - Raw input text.
 * @param {number} maxLength - Maximum allowed length (default 10000).
 * @returns {{ safe: string, truncated: boolean }}
 */
function sanitize(text, maxLength = 10000) {
  if (typeof text !== 'string') {
    text = String(text);
  }

  // Remove zero-width / invisible characters
  let safe = text.replace(ZERO_WIDTH_RE, '');

  // Remove NUL bytes
  safe = safe.replace(/\x00/g, '');

  let truncated = false;
  if (safe.length > maxLength) {
    safe = safe.slice(0, maxLength);
    truncated = true;
  }

  return { safe, truncated };
}

module.exports = { sanitize };
