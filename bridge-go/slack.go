package main

import (
	"context"
	"fmt"
	"log/slog"
	"regexp"
	"slices"
	"strings"
	"sync"

	"github.com/slack-go/slack"
	"github.com/slack-go/slack/slackevents"
	"github.com/slack-go/slack/socketmode"
)

const slackChunkRunes = 2900

var slackMentionRe = regexp.MustCompile(`<@[A-Z0-9]+>`)

type Slack struct {
	cfg  SlackConfig
	exec ExecutorConfig
	log  *slog.Logger
	wg   sync.WaitGroup
}

func NewSlack(cfg SlackConfig, exec ExecutorConfig) *Slack {
	return &Slack{cfg: cfg, exec: exec, log: slog.With("platform", "slack")}
}

func (sl *Slack) Name() string { return "slack" }

func (sl *Slack) Run(ctx context.Context) error {
	if sl.cfg.AppToken == "" {
		return fmt.Errorf("app_token is required for Socket Mode")
	}

	api := slack.New(
		sl.cfg.BotToken,
		slack.OptionAppLevelToken(sl.cfg.AppToken),
	)

	client := socketmode.New(api,
		socketmode.OptionDebug(false),
	)

	// runErr receives the error from RunContext so we can surface it to main.
	runErr := make(chan error, 1)
	go func() {
		runErr <- client.RunContext(ctx)
	}()

	sl.log.Info("bot started")

	// Wait for in-flight handlers before returning.
	defer sl.wg.Wait()

	for {
		select {
		case err := <-runErr:
			// RunContext returned — either ctx cancelled (clean) or connection error.
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("socket mode disconnected: %w", err)

		case <-ctx.Done():
			// Drain runErr to avoid goroutine leak.
			<-runErr
			return nil

		case evt, ok := <-client.Events:
			if !ok {
				return nil
			}
			switch evt.Type {
			case socketmode.EventTypeConnected:
				sl.log.Info("WebSocket connected")
			case socketmode.EventTypeDisconnect:
				sl.log.Info("WebSocket disconnected")
			case socketmode.EventTypeEventsAPI:
				client.Ack(*evt.Request)
				eventsAPIEvent, ok := evt.Data.(slackevents.EventsAPIEvent)
				if !ok {
					continue
				}
				sl.wg.Add(1)
				go func() {
					defer sl.wg.Done()
					defer func() {
						if r := recover(); r != nil {
							sl.log.Error("handler panic", "recover", r)
						}
					}()
					sl.handleEventsAPI(ctx, api, eventsAPIEvent)
				}()
			}
		}
	}
}

func (sl *Slack) handleEventsAPI(ctx context.Context, api *slack.Client, event slackevents.EventsAPIEvent) {
	if event.Type != slackevents.CallbackEvent {
		return
	}

	var channelID, userID, text string
	isDM := false

	switch ev := event.InnerEvent.Data.(type) {
	case *slackevents.AppMentionEvent:
		channelID = ev.Channel
		userID = ev.User
		text = ev.Text
	case *slackevents.MessageEvent:
		if ev.BotID != "" || ev.SubType != "" {
			return
		}
		if ev.ChannelType != "im" {
			return
		}
		isDM = true
		channelID = ev.Channel
		userID = ev.User
		text = ev.Text
	default:
		return
	}

	// Channel whitelist — skip for DMs (channelID is the DM channel, not a public channel ID)
	if !isDM && len(sl.cfg.AllowedChannelIDs) > 0 && !slices.Contains(sl.cfg.AllowedChannelIDs, channelID) {
		return
	}
	// User whitelist
	if len(sl.cfg.AllowedUserIDs) > 0 && !slices.Contains(sl.cfg.AllowedUserIDs, userID) {
		return
	}

	// Strip bot mention
	rawPrompt := slackMentionRe.ReplaceAllString(text, "")
	rawPrompt = strings.TrimSpace(rawPrompt)
	if rawPrompt == "" {
		return
	}

	prompt, truncated := sanitizePrompt(rawPrompt)
	if prompt == "" {
		return
	}

	// Notify user if prompt was truncated before processing.
	if truncated {
		if _, _, err := api.PostMessage(channelID, slack.MsgOptionText("⚠️ 您的訊息過長，已截斷至 10,000 字元。", false)); err != nil {
			sl.log.Error("send truncation notice failed", "err", err)
		}
	}

	// Send placeholder
	_, placeholderTS, err := api.PostMessage(channelID, slack.MsgOptionText("⏳ 處理中...", false))
	if err != nil {
		sl.log.Error("send placeholder failed", "err", err)
		return
	}

	result := Execute(ctx, sl.exec, prompt)
	sl.log.Info("execution complete", "duration_ms", result.DurationMs, "success", result.Success, "timed_out", result.TimedOut)
	output := result.FormatForDisplay()
	chunks := Chunk(output, slackChunkRunes)

	// Update placeholder with first chunk
	_, _, _, err = api.UpdateMessage(channelID, placeholderTS, slack.MsgOptionText(chunks[0], false))
	if err != nil {
		sl.log.Error("update placeholder failed", "err", err)
		// Fallback: post as new message
		if _, _, err2 := api.PostMessage(channelID, slack.MsgOptionText(chunks[0], false)); err2 != nil {
			sl.log.Error("fallback post failed", "err", err2)
			return
		}
	}

	// Send remaining chunks; stop and notify on failure
	for i, chunk := range chunks[1:] {
		if _, _, err := api.PostMessage(channelID, slack.MsgOptionText(chunk, false)); err != nil {
			sl.log.Error("send chunk failed", "chunk", i+1, "err", err)
			_, _, _ = api.PostMessage(channelID, slack.MsgOptionText("⚠️ 回覆傳送不完整，部分內容遺失。", false))
			return
		}
	}
}
