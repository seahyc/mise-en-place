package voice

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
)

// FallbackSTTClient wraps a primary and fallback STT client. If the primary
// fails, the fallback is attempted.
type FallbackSTTClient struct {
	primary  stt.Client
	fallback stt.Client
}

// NewFallbackSTTClient creates a new FallbackSTTClient.
func NewFallbackSTTClient(primary, fallback stt.Client) *FallbackSTTClient {
	return &FallbackSTTClient{primary: primary, fallback: fallback}
}

// Transcribe tries the primary STT client first; on failure, falls back to the
// secondary client.
func (c *FallbackSTTClient) Transcribe(ctx context.Context, audio []byte, format string) (string, error) {
	text, err := c.primary.Transcribe(ctx, audio, format)
	if err == nil {
		return text, nil
	}
	slog.Warn("primary STT failed, trying fallback", "error", err)
	return c.fallback.Transcribe(ctx, audio, format)
}

// Verify interface satisfaction.
var _ stt.Client = (*FallbackSTTClient)(nil)

// FallbackLLMClient wraps a primary and secondary LLM client. If the primary
// fails, the secondary is attempted.
type FallbackLLMClient struct {
	primary   llm.Client
	secondary llm.Client
}

// NewFallbackLLMClient creates a new FallbackLLMClient.
func NewFallbackLLMClient(primary, secondary llm.Client) *FallbackLLMClient {
	return &FallbackLLMClient{primary: primary, secondary: secondary}
}

// Complete tries the primary LLM client first; on failure, falls back to the
// secondary. Returns an error only if both fail.
func (c *FallbackLLMClient) Complete(ctx context.Context, messages []llm.Message, tools []llm.ToolDef) (*llm.Response, error) {
	resp, err := c.primary.Complete(ctx, messages, tools)
	if err == nil {
		return resp, nil
	}
	slog.Warn("primary LLM failed, trying fallback", "error", err)

	resp2, err2 := c.secondary.Complete(ctx, messages, tools)
	if err2 != nil {
		return nil, fmt.Errorf("voice: both LLM clients failed: primary=%w, secondary=%v", err, err2)
	}
	return resp2, nil
}

// Verify interface satisfaction.
var _ llm.Client = (*FallbackLLMClient)(nil)
