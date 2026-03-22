package voice

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/tts"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// SessionContext provides cooking-session metadata to the pipeline so the LLM
// can generate contextually relevant responses.
type SessionContext struct {
	SessionID    types.SessionID
	CurrentStep  int
	TotalSteps   int
	StepText     string
	Ingredients  []string
	ActiveTimers []string
}

// PipelineOutput contains the results of processing a single utterance.
type PipelineOutput struct {
	Transcript    string
	AgentResponse string
	ToolCalls     []llm.ToolCall
	AudioChunks   [][]byte
}

// Pipeline orchestrates the voice interaction flow:
// STT -> LLM (with tools) -> TTS.
type Pipeline struct {
	sttClient    stt.Client
	llmClient    llm.Client
	ttsClient    tts.Client
	vad          VAD
	conversations repo.ConversationRepo
}

// NewPipeline creates a new voice Pipeline.
func NewPipeline(
	sttClient stt.Client,
	llmClient llm.Client,
	ttsClient tts.Client,
	vad VAD,
	conversations repo.ConversationRepo,
) *Pipeline {
	return &Pipeline{
		sttClient:    sttClient,
		llmClient:    llmClient,
		ttsClient:    ttsClient,
		vad:          vad,
		conversations: conversations,
	}
}

// VAD returns the pipeline's voice activity detector (may be nil).
func (p *Pipeline) VAD() VAD {
	return p.vad
}

// ProcessUtterance runs the full voice pipeline:
// 1. STT: audio -> text
// 2. Build messages: system prompt + conversation history + user text
// 3. LLM with tools -> response + tool calls
// 4. Persist turns
// 5. TTS: response -> audio chunks
// 6. Return output
func (p *Pipeline) ProcessUtterance(ctx context.Context, sessionID types.SessionID, audioBuffer []byte, sessionCtx SessionContext) (*PipelineOutput, error) {
	// 1. STT: audio -> text
	transcript, err := p.sttClient.Transcribe(ctx, audioBuffer, "pcm")
	if err != nil {
		return nil, fmt.Errorf("voice: stt failed: %w", err)
	}
	if strings.TrimSpace(transcript) == "" {
		return &PipelineOutput{}, nil
	}

	// 2. Build messages
	messages := p.buildMessages(ctx, sessionID, sessionCtx, transcript)

	// 3. LLM with tools
	tools := CookingToolDefs()
	llmResp, err := p.llmClient.ChatWithTools(ctx, messages, tools)
	if err != nil {
		return nil, fmt.Errorf("voice: llm failed: %w", err)
	}

	// 4. Persist turns
	if p.conversations != nil {
		if err := p.conversations.AddTurn(ctx, sessionID, "user", transcript, nil); err != nil {
			slog.Warn("voice: failed to persist user turn", "error", err)
		}

		var toolCallsMap map[string]any
		if len(llmResp.ToolCalls) > 0 {
			toolCallsMap = make(map[string]any)
			for _, tc := range llmResp.ToolCalls {
				toolCallsMap[tc.Name] = tc.Args
			}
		}
		if err := p.conversations.AddTurn(ctx, sessionID, "assistant", llmResp.Content, toolCallsMap); err != nil {
			slog.Warn("voice: failed to persist assistant turn", "error", err)
		}
	}

	// 5. TTS: response -> audio chunks
	output := &PipelineOutput{
		Transcript:    transcript,
		AgentResponse: llmResp.Content,
		ToolCalls:     llmResp.ToolCalls,
	}

	if p.ttsClient != nil && llmResp.Content != "" && p.ttsClient.Healthy(ctx) {
		audioData, ttsErr := p.ttsClient.Synthesize(ctx, llmResp.Content)
		if ttsErr != nil {
			slog.Warn("voice: tts failed, returning text-only", "error", ttsErr)
		} else if len(audioData) > 0 {
			output.AudioChunks = [][]byte{audioData}
		}
	}

	return output, nil
}

// buildMessages constructs the LLM message array from system prompt,
// conversation history, and the new user utterance.
func (p *Pipeline) buildMessages(ctx context.Context, sessionID types.SessionID, sessionCtx SessionContext, userText string) []llm.Message {
	systemPrompt := buildSystemPrompt(sessionCtx)

	messages := []llm.Message{
		{Role: "system", Content: systemPrompt},
	}

	// Load recent conversation history.
	if p.conversations != nil {
		history, err := p.conversations.GetRecentHistory(ctx, sessionID, 20)
		if err != nil {
			slog.Warn("voice: failed to load history", "error", err)
		} else {
			for _, turn := range history {
				messages = append(messages, llm.Message{
					Role:    turn.Role,
					Content: turn.Content,
				})
			}
		}
	}

	// Add current user message.
	messages = append(messages, llm.Message{
		Role:    "user",
		Content: userText,
	})

	return messages
}

// buildSystemPrompt creates the system prompt with cooking context.
func buildSystemPrompt(ctx SessionContext) string {
	var sb strings.Builder
	sb.WriteString("You are a helpful cooking assistant guiding the user through a recipe. ")
	sb.WriteString("Keep responses concise and conversational — they will be spoken aloud. ")
	sb.WriteString("Use cooking tools when the user asks to navigate steps, set timers, or check progress.\n\n")

	if ctx.TotalSteps > 0 {
		fmt.Fprintf(&sb, "Current step: %d of %d\n", ctx.CurrentStep, ctx.TotalSteps)
		if ctx.StepText != "" {
			fmt.Fprintf(&sb, "Step instruction: %s\n", ctx.StepText)
		}
	}

	if len(ctx.Ingredients) > 0 {
		sb.WriteString("Ingredients: ")
		sb.WriteString(strings.Join(ctx.Ingredients, ", "))
		sb.WriteString("\n")
	}

	if len(ctx.ActiveTimers) > 0 {
		sb.WriteString("Active timers: ")
		sb.WriteString(strings.Join(ctx.ActiveTimers, ", "))
		sb.WriteString("\n")
	}

	return sb.String()
}
