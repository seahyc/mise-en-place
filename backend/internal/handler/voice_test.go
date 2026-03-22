package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"

	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/tts"
	"github.com/yingcong/mise-en-place/backend/internal/types"
	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

const testJWTSecret = "test-secret-key-for-voice-tests"

func makeTestToken(t *testing.T) string {
	t.Helper()
	tok, err := service.GenerateAccessToken("user-1", testJWTSecret, time.Hour)
	if err != nil {
		t.Fatalf("generate token: %v", err)
	}
	return tok
}

func TestVoiceHandler_SessionStart(t *testing.T) {
	vh := handler.NewVoiceHandler(testJWTSecret, nil)

	srv := httptest.NewServer(http.HandlerFunc(vh.HandleVoice))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/"
	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer ws.Close()

	// Send session_start.
	startMsg := handler.WSMessage{
		Type:      "session_start",
		SessionID: "session-abc",
		Token:     makeTestToken(t),
	}
	data, _ := json.Marshal(startMsg)
	if err := ws.WriteMessage(websocket.TextMessage, data); err != nil {
		t.Fatalf("write session_start: %v", err)
	}

	// Read session_started response.
	_, respBytes, err := ws.ReadMessage()
	if err != nil {
		t.Fatalf("read response: %v", err)
	}

	var resp handler.WSMessage
	if err := json.Unmarshal(respBytes, &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if resp.Type != "session_started" {
		t.Errorf("expected session_started, got %q", resp.Type)
	}
	if resp.SessionID != "session-abc" {
		t.Errorf("expected session_id session-abc, got %q", resp.SessionID)
	}
}

func TestVoiceHandler_InvalidToken(t *testing.T) {
	vh := handler.NewVoiceHandler(testJWTSecret, nil)

	srv := httptest.NewServer(http.HandlerFunc(vh.HandleVoice))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/"
	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer ws.Close()

	startMsg := handler.WSMessage{
		Type:      "session_start",
		SessionID: "session-abc",
		Token:     "invalid-token",
	}
	data, _ := json.Marshal(startMsg)
	if err := ws.WriteMessage(websocket.TextMessage, data); err != nil {
		t.Fatalf("write: %v", err)
	}

	_, respBytes, err := ws.ReadMessage()
	if err != nil {
		t.Fatalf("read: %v", err)
	}

	var resp handler.WSMessage
	json.Unmarshal(respBytes, &resp)
	if resp.Type != "error" {
		t.Errorf("expected error, got %q", resp.Type)
	}
	if resp.Error != "invalid token" {
		t.Errorf("expected 'invalid token' error, got %q", resp.Error)
	}
}

// --- Stubs for full pipeline test ---

type voiceStubSTT struct{ text string; err error }
func (s *voiceStubSTT) Transcribe(_ context.Context, _ []byte, _ string) (string, error) { return s.text, s.err }
var _ stt.Client = (*voiceStubSTT)(nil)

type voiceStubLLM struct{ resp *llm.Response; err error }
func (s *voiceStubLLM) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) { return s.resp, s.err }
func (s *voiceStubLLM) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) { return s.resp, s.err }
var _ llm.Client = (*voiceStubLLM)(nil)

type voiceStubTTS struct{ audio []byte; healthy bool; err error }
func (s *voiceStubTTS) Synthesize(_ context.Context, _ string) ([]byte, error) { return s.audio, s.err }
func (s *voiceStubTTS) SynthesizeStream(_ context.Context, _ string, out chan<- []byte) error { defer close(out); return nil }
func (s *voiceStubTTS) Healthy(_ context.Context) bool { return s.healthy }
var _ tts.Client = (*voiceStubTTS)(nil)

type stubConvo struct{}
func (s *stubConvo) AddTurn(_ context.Context, _ types.SessionID, _, _ string, _ map[string]any) error { return nil }
func (s *stubConvo) GetHistory(_ context.Context, _ types.SessionID) ([]types.ConversationTurn, error) { return nil, nil }
func (s *stubConvo) GetRecentHistory(_ context.Context, _ types.SessionID, _ int) ([]types.ConversationTurn, error) { return nil, nil }
var _ repo.ConversationRepo = (*stubConvo)(nil)

func TestVoiceHandler_FullPipelineFlow(t *testing.T) {
	sttC := &voiceStubSTT{text: "next step please"}
	llmC := &voiceStubLLM{resp: &llm.Response{
		Content: "Moving to step 2: dice the tomatoes.",
		ToolCalls: []llm.ToolCall{
			{Name: "navigate_step", Args: map[string]any{"step_number": float64(2)}},
		},
	}}
	ttsC := &voiceStubTTS{audio: []byte{0xAA, 0xBB, 0xCC}, healthy: true}

	pipeline := voice.NewPipeline(sttC, llmC, ttsC, nil, &stubConvo{})
	vh := handler.NewVoiceHandler(testJWTSecret, pipeline)

	srv := httptest.NewServer(http.HandlerFunc(vh.HandleVoice))
	defer srv.Close()

	wsURL := "ws" + strings.TrimPrefix(srv.URL, "http") + "/"
	ws, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		t.Fatalf("dial: %v", err)
	}
	defer ws.Close()

	// Session start.
	startMsg, _ := json.Marshal(handler.WSMessage{
		Type:      "session_start",
		SessionID: "s1",
		Token:     makeTestToken(t),
	})
	ws.WriteMessage(websocket.TextMessage, startMsg)

	// Read session_started.
	_, _, err = ws.ReadMessage()
	if err != nil {
		t.Fatalf("read session_started: %v", err)
	}

	// Send binary audio data.
	ws.WriteMessage(websocket.BinaryMessage, []byte{0x01, 0x02, 0x03, 0x04})

	// Signal end of speech.
	eos, _ := json.Marshal(handler.WSMessage{Type: "end_of_speech"})
	ws.WriteMessage(websocket.TextMessage, eos)

	// Collect responses with a timeout.
	var messages []handler.WSMessage
	var binaryChunks [][]byte

	ws.SetReadDeadline(time.Now().Add(2 * time.Second))
	for {
		msgType, data, err := ws.ReadMessage()
		if err != nil {
			break
		}
		if msgType == websocket.TextMessage {
			var msg handler.WSMessage
			json.Unmarshal(data, &msg)
			messages = append(messages, msg)
			if msg.Type == "tts_end" {
				break
			}
		} else if msgType == websocket.BinaryMessage {
			binaryChunks = append(binaryChunks, data)
		}
	}

	// Verify we got the expected message types.
	typesSeen := make(map[string]bool)
	for _, m := range messages {
		typesSeen[m.Type] = true
	}

	for _, expected := range []string{"transcript", "tool_call", "agent_response", "tts_start", "tts_end"} {
		if !typesSeen[expected] {
			t.Errorf("missing expected message type: %s (got types: %v)", expected, typesSeen)
		}
	}

	if len(binaryChunks) == 0 {
		t.Error("expected at least one binary audio chunk")
	}
}
