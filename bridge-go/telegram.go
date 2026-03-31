package main

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"strings"

	tgbotapi "github.com/go-telegram-bot-api/telegram-bot-api/v5"
)

var claudePrefixRe = regexp.MustCompile(`(?i)^/claude\s*`)

type Telegram struct {
	cfg  TelegramConfig
	exec ExecutorConfig
	log  *slog.Logger
}

func NewTelegram(cfg TelegramConfig, exec ExecutorConfig) *Telegram {
	return &Telegram{cfg: cfg, exec: exec, log: slog.With("platform", "telegram")}
}

func (t *Telegram) Name() string { return "telegram" }

func (t *Telegram) Run(ctx context.Context) error {
	bot, err := tgbotapi.NewBotAPI(t.cfg.Token)
	if err != nil {
		return fmt.Errorf("init bot: %w", err)
	}
	t.log.Info("bot started", "username", bot.Self.UserName)

	u := tgbotapi.NewUpdate(0)
	u.Timeout = 30
	updates := bot.GetUpdatesChan(u)

	for {
		select {
		case <-ctx.Done():
			bot.StopReceivingUpdates()
			return nil
		case update, ok := <-updates:
			if !ok {
				return nil
			}
			if update.Message == nil {
				continue
			}
			go t.handleMessage(ctx, bot, update.Message)
		}
	}
}

func (t *Telegram) handleMessage(ctx context.Context, bot *tgbotapi.BotAPI, msg *tgbotapi.Message) {
	// Only private chats
	if msg.Chat.Type != "private" {
		return
	}
	// msg.From can be nil for channel posts
	if msg.From == nil {
		return
	}

	chatID := msg.Chat.ID
	userID := msg.From.ID

	// Chat whitelist
	if len(t.cfg.AllowedChatIDs) > 0 && !containsStr(t.cfg.AllowedChatIDs, fmt.Sprint(chatID)) {
		return
	}
	// User whitelist
	if len(t.cfg.AllowedUserIDs) > 0 && !containsStr(t.cfg.AllowedUserIDs, fmt.Sprint(userID)) {
		return
	}

	text := msg.Text
	// Must be /claude command or plain text (not another command)
	isClaudeCmd := msg.IsCommand() && msg.Command() == "claude"
	isPlainText := !msg.IsCommand()
	if !isClaudeCmd && !isPlainText {
		return
	}

	// Extract prompt
	rawPrompt := claudePrefixRe.ReplaceAllString(text, "")
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
	placeholder := tgbotapi.NewMessage(chatID, "⏳ 處理中...")
	sent, err := bot.Send(placeholder)
	if err != nil {
		t.log.Error("send placeholder failed", "err", err)
		return
	}

	result := Execute(ctx, t.exec, prompt)
	output := result.FormatForDisplay()
	chunks := Chunk(output, 4000)

	// Edit placeholder with first chunk
	edit := tgbotapi.NewEditMessageText(chatID, sent.MessageID, chunks[0])
	if _, err := bot.Send(edit); err != nil {
		t.log.Error("edit placeholder failed", "err", err)
		// Fallback: send as new message
		if _, err2 := bot.Send(tgbotapi.NewMessage(chatID, chunks[0])); err2 != nil {
			t.log.Error("fallback send failed", "err", err2)
			return
		}
	}

	// Send remaining chunks; stop and notify on failure
	for i, chunk := range chunks[1:] {
		reply := tgbotapi.NewMessage(chatID, chunk)
		reply.ReplyToMessageID = msg.MessageID
		if _, err := bot.Send(reply); err != nil {
			t.log.Error("send chunk failed", "chunk", i+1, "err", err)
			notice := tgbotapi.NewMessage(chatID, "⚠️ 回覆傳送不完整，部分內容遺失。")
			_, _ = bot.Send(notice)
			return
		}
	}
}
