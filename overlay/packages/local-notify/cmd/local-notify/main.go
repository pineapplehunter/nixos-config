package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"local-notify/internal/notification"
)

func defaultSocketPath() (string, error) {
	runtimeDirectory := os.Getenv("XDG_RUNTIME_DIR")
	if runtimeDirectory == "" {
		return "", errors.New("XDG_RUNTIME_DIR is not set")
	}
	return filepath.Join(runtimeDirectory, "local-notify", "notify.sock"), nil
}

func run(args []string) error {
	flags := flag.NewFlagSet("local-notify", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	title := flags.String("title", "", "notification title")
	content := flags.String("content", "", "notification body")
	socket := flags.String("socket", "", "Unix socket path (defaults below XDG_RUNTIME_DIR)")
	color := flags.String("color", "", "Discord embed color in #RRGGBB form")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return fmt.Errorf("unexpected positional arguments: %v", flags.Args())
	}

	message := notification.Message{Title: *title, Content: *content, Color: *color}
	if err := message.Validate(); err != nil {
		return err
	}
	if *socket == "" {
		path, err := defaultSocketPath()
		if err != nil {
			return err
		}
		*socket = path
	}

	connection, err := net.DialTimeout("unix", *socket, 3*time.Second)
	if err != nil {
		return fmt.Errorf("connecting to %s: %w", *socket, err)
	}
	defer connection.Close()
	if err := connection.SetWriteDeadline(time.Now().Add(3 * time.Second)); err != nil {
		return fmt.Errorf("setting socket deadline: %w", err)
	}
	if err := json.NewEncoder(connection).Encode(message); err != nil {
		return fmt.Errorf("sending notification: %w", err)
	}
	if unixConnection, ok := connection.(*net.UnixConn); ok {
		if err := unixConnection.CloseWrite(); err != nil {
			return fmt.Errorf("closing notification request: %w", err)
		}
	}
	return nil
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintf(os.Stderr, "local-notify: %v\n", err)
		os.Exit(1)
	}
}
