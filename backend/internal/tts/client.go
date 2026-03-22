package tts

import "context"

// Client defines the interface for text-to-speech synthesis.
type Client interface {
	// Synthesize converts text to audio and returns the full PCM byte buffer.
	Synthesize(ctx context.Context, text string) ([]byte, error)

	// SynthesizeStream converts text to audio, sending PCM chunks to the out
	// channel as they arrive. The channel is closed when streaming completes.
	SynthesizeStream(ctx context.Context, text string, out chan<- []byte) error

	// Healthy reports whether the TTS backend is reachable.
	Healthy(ctx context.Context) bool
}
