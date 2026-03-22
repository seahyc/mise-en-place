package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
)

const glmBaseURL = "https://open.bigmodel.cn/api/paas/v4/chat/completions"

// GLMClient implements Client using the GLM (Zhipu) API.
type GLMClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
	baseURL    string
}

// NewGLMClient creates a new GLMClient.
func NewGLMClient(apiKey, model string) *GLMClient {
	if model == "" {
		model = "glm-4"
	}
	return &GLMClient{
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{},
		baseURL:    glmBaseURL,
	}
}

// Chat sends messages and returns a response.
func (c *GLMClient) Chat(ctx context.Context, messages []Message) (*Response, error) {
	return c.doRequest(ctx, messages, nil)
}

// ChatWithTools sends messages with tool definitions and returns a response.
func (c *GLMClient) ChatWithTools(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error) {
	return c.doRequest(ctx, messages, tools)
}

func (c *GLMClient) doRequest(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error) {
	reqBody := buildOpenAIRequest(c.model, messages, tools)

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("llm/glm: marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(jsonBody))
	if err != nil {
		return nil, fmt.Errorf("llm/glm: create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("llm/glm: do request: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("llm/glm: read response: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("llm/glm: status %d: %s", resp.StatusCode, string(body))
	}

	return ParseOpenAIResponse(body)
}

// buildOpenAIRequest creates an OpenAI-compatible request body.
func buildOpenAIRequest(model string, messages []Message, tools []ToolDef) map[string]any {
	msgs := make([]map[string]string, len(messages))
	for i, m := range messages {
		msgs[i] = map[string]string{"role": m.Role, "content": m.Content}
	}

	req := map[string]any{
		"model":    model,
		"messages": msgs,
	}

	if len(tools) > 0 {
		toolDefs := make([]map[string]any, len(tools))
		for i, t := range tools {
			toolDefs[i] = map[string]any{
				"type": "function",
				"function": map[string]any{
					"name":        t.Name,
					"description": t.Description,
					"parameters":  t.Parameters,
				},
			}
		}
		req["tools"] = toolDefs
	}

	return req
}

// ParseOpenAIResponse parses an OpenAI-compatible response JSON into an llm.Response.
func ParseOpenAIResponse(data []byte) (*Response, error) {
	var raw openAIResponse
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("llm: parse response: %w", err)
	}

	if len(raw.Choices) == 0 {
		return &Response{}, nil
	}

	choice := raw.Choices[0]
	resp := &Response{
		Content: choice.Message.Content,
	}

	for _, tc := range choice.Message.ToolCalls {
		var args map[string]any
		if tc.Function.Arguments != "" {
			if err := json.Unmarshal([]byte(tc.Function.Arguments), &args); err != nil {
				return nil, fmt.Errorf("llm: parse tool call args: %w", err)
			}
		}
		resp.ToolCalls = append(resp.ToolCalls, ToolCall{
			Name: tc.Function.Name,
			Args: args,
		})
	}

	return resp, nil
}

// openAIResponse is the internal representation of an OpenAI-compatible response.
type openAIResponse struct {
	Choices []openAIChoice `json:"choices"`
}

type openAIChoice struct {
	Message openAIMessage `json:"message"`
}

type openAIMessage struct {
	Content   string           `json:"content"`
	ToolCalls []openAIToolCall `json:"tool_calls,omitempty"`
}

type openAIToolCall struct {
	Function openAIFunction `json:"function"`
}

type openAIFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}
