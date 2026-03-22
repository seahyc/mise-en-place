<<<<<<< HEAD
package stt

import "context"

// Client is the interface for speech-to-text transcription.
type Client interface {
	Transcribe(ctx context.Context, audioData []byte, format string) (string, error)
}
||||||| f1a9b7b
=======
// Package stt defines the interface for speech-to-text clients.
// This is a minimal stub; the full implementation will come from the recipes worktree.
package stt

import "context"

// Client defines the interface for speech-to-text transcription.
type Client interface {
	// Transcribe converts audio bytes to text.
	// format indicates the audio format (e.g. "pcm", "opus", "wav").
	Transcribe(ctx context.Context, audio []byte, format string) (string, error)
}
>>>>>>> feature/v2-voice
