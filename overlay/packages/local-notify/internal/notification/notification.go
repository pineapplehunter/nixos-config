package notification

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

const (
	DefaultColor     = 0x5865F2
	MaxRequestSize   = 16 * 1024
	MaxTitleLength   = 256
	MaxContentLength = 4096
)

type Message struct {
	Title   string `json:"title"`
	Content string `json:"content"`
	Color   string `json:"color,omitempty"`
}

func (m Message) Validate() error {
	if strings.TrimSpace(m.Title) == "" {
		return errors.New("title is required")
	}
	if strings.TrimSpace(m.Content) == "" {
		return errors.New("content is required")
	}
	if len(m.Title) > MaxTitleLength {
		return fmt.Errorf("title exceeds %d bytes", MaxTitleLength)
	}
	if len(m.Content) > MaxContentLength {
		return fmt.Errorf("content exceeds %d bytes", MaxContentLength)
	}
	if m.Color != "" {
		if len(m.Color) != 7 || m.Color[0] != '#' {
			return errors.New("color must use the form #RRGGBB")
		}
		if _, err := strconv.ParseUint(m.Color[1:], 16, 24); err != nil {
			return errors.New("color must use the form #RRGGBB")
		}
	}
	return nil
}

func Decode(r io.Reader) (Message, error) {
	data, err := io.ReadAll(io.LimitReader(r, MaxRequestSize+1))
	if err != nil {
		return Message{}, fmt.Errorf("reading request: %w", err)
	}
	if len(data) > MaxRequestSize {
		return Message{}, fmt.Errorf("request exceeds %d bytes", MaxRequestSize)
	}

	var message Message
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&message); err != nil {
		return Message{}, fmt.Errorf("decoding request: %w", err)
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		if err == nil {
			return Message{}, errors.New("request contains more than one JSON object")
		}
		return Message{}, fmt.Errorf("decoding request suffix: %w", err)
	}
	if err := message.Validate(); err != nil {
		return Message{}, err
	}
	return message, nil
}

type discordEmbed struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Color       int    `json:"color"`
}

type discordPayload struct {
	Username        string         `json:"username"`
	Embeds          []discordEmbed `json:"embeds"`
	AllowedMentions struct {
		Parse []string `json:"parse"`
	} `json:"allowed_mentions"`
}

func SendDiscord(ctx context.Context, webhookURL string, message Message) error {
	color := DefaultColor
	if message.Color != "" {
		parsed, _ := strconv.ParseUint(message.Color[1:], 16, 24)
		color = int(parsed)
	}
	payload := discordPayload{
		Username: "Local Notifier",
		Embeds: []discordEmbed{{
			Title:       message.Title,
			Description: message.Content,
			Color:       color,
		}},
	}
	payload.AllowedMentions.Parse = []string{}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encoding Discord payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, webhookURL, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("creating Discord request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("User-Agent", "local-notify/1.0")

	client := http.Client{Timeout: 15 * time.Second}
	response, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("sending Discord request: %w", err)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("Discord webhook returned %s", response.Status)
	}
	return nil
}
