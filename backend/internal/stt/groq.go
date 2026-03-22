package stt

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
)

const groqBaseURL = "https://api.groq.com/openai/v1/audio/transcriptions"

// GroqClient implements Client using the Groq Whisper API.
type GroqClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
	baseURL    string
}

// NewGroqClient creates a new GroqClient.
func NewGroqClient(apiKey string) *GroqClient {
	return &GroqClient{
		apiKey:     apiKey,
		model:      "whisper-large-v3",
		httpClient: &http.Client{},
		baseURL:    groqBaseURL,
	}
}

// Transcribe sends audio data to Groq Whisper and returns the transcription text.
func (c *GroqClient) Transcribe(ctx context.Context, audioData []byte, format string) (string, error) {
	var buf bytes.Buffer
	w := multipart.NewWriter(&buf)

	// Add the audio file
	filename := "audio." + format
	part, err := w.CreateFormFile("file", filename)
	if err != nil {
		return "", fmt.Errorf("stt/groq: create form file: %w", err)
	}
	if _, err := part.Write(audioData); err != nil {
		return "", fmt.Errorf("stt/groq: write audio data: %w", err)
	}

	// Add the model field
	if err := w.WriteField("model", c.model); err != nil {
		return "", fmt.Errorf("stt/groq: write model field: %w", err)
	}

	if err := w.Close(); err != nil {
		return "", fmt.Errorf("stt/groq: close writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, &buf)
	if err != nil {
		return "", fmt.Errorf("stt/groq: create request: %w", err)
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("stt/groq: do request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("stt/groq: read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("stt/groq: status %d: %s", resp.StatusCode, string(body))
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(body, &result); err != nil {
		return "", fmt.Errorf("stt/groq: parse response: %w", err)
	}

	return result.Text, nil
}
