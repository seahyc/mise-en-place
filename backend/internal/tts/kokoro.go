package tts

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

// KokoroClient implements Client using the Kokoro FastAPI TTS server
// (ghcr.io/remsky/kokoro-fastapi).
type KokoroClient struct {
	baseURL    string
	httpClient *http.Client
	voice      string
	model      string
}

// KokoroOption configures a KokoroClient.
type KokoroOption func(*KokoroClient)

// WithBaseURL sets the Kokoro server base URL.
func WithBaseURL(url string) KokoroOption {
	return func(c *KokoroClient) { c.baseURL = url }
}

// WithVoice sets the TTS voice.
func WithVoice(voice string) KokoroOption {
	return func(c *KokoroClient) { c.voice = voice }
}

// WithHTTPClient sets a custom HTTP client.
func WithHTTPClient(hc *http.Client) KokoroOption {
	return func(c *KokoroClient) { c.httpClient = hc }
}

// NewKokoroClient creates a KokoroClient with the given options.
func NewKokoroClient(opts ...KokoroOption) *KokoroClient {
	c := &KokoroClient{
		baseURL:    "http://localhost:8880",
		httpClient: http.DefaultClient,
		voice:      "af_sarah",
		model:      "kokoro",
	}
	for _, o := range opts {
		o(c)
	}
	return c
}

type speechRequest struct {
	Model          string `json:"model"`
	Input          string `json:"input"`
	Voice          string `json:"voice"`
	ResponseFormat string `json:"response_format"`
	Stream         bool   `json:"stream"`
}

// Synthesize sends text to the Kokoro server and returns the full PCM response.
func (c *KokoroClient) Synthesize(ctx context.Context, text string) ([]byte, error) {
	body, err := json.Marshal(speechRequest{
		Model:          c.model,
		Input:          text,
		Voice:          c.voice,
		ResponseFormat: "pcm",
		Stream:         false,
	})
	if err != nil {
		return nil, fmt.Errorf("tts: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.baseURL+"/v1/audio/speech", bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("tts: create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("tts: request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tts: unexpected status %d", resp.StatusCode)
	}

	pcm, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("tts: read response: %w", err)
	}
	return pcm, nil
}

// SynthesizeStream sends text to the Kokoro server with streaming enabled and
// writes PCM chunks to out as they arrive. The channel is closed on return.
func (c *KokoroClient) SynthesizeStream(ctx context.Context, text string, out chan<- []byte) error {
	defer close(out)

	body, err := json.Marshal(speechRequest{
		Model:          c.model,
		Input:          text,
		Voice:          c.voice,
		ResponseFormat: "pcm",
		Stream:         true,
	})
	if err != nil {
		return fmt.Errorf("tts: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		c.baseURL+"/v1/audio/speech", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("tts: create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("tts: request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("tts: unexpected status %d", resp.StatusCode)
	}

	buf := make([]byte, 4096)
	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			chunk := make([]byte, n)
			copy(chunk, buf[:n])
			select {
			case out <- chunk:
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		if readErr == io.EOF {
			return nil
		}
		if readErr != nil {
			return fmt.Errorf("tts: read stream: %w", readErr)
		}
	}
}

// Healthy checks whether the Kokoro TTS server is reachable.
func (c *KokoroClient) Healthy(ctx context.Context) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/health", nil)
	if err != nil {
		return false
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}
