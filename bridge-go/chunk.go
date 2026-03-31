package main

import "strings"

// Chunk splits text into pieces of at most maxLen runes, preferring to break
// on newline boundaries. Each chunk keeps the trailing newline when split
// there. If no newline is found within maxLen, a hard split occurs.
func Chunk(text string, maxLen int) []string {
	if maxLen <= 0 {
		return []string{text}
	}
	if text == "" {
		return []string{""}
	}
	runes := []rune(text)
	if len(runes) <= maxLen {
		return []string{text}
	}

	var chunks []string
	remaining := runes
	for len(remaining) > 0 {
		if len(remaining) <= maxLen {
			chunks = append(chunks, string(remaining))
			break
		}
		window := string(remaining[:maxLen])
		idx := strings.LastIndex(window, "\n")
		var splitAt int
		if idx > 0 {
			splitAt = idx + 1 // include the newline in the current chunk
		} else {
			splitAt = maxLen
		}
		chunks = append(chunks, string(remaining[:splitAt]))
		remaining = remaining[splitAt:]
	}
	return chunks
}
