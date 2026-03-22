# Voice Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the self-hosted voice pipeline: WebSocket server streaming audio between Flutter client and server, with VAD → Groq Whisper STT → Kimi/GLM LLM → Kokoro TTS chain. Includes tool call dispatch, conversation history persistence, and degradation fallbacks.

**Architecture:** Single WebSocket endpoint handles bidirectional audio. Server-side: VAD detects speech end → sends audio buffer to STT → sends transcript to LLM (with session context + tool definitions) → streams TTS audio back. Binary frames for audio (Opus), text frames for JSON control messages.

**Tech Stack:** Go, gorilla/websocket, silero-vad (via ONNX runtime or external process), Groq Whisper API, Kimi/GLM API (from Plan 2), Kokoro TTS (HTTP sidecar), Opus encoding (gopus)

**Spec:** `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md` (section 1 — Voice Pipeline)

**Dependency:** Plan 1 (backend foundation), Plan 2 Task 4 (LLM client), Plan 2 Task 5 (STT client)

---

### Task 1: TTS Client Interface + Kokoro Integration

**Files:**
- Create: `backend/internal/tts/client.go`
- Create: `backend/internal/tts/kokoro.go`
- Create: `backend/internal/tts/client_test.go`

- [ ] **Step 1: Write interface**

```go
package tts

import "context"

type Client interface {
    // Synthesize returns PCM audio bytes for the given text.
    Synthesize(ctx context.Context, text string) ([]byte, error)
    // SynthesizeStream sends PCM audio chunks to the channel as they're generated.
    SynthesizeStream(ctx context.Context, text string, out chan<- []byte) error
    // Healthy returns whether the TTS service is reachable.
    Healthy(ctx context.Context) bool
}
```

- [ ] **Step 2: Write stub test**

Test that a stub TTS client satisfies the interface. Test that KokoroClient constructs correct HTTP request URL.

- [ ] **Step 3: Implement KokoroClient**

Kokoro runs as `ghcr.io/remsky/kokoro-fastapi` (see Plan 1 docker-compose.yml). This is a FastAPI server wrapping Kokoro ONNX. API contract:

**POST `http://localhost:8880/v1/audio/speech`** (OpenAI-compatible):
```json
{
  "model": "kokoro",
  "input": "Hello, let's add the garlic now",
  "voice": "af_sarah",
  "response_format": "pcm",
  "stream": true
}
```
Response: streaming PCM audio (16-bit, 24kHz mono) when `stream: true`, or full audio bytes when `stream: false`.
Health check: `GET http://localhost:8880/health` → 200.

```go
type KokoroClient struct {
    baseURL    string
    httpClient *http.Client
}

func (c *KokoroClient) Synthesize(ctx context.Context, text string) ([]byte, error) {
    body, _ := json.Marshal(map[string]any{
        "model": "kokoro", "input": text, "voice": "af_sarah",
        "response_format": "pcm", "stream": false,
    })
    req, _ := http.NewRequestWithContext(ctx, "POST", c.baseURL+"/v1/audio/speech", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    resp, err := c.httpClient.Do(req)
    // read PCM audio bytes from response body
}

func (c *KokoroClient) SynthesizeStream(ctx context.Context, text string, out chan<- []byte) error {
    // Same endpoint with "stream": true
    // Read chunked response body, send PCM chunks to channel
}
```

- [ ] **Step 4: Commit**

---

### Task 2: Conversation History Repository

**Files:**
- Create: `backend/internal/repo/conversations.go`
- Create: `backend/internal/repo/conversations_test.go`

- [ ] **Step 1: Write failing test**

```go
func TestConversationRepoInterface(t *testing.T) {
    var _ repo.ConversationRepo = (*repo.PgConversationRepo)(nil)
}
```

- [ ] **Step 2: Implement PgConversationRepo**

Methods:
- `AddTurn(ctx, sessionID, role, content, toolCalls) error`
- `GetHistory(ctx, sessionID) ([]types.ConversationTurn, error)` — ordered by created_at
- `GetRecentHistory(ctx, sessionID, limit int) ([]types.ConversationTurn, error)` — last N turns for context window management

Add to `types/types.go`:
```go
type ConversationTurn struct {
    ID        string         `json:"id"`
    SessionID SessionID      `json:"session_id"`
    Role      string         `json:"role"`
    Content   string         `json:"content"`
    ToolCalls map[string]any `json:"tool_calls,omitempty"`
    CreatedAt time.Time      `json:"created_at"`
}
```

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 3: Voice Pipeline Core — WebSocket Handler

**Files:**
- Create: `backend/internal/handler/voice.go`
- Create: `backend/internal/handler/voice_test.go`

- [ ] **Step 1: Write failing WebSocket test**

Use `httptest.Server` + gorilla/websocket client:
- Connect WebSocket
- Send `session_start` JSON message
- Assert server responds (or at least accepts the connection)

- [ ] **Step 2: Implement WebSocket handler**

```go
func (h *VoiceHandler) HandleVoice(w http.ResponseWriter, r *http.Request) {
    conn, err := upgrader.Upgrade(w, r, nil)
    // 1. Read session_start message, authenticate JWT
    // 2. Load session context (recipe steps, active timers)
    // 3. Load conversation history from DB
    // 4. Enter read loop:
    //    - Binary frame → accumulate audio buffer
    //    - Text frame → handle control messages
    // 5. On connection close, persist final state
}
```

WebSocket route (add to main.go):
```go
r.Get("/ws/voice", voiceHandler.HandleVoice)
```

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 4: VAD Integration

**Files:**
- Create: `backend/internal/voice/vad.go`
- Create: `backend/internal/voice/vad_test.go`

- [ ] **Step 1: Write VAD interface + test**

```go
package voice

type VADResult struct {
    IsSpeech    bool
    Confidence  float32
}

type VAD interface {
    // ProcessFrame takes an audio frame and returns speech detection result.
    ProcessFrame(frame []byte) VADResult
    // Reset clears internal state for a new utterance.
    Reset()
}
```

- [ ] **Step 2: Implement energy-based VAD as simple fallback**

**Important**: VAD operates on PCM samples, not Opus frames. Incoming audio arrives as Opus over WebSocket, so it must be decoded to PCM first (using Task 6's Opus decoder). The WebSocket handler decodes Opus → PCM, then feeds PCM frames to VAD.

Simple approach: compute RMS energy of PCM int16 frame, compare to threshold. Track consecutive silent frames to detect end-of-speech. This works for v1 and avoids ONNX runtime dependency.

```go
type EnergyVAD struct {
    threshold       float32
    silenceFrames   int
    maxSilence      int // frames of silence before end-of-speech (e.g., 30 frames = 600ms at 20ms/frame)
}

// ProcessFrame takes PCM int16 samples (NOT Opus-encoded).
func (v *EnergyVAD) ProcessFrame(pcmSamples []int16) VADResult {
    rms := computeRMS(pcmSamples)
    isSpeech := rms > v.threshold
    // track silence duration...
}
```

- [ ] **Step 3: Test with known PCM samples** — array of zeros → not speech, array of loud samples → speech, silence after speech → end-of-speech detected
- [ ] **Step 4: Commit**

**Note on Task ordering**: Task 6 (Opus encode/decode) should complete before Task 5 (Pipeline integration), since the pipeline needs to decode Opus to PCM for both VAD and STT.

---

### Task 5: Voice Pipeline Orchestrator

**Files:**
- Create: `backend/internal/voice/pipeline.go`
- Create: `backend/internal/voice/pipeline_test.go`
- Create: `backend/internal/voice/tools.go`

- [ ] **Step 1: Write failing pipeline test**

Test the full chain with stubs: given audio bytes → VAD detects speech end → STT returns text → LLM returns response with tool call → TTS returns audio → verify output messages.

- [ ] **Step 2: Implement Pipeline**

```go
type Pipeline struct {
    stt          stt.Client
    llm          llm.Client
    tts          tts.Client
    vad          VAD
    conversations repo.ConversationRepo
}

type PipelineOutput struct {
    Transcript    string          // what the user said
    AgentResponse string          // what the agent said
    ToolCalls     []llm.ToolCall  // tool calls to send to client
    AudioChunks   [][]byte        // TTS audio to stream back
}

func (p *Pipeline) ProcessUtterance(ctx context.Context, sessionID types.SessionID, audioBuffer []byte, sessionContext SessionContext) (*PipelineOutput, error) {
    // 1. STT: audio → text
    // 2. Build LLM messages: system prompt (with session context) + conversation history + user message
    // 3. LLM chat with tools → response + tool calls
    // 4. Persist conversation turns
    // 5. TTS: response text → audio
    // 6. Return output
}
```

- [ ] **Step 3: Implement cooking tool definitions**

```go
// tools.go
func CookingToolDefs() []llm.ToolDef {
    return []llm.ToolDef{
        {Name: "navigate_step", Description: "Navigate to a specific step", Parameters: ...},
        {Name: "mark_step_complete", Description: "Mark current step as done", Parameters: ...},
        {Name: "set_timer", Description: "Set a cooking timer", Parameters: ...},
        {Name: "get_cooking_state", Description: "Get current session state", Parameters: ...},
    }
}
```

- [ ] **Step 4: Write test for tool call parsing**
- [ ] **Step 5: Run all tests**
- [ ] **Step 6: Commit**

---

### Task 6: Opus Encoding/Decoding

**Files:**
- Create: `backend/internal/voice/audio.go`
- Create: `backend/internal/voice/audio_test.go`

- [ ] **Step 1: Add gopus dependency**

```bash
go get gopkg.in/hraban/opus.v2
```

Note: gopus requires libopus-dev. Add to Dockerfile: `RUN apk add --no-cache opus-dev`

- [ ] **Step 2: Implement encode/decode helpers**

```go
func DecodeOpusToPCM(opusData []byte, sampleRate, channels int) ([]int16, error)
func EncodePCMToOpus(pcm []int16, sampleRate, channels, frameSize int) ([]byte, error)
```

- [ ] **Step 3: Write round-trip test** — encode PCM to Opus, decode back, verify similarity
- [ ] **Step 4: Commit**

---

### Task 7: Degradation + Fallback Logic

**Files:**
- Modify: `backend/internal/voice/pipeline.go`
- Create: `backend/internal/voice/fallback.go`
- Create: `backend/internal/voice/fallback_test.go`

- [ ] **Step 1: Write failing fallback test**

Test: when STT returns error, pipeline switches to fallback STT. When both LLM providers fail, pipeline returns text-only response.

- [ ] **Step 2: Implement WhisperCppClient (local STT fallback)**

```go
// backend/internal/stt/whispercpp.go
type WhisperCppClient struct {
    modelPath string // path to whisper model file (e.g., /models/ggml-base.bin)
}

func (c *WhisperCppClient) Transcribe(ctx context.Context, audioData []byte, format string) (string, error) {
    // Write audio to temp WAV file
    // Run: whisper-cli -m <model> -f <wav> --output-txt --no-timestamps
    // Read output text file
    // Clean up temp files
    cmd := exec.CommandContext(ctx, "whisper-cli",
        "-m", c.modelPath, "-f", tmpWavPath,
        "--output-txt", "--no-timestamps",
    )
    // ...
}
```

Add whisper.cpp binary to Docker image or as a sidecar. For the Oracle VM: install via `apt install whisper.cpp` or build from source. Model file (~150MB for base) stored on VM disk.

- [ ] **Step 3: Implement FallbackSTT**

```go
type FallbackSTTClient struct {
    primary   stt.Client
    fallback  stt.Client // Whisper.cpp local
}

func (c *FallbackSTTClient) Transcribe(ctx context.Context, audio []byte, format string) (string, error) {
    text, err := c.primary.Transcribe(ctx, audio, format)
    if err == nil {
        return text, nil
    }
    slog.Warn("primary STT failed, trying fallback", "error", err)
    return c.fallback.Transcribe(ctx, audio, format)
}
```

- [ ] **Step 3: Implement FallbackLLM** (try Kimi, then GLM, then return text-only error)
- [ ] **Step 4: Add TTS health check** — if Kokoro unhealthy, pipeline returns text-only response
- [ ] **Step 5: Run tests**
- [ ] **Step 6: Commit**

---

### Task 8: Wire Voice WebSocket End-to-End

**Files:**
- Modify: `backend/internal/handler/voice.go`
- Modify: `backend/cmd/server/main.go`
- Create: `backend/test/integration/voice_test.go`

- [ ] **Step 1: Complete the WebSocket handler read/write loop**

Integrate Pipeline into the WebSocket handler:
- Binary frames → feed to VAD → on speech end, call `Pipeline.ProcessUtterance`
- Send back: transcript (text frame), tool calls (text frames), audio (binary frames), tts_start/tts_end markers

- [ ] **Step 2: Write integration test**

WebSocket test with stubs: connect → send fake audio → receive transcript + response + tool call JSON.

- [ ] **Step 3: Wire into main.go**

Initialize Pipeline with all dependencies, register `/ws/voice` route.

- [ ] **Step 4: Run all tests including integration**
- [ ] **Step 5: Commit**

---

## Dependency Graph

```
Task 1 (TTS client) ──────────────────────────┐
Task 2 (conversation repo) ────────────────────┤
Task 4 (VAD) ──────────────────────────────────┼→ Task 5 (pipeline) → Task 7 (fallback) → Task 8 (wire up)
Plan 2 Task 4 (LLM client — already exists) ───┤
Plan 2 Task 5 (STT client — already exists) ───┘
Task 3 (WebSocket handler) → Task 8
Task 6 (Opus) → Task 8
```

**Parallelizable**: Tasks 1, 2, 3, 4, 6 can all run in parallel.
