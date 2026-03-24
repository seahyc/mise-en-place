package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const kimiBaseURL = "https://api.moonshot.ai/v1/chat/completions"

// KimiClient implements Client using the Moonshot (Kimi) API.
type KimiClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
	baseURL    string
}

// NewKimiClient creates a new KimiClient.
func NewKimiClient(apiKey, model string) *KimiClient {
	if model == "" {
		model = "moonshot-v1-8k"
	}
	return &KimiClient{
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{},
		baseURL:    kimiBaseURL,
	}
}

// Chat sends messages and returns a response.
func (c *KimiClient) Chat(ctx context.Context, messages []Message) (*Response, error) {
	return c.doRequest(ctx, messages, nil)
}

// ChatWithTools sends messages with tool definitions and returns a response.
func (c *KimiClient) ChatWithTools(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error) {
	return c.doRequest(ctx, messages, tools)
}

func (c *KimiClient) doRequest(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error) {
	reqBody := buildOpenAIRequest(c.model, messages, tools)

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("llm/kimi: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("llm/kimi: create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("llm/kimi: do request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("llm/kimi: read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("llm/kimi: status %d: %s", resp.StatusCode, string(body))
	}

	return ParseOpenAIResponse(body)
}
