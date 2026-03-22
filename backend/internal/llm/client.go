<<<<<<< HEAD
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
||||||| f1a9b7b
=======
// Package llm defines the interface for large language model clients.
// This is a minimal stub; the full implementation will come from the recipes worktree.
package llm

import "context"

// Message represents a single message in a conversation.
type Message struct {
	Role      string         `json:"role"` // system, user, assistant, tool
	Content   string         `json:"content"`
	ToolCalls []ToolCall     `json:"tool_calls,omitempty"`
	ToolID    string         `json:"tool_call_id,omitempty"`
	Name      string         `json:"name,omitempty"`
}

// ToolCall represents a function call requested by the LLM.
type ToolCall struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

// ToolDef defines a tool available to the LLM.
type ToolDef struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Parameters  map[string]any `json:"parameters,omitempty"`
}

// Response is the result of an LLM completion.
type Response struct {
	Content   string     `json:"content"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

// Client defines the interface for interacting with an LLM.
type Client interface {
	// Complete sends messages to the LLM and returns a response.
	// tools may be nil if no tool use is needed.
	Complete(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error)
}
>>>>>>> feature/v2-voice
