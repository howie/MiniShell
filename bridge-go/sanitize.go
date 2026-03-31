package main

import "strings"

// sanitizePrompt strips invisible chars, trims whitespace, and returns the
// cleaned prompt along with whether it was truncated to the 10k-rune limit.
func sanitizePrompt(raw string) (prompt string, truncated bool) {
	prompt, truncated = Sanitize(raw, 0)
	prompt = strings.TrimSpace(prompt)
	return
}

const defaultMaxRunes = 10_000

// Sanitize strips invisible/zero-width Unicode characters and NUL bytes from
// text, then truncates to maxRunes runes. Returns the cleaned string and
// whether truncation occurred.
func Sanitize(text string, maxRunes int) (safe string, truncated bool) {
	if maxRunes <= 0 {
		maxRunes = defaultMaxRunes
	}
	// Strip invisible characters and NUL.
	cleaned := strings.Map(func(r rune) rune {
		switch {
		case r == 0x0000: // NUL
			return -1
		case r == 0x00AD: // soft hyphen
			return -1
		case r >= 0x200B && r <= 0x200D: // zero-width space/non-joiner/joiner
			return -1
		case r == 0x200E || r == 0x200F: // LTR/RTL mark
			return -1
		case r >= 0x202A && r <= 0x202E: // bidi embedding/override
			return -1
		case r >= 0x2060 && r <= 0x2064: // word joiner etc.
			return -1
		case r >= 0x2066 && r <= 0x2069: // bidi isolate
			return -1
		case r == 0xFEFF: // BOM / zero-width no-break space
			return -1
		default:
			return r
		}
	}, text)

	runes := []rune(cleaned)
	if len(runes) > maxRunes {
		return string(runes[:maxRunes]), true
	}
	return cleaned, false
}
