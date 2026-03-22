# Mise en Place v2 — Full Stack Redesign

## Context

Mise en Place is a voice-driven recipe mobile app. The current prototype uses Flutter + Supabase + ElevenLabs + n8n. This redesign eliminates n8n, replaces ElevenLabs with a self-hosted voice pipeline, and moves the backend to a Go server on an Oracle VM — minimising serving costs while preserving quality.

## Requirements

- **Cross-platform**: iPad (cooking), phone (browsing), web (recipe management/sharing)
- **Voice agent**: Full conversational AI cooking mentor, hands-free during cooking
- **Video-to-recipe pipeline**: TikTok, YouTube, any video platform — transcribe video + pull captions/comments/linked articles → LLM parses into structured recipe → user reviews/edits → saves
- **Multi-recipe runtime merging**: User selects multiple recipes → LLM merges into one optimised cooking session on the fly (parallel prep, shared ingredients, coordinated timings) → single seamless voice-guided experience
- **Data model**: Start freeform (title, description, ingredient list as text, steps as text), progressively enrich with structure (step-level bindings, unit system, pax scaling) via background jobs
- **Step image generation**: Every instruction step gets an AI-generated illustration via Silicon Flow (Flux Schnell, ~$0.001/image)
- **Cost**: Near-zero fixed costs. Oracle VM (oracle.seahyingcong.com, ARM, free tier) as always-on compute. Pay only per-API-call for LLM/STT.
- **Scale**: 10-100 users initially, solo developer

## Architecture Overview

```
[Flutter Client]  ←──WebSocket──→  [Oracle VM]
  (iPad/Phone/Web)                    │
                                      ├─ Caddy (reverse proxy, auto HTTPS)
                                      ├─ Go Server (Chi/Echo)
                                      │   ├─ REST API (auth, recipes, sessions, ingestion)
                                      │   ├─ WebSocket: voice pipeline
                                      │   └─ WebSocket: realtime session updates
                                      ├─ Postgres
                                      ├─ Kokoro TTS (sidecar process)
                                      └─ Background workers (Go goroutines)
                                          ├─ Video ingestion
                                          └─ Image generation
```

### External API Dependencies (pay-per-use only)

| Service | Provider | Purpose | Cost |
|---------|----------|---------|------|
| LLM | Kimi (Moonshot) / GLM (Zhipu) | Recipe parsing, session merging, conversational agent | ~$0.001-0.003/1K tokens |
| STT | Groq Whisper (free tier) | Speech-to-text | Free (fallback: self-hosted Whisper.cpp) |
| TTS | Kokoro (self-hosted) | Text-to-speech | Free |
| Image Gen | Silicon Flow (Flux Schnell) | Step instruction images | ~$0.001/image |

**Estimated cost per cooking session**: ~$0.02-0.05 (LLM calls only)

## Component Design

### 1. Voice Pipeline

Replaces ElevenLabs agent entirely. Runs on the Oracle VM.

```
Client mic audio
  → WebSocket (bidirectional audio stream)
  → Server: VAD (silero-vad) detects speech boundaries
  → Groq Whisper API: speech → text
  → LLM (Kimi/GLM): text + conversation history + recipe context → response + tool calls
  → Kokoro TTS: response text → audio chunks
  → WebSocket: stream audio back to client + send tool call JSON
```

**Target latency**: ~1-1.5s from end-of-speech to first audio chunk.

#### WebSocket Protocol

The voice WebSocket carries two frame types:
- **Binary frames**: Audio data. Client→server: Opus-encoded, 48kHz, 20ms frames. Server→client: same format (Kokoro outputs PCM, server encodes to Opus before sending).
- **Text frames**: JSON control messages.

Client→server JSON messages:
```json
{"type": "session_start", "session_id": "uuid", "token": "jwt"}
{"type": "audio_config", "codec": "opus", "sample_rate": 48000}
```

Server→client JSON messages:
```json
{"type": "transcript", "text": "add the garlic now", "is_final": true}
{"type": "agent_response", "text": "Sure, adding garlic to step 4"}
{"type": "tool_call", "tool": "navigate_step", "args": {"step": 4}}
{"type": "tool_call", "tool": "set_timer", "args": {"label": "garlic", "seconds": 60}}
{"type": "tts_start"}
{"type": "tts_end"}
{"type": "error", "code": "stt_unavailable", "message": "..."}
```

Audio and JSON messages are distinguished by WebSocket frame type (binary vs text) — no multiplexing envelope needed.

**Reconnection**: On disconnect, the client reconnects with `session_id`. The server persists conversation history in a `conversation_turns` table, so context survives reconnection. Audio-in-flight is lost (acceptable — user just repeats).

**Tool calls**: The LLM can emit structured tool calls in its response (navigate step, set timer, mark complete, get cooking state, etc.). These are sent as JSON text frames. The Flutter client handles them identically to the current ElevenLabs tool pattern.

**Conversation context**: Per-session conversation history stored in `conversation_turns` table and maintained in-memory for the active session. Recipe context (current step, ingredients, active timers) injected as a system message, updated on each turn.

#### Degradation & Fallback Strategy

| Dependency | Failure mode | Detection | Fallback |
|------------|-------------|-----------|----------|
| Groq Whisper (STT) | Rate limit or downtime | HTTP 429/5xx | Switch to self-hosted Whisper.cpp on VM (higher latency, ~2-3s) |
| Kimi/GLM (LLM) | Rate limit or downtime | HTTP 429/5xx, timeout >5s | Try alternate provider (if Kimi fails, try GLM and vice versa). If both fail, degrade to text-only mode: show step text on screen, user taps to advance. |
| Kokoro (TTS) | Process crash | Health check ping every 30s | Restart sidecar automatically. During downtime, send text responses only (client shows text bubble instead of playing audio). |
| Silicon Flow (images) | Rate limit or downtime | HTTP 429/5xx | Skip image generation, leave image_url null. Retry in next cleanup cycle. |

The client always has the full session text available locally. Voice is an enhancement — the app remains usable in text-only mode if the voice pipeline degrades.

**Fallback TTS**: If Kokoro quality is insufficient long-term, swap to a cheap TTS API (e.g., MiniMax, Fish Audio) — the `tts.TTSClient` interface stays the same.

### 2. Video-to-Recipe Ingestion

```
User shares URL (TikTok / YouTube / any video platform)
  → Go server receives URL
  → yt-dlp: extract audio + metadata (title, description, comments)
  → If linked article/blog URL in description: scrape page text
  → Groq Whisper: transcribe audio → text
  → Kimi/GLM: parse all gathered text into recipe JSON
      Output: { title, description, ingredients: [text], steps: [text] }
  → Save to Postgres → notify client
  → Background job: generate step images via Silicon Flow
```

**Freeform first**: LLM outputs a simple structure — title, description, list of ingredients as text strings, ordered instruction steps as plain text. No step-level bindings or unit system yet.

**Progressive enrichment (v2)**: Background jobs re-process saved recipes to parse amounts/units, bind ingredients to steps, identify equipment. Not in v1.

**User review**: After ingestion, user sees the parsed recipe and can edit anything before saving. Critical for quality — LLM parsing won't be perfect.

**Job queue**: Simple Postgres table (see Data Model). Go goroutines poll or listen via NOTIFY/LISTEN. No Redis, no message broker.

**Ingestion security**:
- URL allowlist: only accept domains from a known list (youtube.com, youtu.be, tiktok.com, instagram.com, etc.). Reject unknown domains.
- yt-dlp arguments are constructed programmatically (no shell interpolation) — URL passed as a Go string argument to exec.Command, not through a shell.
- Downloaded media stored in a temp directory with a 500MB per-job limit. Cleaned up after transcription completes.
- Per-user rate limit: max 10 ingestion jobs per day.

### 3. Multi-Recipe Runtime Merging

When a user selects multiple recipes and hits "Start Cooking":

1. Fetch all selected recipes from Postgres
2. Single LLM call (Kimi/GLM) with all recipes' ingredients + instructions
3. Prompt: merge into one optimised cooking session — identify shared prep, parallel steps, optimal ordering
4. Output: ordered list of merged instruction steps, each tagged with source dish(es)
5. Save as a CookingSession with merged steps
6. Start voice-guided cooking

**Single-recipe is a degenerate case** — same flow, one recipe, no merging needed.

**Latency**: ~3-5 seconds for 2-3 recipes. Acceptable with a loading animation.

**Dish tagging**: Each step knows which recipe(s) it serves, enabling UI color-coding.

### 4. Data Model (Simplified)

**Recipe** (freeform v1):
```
recipes:
  id, title, description, source_url, source_type (tiktok/youtube/manual),
  cuisine, image_url, created_at, updated_at, user_id

recipe_ingredients:
  id, recipe_id, text (e.g., "2 cloves garlic, minced")

recipe_steps:
  id, recipe_id, order_index, text, image_url
```

**Cooking Session** (runtime):
```
cooking_sessions:
  id, user_id, source_recipe_ids[], status (setup/in_progress/paused/completed),
  created_at, started_at, completed_at

session_steps:
  id, session_id, order_index, text, source_dish_tag,
  is_completed, completed_at, agent_notes
```

**Users & Auth**:
```
users:
  id, email, display_name, password_hash, google_id, created_at

refresh_tokens:
  id, user_id, token_hash, expires_at, created_at
```

**Voice Conversation History** (survives reconnection/restart):
```
conversation_turns:
  id, session_id, role (user/assistant/system), content,
  tool_calls jsonb, created_at
```

**Session-Recipe Join Table** (replaces array column):
```
session_recipes:
  session_id, recipe_id
```

**Job Queue**:
```
jobs:
  id, type (ingest_video/generate_images), status (pending/running/done/failed),
  payload jsonb, result jsonb, user_id, created_at, updated_at
```

No placeholder keys, no step-level ingredient bindings, no unit master table in v1. Pax scaling handled conversationally by the LLM.

**Image storage**: Generated step images are saved to the VM filesystem under `/data/images/{recipe_id}/{step_index}.webp`. Caddy serves `/data/images/` as a static file path. `recipe_steps.image_url` stores the relative path. If the VM dies, images are regenerated from the job queue (idempotent). No external object storage needed at this scale.

### 5. Backend Architecture (Go)

```
backend/
├─ cmd/server/main.go              ← entry point
├─ internal/
│   ├─ types/                      ← shared types, no imports from other internal packages
│   ├─ config/                     ← env loading, config struct
│   ├─ repo/                       ← Postgres queries (sqlc or pgx)
│   ├─ service/                    ← business logic
│   │   ├─ recipe.go               ← CRUD, search
│   │   ├─ session.go              ← create, merge, state transitions
│   │   ├─ ingestion.go            ← video-to-recipe pipeline
│   │   ├─ voice.go                ← voice pipeline orchestration
│   │   └─ imagegen.go             ← Silicon Flow API calls
│   ├─ handler/                    ← HTTP + WebSocket handlers
│   ├─ llm/                        ← LLM client interface + Kimi/GLM implementations
│   ├─ stt/                        ← STT interface + Groq Whisper implementation
│   ├─ tts/                        ← TTS interface + Kokoro implementation
│   └─ worker/                     ← background job runner
├─ migrations/                     ← SQL migrations (golang-migrate)
├─ test/
│   ├─ integration/
│   ├─ golden/
│   └─ architecture_test.go
├─ Dockerfile
├─ docker-compose.yml              ← Caddy + Go server + Postgres + Kokoro
└─ AGENTS.md
```

**Dependency layers**: `types → config → repo → service → handler`. Enforced by structural tests and custom linter rules.

#### Auth Flow

**Email/password registration**:
1. `POST /auth/register` with email + password → server hashes with bcrypt, stores in `users` table, returns JWT access token (1h expiry) + refresh token (30d expiry, stored in `refresh_tokens` table).
2. `POST /auth/login` with email + password → verify hash → return tokens.
3. `POST /auth/refresh` with refresh token → validate, rotate, return new token pair.
4. Client stores tokens in secure storage (`flutter_secure_storage`). Attaches access token via `Authorization: Bearer <token>` header. Silent refresh on 401.

**Google OAuth (mobile)**:
1. Client uses `google_sign_in` Flutter package → gets Google ID token.
2. `POST /auth/google` with Google ID token → server verifies with Google's public keys, creates/finds user, returns JWT token pair.
3. No server-side redirect flow needed — the Flutter package handles the native OAuth UI.

**No migration from Supabase Auth**: The current prototype has minimal test data. Fresh start.

**Deployment**: `docker compose up -d` on Oracle VM. Caddy handles HTTPS.

#### VM Resource Budget (Oracle ARM A1: 4 OCPU / 24 GB RAM)

| Service | CPU | RAM | Notes |
|---------|-----|-----|-------|
| Postgres | 0.5 OCPU | 2 GB | Shared buffers 512MB, plenty for <100 users |
| Go server | 0.5 OCPU | 512 MB | Goroutines are cheap, even with concurrent WebSockets |
| Kokoro TTS | 1 OCPU | 4 GB | Largest consumer. Single model instance, requests queued. |
| Whisper.cpp (fallback) | 1 OCPU | 2 GB | Only loaded when Groq is unavailable |
| Caddy | negligible | 64 MB | |
| yt-dlp + ffmpeg | 0.5 OCPU (burst) | 512 MB | Runs during ingestion only |
| **Headroom** | **1 OCPU** | **~15 GB** | Comfortable margin |

**Concurrent load**: Kokoro processes TTS requests sequentially per instance. With ~1.5s synthesis per response, a single instance handles ~40 responses/minute — sufficient for 3-5 simultaneous cooking sessions. If contention occurs, add a second Kokoro instance (RAM allows it).

### 6. Flutter Client Changes

**Removed**:
- ElevenLabs SDK
- Supabase client (DB, Auth, Realtime)
- n8n webhook calls
- Music service

**Added**:
- HTTP client to Go API (auth, recipes, sessions, ingestion)
- WebSocket client for voice pipeline (stream mic audio, receive audio + tool calls)
- WebSocket client for realtime session updates
- Share extension handler (receive URLs from TikTok/YouTube share sheets)

**Kept**:
- Flutter framework (cross-platform)
- CookingModeController pattern
- Tool call handling (navigate, timer, mark complete — same interface, different transport)
- Timer manager

**State management**: Riverpod (migration from Provider). Typed, testable, supports code generation. Each service exposed as a provider; controllers as StateNotifier/AsyncNotifier.

**Data model simplification**: No placeholder keys, no step-level bindings. Recipes are freeform text. Pax scaling is conversational.

**Offline/poor connectivity**: Recipes are cached locally (SQLite via `drift`). If WebSocket drops during cooking, the client shows step text and allows manual tap-to-advance. Voice resumes on reconnection with conversation context preserved server-side. Browsing and recipe editing work offline against local cache, synced on reconnect.

```
app/
├─ lib/
│   ├─ models/                     ← simplified recipe, session, user
│   ├─ services/
│   │   ├─ api_client.dart         ← HTTP to Go backend
│   │   ├─ voice_client.dart       ← WebSocket voice pipeline
│   │   ├─ session_client.dart     ← WebSocket realtime updates
│   │   └─ auth_service.dart       ← JWT-based auth
│   ├─ controllers/
│   │   └─ cooking_mode_controller.dart
│   ├─ screens/
│   └─ widgets/
├─ test/
│   ├─ unit/
│   ├─ widget/                     ← golden image tests
│   └─ integration_test/           ← patrol tests
└─ AGENTS.md
```

## Harness Engineering

Since this codebase is fully AI-written, the harness is the quality mechanism.

### Linting

**Go backend**:
- `golangci-lint` with strict config: `govet`, `staticcheck`, `errcheck`, `gosimple`, `ineffassign`, `revive`
- Custom `revive` rules enforcing dependency layer direction
- Linter error messages double as remediation instructions (e.g., "handlers must not import repo directly — inject via service layer. See docs/architecture.md")

**Flutter client**:
- `flutter analyze` with strict `analysis_options.yaml`: `avoid_dynamic_calls`, `prefer_const_constructors`, `always_declare_return_types`
- Custom lint rules via `custom_lint` for project-specific patterns

**Both**:
- Pre-commit hooks via `lefthook` running lint + test
- `AGENTS.md` at repo root + per-directory for each subsystem

### Test Strategy

**Go backend — unit tests** (no external deps, <1s):
- Every service function tested. Table-driven tests.
- LLM calls behind `LLMClient` interface — tests use stubs returning canned responses.
- Golden file pattern for LLM output validation (stored in `test/golden/`).

**Go backend — integration tests** (~5s):
- `testcontainers-go` for throwaway Postgres per test suite. No DB mocks.
- Full flows: create recipe → create session → merge steps → verify in DB.
- Ingestion pipeline: canned yt-dlp output + canned transcript → verify parsed recipe.

**Go backend — contract tests**:
- Recorded real responses from Kimi/GLM, Groq Whisper, Silicon Flow → replay in tests.
- Catches serialization/deserialization breakage.

**Go backend — WebSocket tests**:
- `httptest` server + WebSocket client. Test voice pipeline message protocol.

**Go backend — structural tests**:
- `architecture_test.go`: scan imports, assert dependency layer rules hold.

**Flutter — unit tests**:
- Controllers and services with mocked HTTP/WebSocket.
- CookingModeController state transitions given tool call JSON.
- Model JSON parsing.

**Flutter — golden image tests** (`golden_toolkit`):
- Render key screens at iPad (1024x1366) and phone (390x844) sizes.
- Pixel-diff against `.golden.png` files. Fail on unexpected changes.
- Agents update goldens explicitly when UI intentionally changes.

**Flutter — Patrol tests** (native interaction):
- Microphone permission grant flow.
- Share sheet URL receiving (TikTok/YouTube share-to-app).
- Full cooking flow: browse → select → start → receive mock tool calls → navigate → complete.

### CI Pipeline

```
On PR:
  ├─ golangci-lint (backend)
  ├─ flutter analyze (client)
  ├─ go test ./... (backend unit + integration)
  ├─ flutter test (unit + golden image)
  ├─ patrol test (on emulator: iPad + iPhone)
  ├─ Architectural boundary check (structural tests)
  └─ Doc freshness check (AGENTS.md references valid files)

On merge to main:
  ├─ Build Docker images
  └─ Deploy to Oracle VM (docker compose)
```

### Logging

Structured JSON logging via `slog` (Go stdlib). Every request gets a `request_id`; voice sessions get a `session_id`. Logs written to stdout, Caddy captures and rotates via systemd journal or `logrotate`. No external log aggregation — `journalctl` and `jq` are sufficient at this scale.

### What We're NOT Doing (YAGNI)

- Per-worktree observability stack
- LLM-based code reviewers in CI
- Metrics dashboards (add when real traffic exists)
- Cloudflare R2 (store images as URLs for now)
- Music generation (drop for v1)
- Complex unit/ingredient data model (v1 is freeform text)

## Cost Summary

| Item | Monthly cost (10-100 users) |
|------|---------------------------|
| Oracle VM | Free (always-free tier) |
| Postgres | Free (on VM) |
| Kokoro TTS | Free (on VM) |
| Groq Whisper STT | Free (free tier) |
| Kimi/GLM LLM calls | ~$1-5 |
| Silicon Flow image gen | ~$0.50-2 |
| Domain + HTTPS (Caddy) | ~$10/year |
| **Total** | **~$2-8/month** |
