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

**Tool calls**: The LLM can emit structured tool calls in its response (navigate step, set timer, mark complete, get cooking state, etc.). These are sent as JSON messages on the WebSocket. The Flutter client handles them identically to the current ElevenLabs tool pattern.

**Conversation context**: Per-session conversation history maintained server-side. Recipe context (current step, ingredients, active timers) injected as a system message, updated on each turn.

**Fallback**: If Kokoro TTS quality is insufficient, swap to a cheap TTS API (e.g., MiniMax, Fish Audio) — the interface stays the same.

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

**Job queue**: Simple Postgres table (`jobs`: id, type, status, payload, result, created_at, updated_at). Go goroutines poll or listen via NOTIFY/LISTEN. No Redis, no message broker.

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

**Users**:
```
users:
  id, email, display_name, password_hash, created_at
```

No placeholder keys, no step-level ingredient bindings, no unit master table in v1. Pax scaling handled conversationally by the LLM.

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

**Auth**: Simple JWT. Login endpoint returns access token. Client attaches to all requests via Authorization header. Google OAuth handled server-side (exchange code for token).

**Deployment**: `docker compose up -d` on Oracle VM. Caddy handles HTTPS.

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

**Data model simplification**: No placeholder keys, no step-level bindings. Recipes are freeform text. Pax scaling is conversational.

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
