package main

import (
	"bytes"
	"context"
	"errors"
	"flag"
	"fmt"
	"os"

	"local-notify/internal/notification"
)

func run(args []string) error {
	flags := flag.NewFlagSet("local-notifyd", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	webhookFile := flags.String("webhook-file", "", "file containing the Discord webhook URL")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments: %v", flags.Args())
	}
	if *webhookFile == "" {
		return errors.New("--webhook-file is required")
	}

	webhook, err := os.ReadFile(*webhookFile)
	if err != nil {
		return fmt.Errorf("reading webhook file: %w", err)
	}
	webhookURL := string(bytes.TrimSpace(webhook))
	if webhookURL == "" {
		return errors.New("webhook file is empty")
	}

	message, err := notification.Decode(os.Stdin)
	if err != nil {
		return fmt.Errorf("invalid notification: %w", err)
	}
	if err := notification.SendDiscord(context.Background(), webhookURL, message); err != nil {
		return fmt.Errorf("notification delivery failed: %w", err)
	}
	return nil
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "local-notifyd: %v\n", err)
		os.Exit(1)
	}
}
