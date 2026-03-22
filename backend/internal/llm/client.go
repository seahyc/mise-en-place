package llm

import "context"

// Message represents a single chat message.
type Message struct {
	Role    string
	Content string
}

// ToolCall represents a tool invocation from the LLM.
type ToolCall struct {
	Name string
	Args map[string]any
}

// Response is what the LLM returns.
type Response struct {
	Content   string
	ToolCalls []ToolCall
}

// ToolDef describes a tool the LLM can call.
type ToolDef struct {
	Name        string
	Description string
	Parameters  any
}

// Client is the interface for interacting with an LLM.
type Client interface {
	Chat(ctx context.Context, messages []Message) (*Response, error)
	ChatWithTools(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error)
}
