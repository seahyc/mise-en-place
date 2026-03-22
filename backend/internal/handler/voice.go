package handler

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
	"github.com/yingcong/mise-en-place/backend/internal/voice"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  16384,
	WriteBufferSize: 16384,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

// WSMessage is the JSON envelope for text-frame messages over the voice WebSocket.
type WSMessage struct {
	Type         string         `json:"type"`
	SessionID    string         `json:"session_id,omitempty"`
	Token        string         `json:"token,omitempty"`
	Transcript   string         `json:"transcript,omitempty"`
	Text         string         `json:"text,omitempty"`
	ToolName     string         `json:"tool_name,omitempty"`
	ToolArgs     map[string]any `json:"tool_args,omitempty"`
	Error        string         `json:"error,omitempty"`
	Step         int            `json:"step,omitempty"`
	TotalSteps   int            `json:"total_steps,omitempty"`
	StepText     string         `json:"step_text,omitempty"`
	Ingredients  []string       `json:"ingredients,omitempty"`
	ActiveTimers []string       `json:"active_timers,omitempty"`
}

// VoiceHandler manages the voice WebSocket connection.
type VoiceHandler struct {
	jwtSecret string
	pipeline  *voice.Pipeline
}

// NewVoiceHandler creates a new VoiceHandler. pipeline may be nil during init.
func NewVoiceHandler(jwtSecret string, pipeline *voice.Pipeline) *VoiceHandler {
	return &VoiceHandler{
		jwtSecret: jwtSecret,
		pipeline:  pipeline,
	}
}

// HandleVoice upgrades the HTTP connection to a WebSocket, authenticates via
// a session_start text message, then enters a read loop that handles binary
// audio frames and text control messages.
func (h *VoiceHandler) HandleVoice(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Error("voice: websocket upgrade failed", "error", err)
		return
	}
	defer conn.Close()

	ctx := r.Context()

	// Step 1: Read session_start message.
	_, msgBytes, err := conn.ReadMessage()
	if err != nil {
		slog.Error("voice: read session_start", "error", err)
		return
	}

	var startMsg WSMessage
	if err := json.Unmarshal(msgBytes, &startMsg); err != nil {
		h.writeError(conn, "invalid JSON in session_start")
		return
	}
	if startMsg.Type != "session_start" {
		h.writeError(conn, "first message must be session_start")
		return
	}
	if startMsg.Token == "" {
		h.writeError(conn, "missing token in session_start")
		return
	}

	// Step 2: Validate JWT.
	userID, err := service.ParseAccessToken(startMsg.Token, h.jwtSecret)
	if err != nil {
		h.writeError(conn, "invalid token")
		return
	}

	sessionID := types.SessionID(startMsg.SessionID)
	slog.Info("voice: session started", "user_id", userID, "session_id", sessionID)

	// Acknowledge session start.
	h.writeJSON(conn, WSMessage{Type: "session_started", SessionID: string(sessionID)})

	// Step 3: Read loop with pipeline integration.
	var (
		audioBuffer []byte
		audioMu     sync.Mutex
	)
	hasVAD := h.pipeline != nil && h.pipeline.VAD() != nil

	// Session context defaults — the client can update via update_context messages.
	sessionCtx := voice.SessionContext{
		SessionID: sessionID,
	}

	for {
		msgType, data, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				slog.Error("voice: unexpected close", "error", err)
			}
			break
		}

		switch msgType {
		case websocket.BinaryMessage:
			if h.pipeline == nil {
				continue
			}

			audioMu.Lock()
			audioBuffer = append(audioBuffer, data...)
			audioMu.Unlock()

			// If we have a VAD, decode audio and check for end-of-speech.
			if hasVAD {
				pcmSamples, decErr := voice.DecodeToPCM(data, 16000, 1)
				if decErr != nil {
					slog.Warn("voice: decode audio", "error", decErr)
					continue
				}
				result := h.pipeline.VAD().ProcessFrame(pcmSamples)
				if !result.IsSpeech && result.Confidence == -1 {
					// End-of-speech detected — process the utterance.
					audioMu.Lock()
					buf := audioBuffer
					audioBuffer = nil
					audioMu.Unlock()

					h.processAndRespond(ctx, conn, sessionID, buf, sessionCtx)
					h.pipeline.VAD().Reset()
				}
			}

		case websocket.TextMessage:
			var msg WSMessage
			if err := json.Unmarshal(data, &msg); err != nil {
				h.writeError(conn, "invalid JSON")
				continue
			}

			switch msg.Type {
			case "end_of_speech":
				// Client signals end-of-speech manually.
				if h.pipeline == nil {
					continue
				}
				audioMu.Lock()
				buf := audioBuffer
				audioBuffer = nil
				audioMu.Unlock()

				h.processAndRespond(ctx, conn, sessionID, buf, sessionCtx)

			case "update_context":
				sessionCtx.CurrentStep = msg.Step
				sessionCtx.TotalSteps = msg.TotalSteps
				sessionCtx.StepText = msg.StepText
				sessionCtx.Ingredients = msg.Ingredients
				sessionCtx.ActiveTimers = msg.ActiveTimers

			default:
				slog.Warn("voice: unknown message type", "type", msg.Type)
			}
		}
	}

	slog.Info("voice: session ended", "session_id", sessionID)
}

// processAndRespond runs the voice pipeline and sends results back over the WebSocket.
func (h *VoiceHandler) processAndRespond(ctx context.Context, conn *websocket.Conn, sessionID types.SessionID, audioBuffer []byte, sessionCtx voice.SessionContext) {
	if len(audioBuffer) == 0 {
		return
	}

	output, err := h.pipeline.ProcessUtterance(ctx, sessionID, audioBuffer, sessionCtx)
	if err != nil {
		slog.Error("voice: pipeline error", "error", err)
		h.writeError(conn, "pipeline processing failed")
		return
	}

	// Send transcript.
	if output.Transcript != "" {
		h.writeJSON(conn, WSMessage{Type: "transcript", Transcript: output.Transcript})
	}

	// Send tool calls.
	for _, tc := range output.ToolCalls {
		h.writeJSON(conn, WSMessage{
			Type:     "tool_call",
			ToolName: tc.Name,
			ToolArgs: tc.Arguments,
		})
	}

	// Send agent response.
	if output.AgentResponse != "" {
		h.writeJSON(conn, WSMessage{Type: "agent_response", Text: output.AgentResponse})
	}

	// Send audio chunks.
	if len(output.AudioChunks) > 0 {
		h.writeJSON(conn, WSMessage{Type: "tts_start"})
		for _, chunk := range output.AudioChunks {
			if err := conn.WriteMessage(websocket.BinaryMessage, chunk); err != nil {
				slog.Error("voice: write audio chunk", "error", err)
				break
			}
		}
		h.writeJSON(conn, WSMessage{Type: "tts_end"})
	}
}

func (h *VoiceHandler) writeJSON(conn *websocket.Conn, msg WSMessage) {
	data, err := json.Marshal(msg)
	if err != nil {
		slog.Error("voice: marshal JSON", "error", err)
		return
	}
	if err := conn.WriteMessage(websocket.TextMessage, data); err != nil {
		slog.Error("voice: write message", "error", err)
	}
}

func (h *VoiceHandler) writeError(conn *websocket.Conn, errMsg string) {
	h.writeJSON(conn, WSMessage{Type: "error", Error: errMsg})
}
