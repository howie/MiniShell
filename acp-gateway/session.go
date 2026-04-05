package main

import (
	"context"
	"log/slog"
	"sync"
	"time"

	"crypto/rand"
	"encoding/hex"
)

// Exchange records a single prompt-response pair in a session.
type Exchange struct {
	Prompt   string    `json:"prompt"`
	Response string    `json:"response"`
	At       time.Time `json:"at"`
}

// Session tracks a multi-turn conversation with context accumulation.
type Session struct {
	ID           string     `json:"id"`
	CreatedAt    time.Time  `json:"created_at"`
	LastUsed     time.Time  `json:"last_used"`
	SystemPrompt string     `json:"system_prompt,omitempty"`
	History      []Exchange `json:"history"`
	mu           sync.Mutex
	maxHistory   int
}

// AddExchange appends a prompt-response pair, evicting oldest if over limit.
func (s *Session) AddExchange(prompt, response string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.History = append(s.History, Exchange{
		Prompt:   prompt,
		Response: response,
		At:       time.Now(),
	})
	s.LastUsed = time.Now()
	if len(s.History) > s.maxHistory {
		s.History = s.History[len(s.History)-s.maxHistory:]
	}
}

// SessionPool manages a pool of sessions with TTL-based cleanup.
type SessionPool struct {
	sessions    map[string]*Session
	mu          sync.RWMutex
	ttl         time.Duration
	maxSessions int
	maxHistory  int
}

// NewSessionPool creates a session pool with the given TTL and limits.
func NewSessionPool(ttl time.Duration, maxSessions, maxHistory int) *SessionPool {
	return &SessionPool{
		sessions:    make(map[string]*Session),
		ttl:         ttl,
		maxSessions: maxSessions,
		maxHistory:  maxHistory,
	}
}

// Count returns the number of active sessions.
func (p *SessionPool) Count() int {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return len(p.sessions)
}

// Create creates a new session. Returns an error if the pool is full.
func (p *SessionPool) Create(systemPrompt string) (*Session, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if len(p.sessions) >= p.maxSessions {
		return nil, ErrPoolExhausted
	}
	id := generateID()
	s := &Session{
		ID:           id,
		CreatedAt:    time.Now(),
		LastUsed:     time.Now(),
		SystemPrompt: systemPrompt,
		maxHistory:   p.maxHistory,
	}
	p.sessions[id] = s
	return s, nil
}

// Get retrieves a session by ID.
func (p *SessionPool) Get(id string) *Session {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return p.sessions[id]
}

// Delete removes a session by ID.
func (p *SessionPool) Delete(id string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if _, ok := p.sessions[id]; ok {
		delete(p.sessions, id)
		return true
	}
	return false
}

// CleanupLoop periodically removes idle sessions. Runs until ctx is cancelled.
func (p *SessionPool) CleanupLoop(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			p.cleanup()
		}
	}
}

func (p *SessionPool) cleanup() {
	p.mu.Lock()
	defer p.mu.Unlock()
	now := time.Now()
	// Collect expired IDs first to avoid deleting during iteration.
	var expired []string
	for id, s := range p.sessions {
		s.mu.Lock()
		idle := now.Sub(s.LastUsed) > p.ttl
		s.mu.Unlock()
		if idle {
			expired = append(expired, id)
		}
	}
	for _, id := range expired {
		delete(p.sessions, id)
		slog.Info("session expired", "id", id)
	}
}

func generateID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		// Fallback: use timestamp + counter (should never happen in practice).
		slog.Error("crypto/rand.Read failed", "err", err)
		return hex.EncodeToString([]byte(time.Now().String()))
	}
	return hex.EncodeToString(b)
}

type poolError string

func (e poolError) Error() string { return string(e) }

const ErrPoolExhausted = poolError("session pool exhausted")
