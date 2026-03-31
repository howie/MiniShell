package main

// containsStr reports whether val exists in list (exact string match).
func containsStr(list []string, val string) bool {
	for _, v := range list {
		if v == val {
			return true
		}
	}
	return false
}
