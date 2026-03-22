package voice_test

import (
	"context"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/tts"
	"github.com/yingcong/mise-en-place/backend/internal/types"
	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

// --- Stub implementations ---

type stubSTT struct {
	text string
	err  error
}

func (s *stubSTT) Transcribe(_ context.Context, _ []byte, _ string) (string, error) {
	return s.text, s.err
}

var _ stt.Client = (*stubSTT)(nil)

type stubLLM struct {
	resp *llm.Response
	err  error
}

func (s *stubLLM) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	return s.resp, s.err
}

func (s *stubLLM) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	return s.resp, s.err
}

var _ llm.Client = (*stubLLM)(nil)

type stubTTS struct {
	audio   []byte
	healthy bool
	err     error
}

func (s *stubTTS) Synthesize(_ context.Context, _ string) ([]byte, error) {
	return s.audio, s.err
}

func (s *stubTTS) SynthesizeStream(_ context.Context, _ string, out chan<- []byte) error {
	defer close(out)
	if s.err != nil {
		return s.err
	}
	out <- s.audio
	return nil
}

func (s *stubTTS) Healthy(_ context.Context) bool {
	return s.healthy
}

var _ tts.Client = (*stubTTS)(nil)

type stubConversations struct {
	turns []types.ConversationTurn
}

func (s *stubConversations) AddTurn(_ context.Context, _ types.SessionID, _, _ string, _ map[string]any) error {
	return nil
}

func (s *stubConversations) GetHistory(_ context.Context, _ types.SessionID) ([]types.ConversationTurn, error) {
	return s.turns, nil
}

func (s *stubConversations) GetRecentHistory(_ context.Context, _ types.SessionID, _ int) ([]types.ConversationTurn, error) {
	return s.turns, nil
}

// --- Tests ---

func TestPipeline_ProcessUtterance(t *testing.T) {
	sttClient := &stubSTT{text: "what is the next step"}
	llmClient := &stubLLM{resp: &llm.Response{
		Content: "The next step is to chop the onions.",
		ToolCalls: []llm.ToolCall{
			{Name: "navigate_step", Args: map[string]any{"step_number": float64(2)}},
		},
	}}
	ttsClient := &stubTTS{audio: []byte{0x01, 0x02}, healthy: true}
	vad := voice.NewEnergyVAD()
	convos := &stubConversations{}

	p := voice.NewPipeline(sttClient, llmClient, ttsClient, vad, convos)

	output, err := p.ProcessUtterance(
		context.Background(),
		types.SessionID("session-1"),
		[]byte{0xFF, 0xFF}, // dummy audio
		voice.SessionContext{
			SessionID:   "session-1",
			CurrentStep: 1,
			TotalSteps:  5,
			StepText:    "Boil the water",
		},
	)
	if err != nil {
		t.Fatalf("ProcessUtterance: %v", err)
	}

	if output.Transcript != "what is the next step" {
		t.Errorf("transcript: got %q", output.Transcript)
	}
	if output.AgentResponse != "The next step is to chop the onions." {
		t.Errorf("agent_response: got %q", output.AgentResponse)
	}
	if len(output.ToolCalls) != 1 {
		t.Fatalf("tool_calls: got %d, want 1", len(output.ToolCalls))
	}
	if output.ToolCalls[0].Name != "navigate_step" {
		t.Errorf("tool_call name: got %q", output.ToolCalls[0].Name)
	}
	if len(output.AudioChunks) != 1 {
		t.Fatalf("audio_chunks: got %d, want 1", len(output.AudioChunks))
	}
}

func TestPipeline_EmptyTranscript(t *testing.T) {
	sttClient := &stubSTT{text: "   "}
	llmClient := &stubLLM{resp: &llm.Response{Content: "should not be called"}}
	ttsClient := &stubTTS{healthy: true}

	p := voice.NewPipeline(sttClient, llmClient, ttsClient, nil, nil)

	output, err := p.ProcessUtterance(
		context.Background(),
		types.SessionID("s1"),
		[]byte{0x00},
		voice.SessionContext{},
	)
	if err != nil {
		t.Fatalf("ProcessUtterance: %v", err)
	}
	if output.AgentResponse != "" {
		t.Errorf("expected empty response for blank transcript, got %q", output.AgentResponse)
	}
}

func TestPipeline_TTSUnhealthy(t *testing.T) {
	sttClient := &stubSTT{text: "hello"}
	llmClient := &stubLLM{resp: &llm.Response{Content: "Hi there!"}}
	ttsClient := &stubTTS{healthy: false}

	p := voice.NewPipeline(sttClient, llmClient, ttsClient, nil, nil)

	output, err := p.ProcessUtterance(
		context.Background(),
		types.SessionID("s1"),
		[]byte{0x00},
		voice.SessionContext{},
	)
	if err != nil {
		t.Fatalf("ProcessUtterance: %v", err)
	}
	if output.AgentResponse != "Hi there!" {
		t.Errorf("expected text response")
	}
	if len(output.AudioChunks) != 0 {
		t.Error("expected no audio chunks when TTS is unhealthy")
	}
}
