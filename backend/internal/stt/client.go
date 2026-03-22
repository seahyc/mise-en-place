package stt

import "context"

// Client is the interface for speech-to-text transcription.
type Client interface {
	Transcribe(ctx context.Context, audioData []byte, format string) (string, error)
}
