package llm

import "context"

// Message represents a chat message.
type Message struct {
	Role    string
	Content string
}

// ToolCall represents a function call requested by the model.
type ToolCall struct {
	Name string
	Args map[string]any
}

// Response represents a chat completion response.
type Response struct {
	Content   string
	ToolCalls []ToolCall
}

// ToolDef defines a tool/function that the model can call.
type ToolDef struct {
	Name        string
	Description string
	Parameters  any
}

// Client is the interface for LLM chat completions.
type Client interface {
	Chat(ctx context.Context, messages []Message) (*Response, error)
	ChatWithTools(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error)
}
