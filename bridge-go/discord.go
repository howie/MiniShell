package main

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"strings"

	"github.com/bwmarrin/discordgo"
)

var mentionRe = regexp.MustCompile(`<@!?[0-9]+>`)

type Discord struct {
	cfg  DiscordConfig
	exec ExecutorConfig
	log  *slog.Logger
}

func NewDiscord(cfg DiscordConfig, exec ExecutorConfig) *Discord {
	return &Discord{cfg: cfg, exec: exec, log: slog.With("platform", "discord")}
}

func (d *Discord) Name() string { return "discord" }

func (d *Discord) Run(ctx context.Context) error {
	session, err := discordgo.New("Bot " + d.cfg.Token)
	if err != nil {
		return fmt.Errorf("init session: %w", err)
	}

	session.Identify.Intents = discordgo.IntentsGuilds |
		discordgo.IntentsGuildMessages |
		discordgo.IntentsMessageContent
	session.ShouldReconnectOnError = true

	session.AddHandler(func(s *discordgo.Session, m *discordgo.MessageCreate) {
		d.handleMessage(ctx, s, m)
	})
	session.AddHandler(func(s *discordgo.Session, r *discordgo.Ready) {
		d.log.Info("bot ready", "username", r.User.Username)
	})

	if err := session.Open(); err != nil {
		return fmt.Errorf("open session: %w", err)
	}
	defer session.Close()

	d.log.Info("bot started")
	<-ctx.Done()
	return nil
}

func (d *Discord) handleMessage(ctx context.Context, s *discordgo.Session, m *discordgo.MessageCreate) {
	// Ignore bots
	if m.Author.Bot {
		return
	}

	// State.User is nil before the Ready event fires
	if s.State == nil || s.State.User == nil {
		return
	}

	// Channel whitelist
	if len(d.cfg.AllowedChannelIDs) > 0 && !containsStr(d.cfg.AllowedChannelIDs, m.ChannelID) {
		return
	}
	// User whitelist
	if len(d.cfg.AllowedUserIDs) > 0 && !containsStr(d.cfg.AllowedUserIDs, m.Author.ID) {
		return
	}

	content := m.Content
	botID := s.State.User.ID
	prefixMention1 := "<@" + botID + ">"
	prefixMention2 := "<@!" + botID + ">"

	var rawPrompt string
	switch {
	case strings.HasPrefix(content, d.cfg.CommandPrefix):
		rawPrompt = strings.TrimPrefix(content, d.cfg.CommandPrefix)
	case strings.HasPrefix(content, prefixMention1) || strings.HasPrefix(content, prefixMention2):
		rawPrompt = mentionRe.ReplaceAllString(content, "")
		rawPrompt = strings.TrimSpace(rawPrompt)
	default:
		return
	}

	rawPrompt = strings.TrimSpace(rawPrompt)
	if rawPrompt == "" {
		return
	}

	prompt, _ := Sanitize(rawPrompt, 0)
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return
	}

	// Send placeholder
	placeholder, err := s.ChannelMessageSend(m.ChannelID, "⏳ 處理中...")
	if err != nil {
		d.log.Error("send placeholder failed", "err", err)
		return
	}

	result := Execute(ctx, d.exec, prompt)
	output := result.FormatForDisplay()
	chunks := Chunk(output, 1990)

	// Edit placeholder with first chunk
	edit := &discordgo.MessageEdit{
		Channel: m.ChannelID,
		ID:      placeholder.ID,
		Content: &chunks[0],
	}
	if _, err := s.ChannelMessageEditComplex(edit); err != nil {
		d.log.Error("edit placeholder failed", "err", err)
		// Fallback: send as a new message
		if _, err2 := s.ChannelMessageSend(m.ChannelID, chunks[0]); err2 != nil {
			d.log.Error("fallback send failed", "err", err2)
			return
		}
	}

	// Send remaining chunks; stop and notify on failure
	for i, chunk := range chunks[1:] {
		ref := m.Reference()
		msg := &discordgo.MessageSend{Content: chunk, Reference: ref}
		if _, err := s.ChannelMessageSendComplex(m.ChannelID, msg); err != nil {
			d.log.Error("send chunk failed", "chunk", i+1, "err", err)
			notice := &discordgo.MessageSend{Content: "⚠️ 回覆傳送不完整，部分內容遺失。", Reference: ref}
			_, _ = s.ChannelMessageSendComplex(m.ChannelID, notice)
			return
		}
	}
}
