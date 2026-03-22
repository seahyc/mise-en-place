# Recipe CRUD + Video Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the recipe CRUD API and the video-to-recipe ingestion pipeline (yt-dlp → Groq Whisper → LLM parsing → image generation).

**Architecture:** Recipe service handles CRUD. Ingestion service orchestrates: URL validation → yt-dlp audio extraction → Groq Whisper transcription → Kimi/GLM recipe parsing → save to DB. Background worker generates step images via Silicon Flow. All external APIs behind interfaces.

**Tech Stack:** Go, pgx, yt-dlp (exec.Command), Groq Whisper API, Kimi/GLM API, Silicon Flow API

**Spec:** `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md` (sections 2, 4)

**Dependency:** Plan 1 (backend foundation) must be complete.

---

### Task 1: Recipe Repository

**Files:**
- Create: `backend/internal/repo/recipes.go`
- Create: `backend/internal/repo/recipes_test.go`

- [ ] **Step 1: Write failing test for RecipeRepo interface**

```go
package repo_test

func TestRecipeRepoInterface(t *testing.T) {
	var _ repo.RecipeRepo = (*repo.PgRecipeRepo)(nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/repo/ -v -run TestRecipeRepo`
Expected: FAIL

- [ ] **Step 3: Implement PgRecipeRepo**

Implement CRUD methods:
- `Create(ctx, userID, title, description, sourceURL, sourceType, cuisine, ingredients []string, steps []StepInput) (*types.Recipe, error)` — insert recipe + ingredients + steps in a transaction
- `GetByID(ctx, id) (*types.Recipe, error)` — fetch recipe with ingredients and steps (LEFT JOINs)
- `ListByUser(ctx, userID, limit, offset) ([]types.Recipe, error)` — list recipes for a user (without steps/ingredients for the list view)
- `Update(ctx, id, updates) error` — update title, description, cuisine, ingredients, steps
- `Delete(ctx, id) error` — cascade delete

- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 2: Recipe Service

**Files:**
- Create: `backend/internal/service/recipe.go`
- Create: `backend/internal/service/recipe_test.go`

- [ ] **Step 1: Write failing test**

Test `RecipeService.Create` with a stub repo — verify it validates inputs (non-empty title, at least one step) and delegates to repo.

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement RecipeService**

Methods:
- `Create(ctx, userID, req CreateRecipeRequest) (*types.Recipe, error)`
- `Get(ctx, recipeID) (*types.Recipe, error)`
- `List(ctx, userID, page, pageSize) ([]types.Recipe, int, error)` — returns recipes + total count
- `Update(ctx, userID, recipeID, req UpdateRecipeRequest) error` — verify ownership
- `Delete(ctx, userID, recipeID) error` — verify ownership

- [ ] **Step 4: Run test to verify it passes**
- [ ] **Step 5: Commit**

---

### Task 3: Recipe HTTP Handlers

**Files:**
- Create: `backend/internal/handler/recipes.go`
- Create: `backend/internal/handler/recipes_test.go`
- Modify: `backend/cmd/server/main.go` (add routes)

- [ ] **Step 1: Write failing handler tests**

Test with httptest:
- POST `/recipes` with valid JSON → 201
- POST `/recipes` with missing title → 400
- GET `/recipes` → 200 with list
- GET `/recipes/:id` → 200 with full recipe
- DELETE `/recipes/:id` → 204

- [ ] **Step 2: Run test to verify they fail**
- [ ] **Step 3: Implement handlers**

Wire handlers to `RecipeService`. Use `handler.GetUserID(ctx)` for ownership.

Routes (add to main.go protected group):
```go
r.Route("/recipes", func(r chi.Router) {
    r.Post("/", recipeHandler.Create)
    r.Get("/", recipeHandler.List)
    r.Get("/{id}", recipeHandler.Get)
    r.Put("/{id}", recipeHandler.Update)
    r.Delete("/{id}", recipeHandler.Delete)
})
```

- [ ] **Step 4: Run tests to verify they pass**
- [ ] **Step 5: Commit**

---

### Task 4: LLM Client Interface + Kimi/GLM Implementations

**Files:**
- Create: `backend/internal/llm/client.go`
- Create: `backend/internal/llm/kimi.go`
- Create: `backend/internal/llm/glm.go`
- Create: `backend/internal/llm/client_test.go`

- [ ] **Step 1: Write the LLM client interface and test**

```go
// client.go
package llm

import "context"

type Message struct {
    Role    string `json:"role"`
    Content string `json:"content"`
}

type ToolCall struct {
    Name string         `json:"name"`
    Args map[string]any `json:"args"`
}

type Response struct {
    Content   string     `json:"content"`
    ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

type Client interface {
    Chat(ctx context.Context, messages []Message) (*Response, error)
    ChatWithTools(ctx context.Context, messages []Message, tools []ToolDef) (*Response, error)
}

type ToolDef struct {
    Name        string `json:"name"`
    Description string `json:"description"`
    Parameters  any    `json:"parameters"`
}
```

Test with a stub client that returns canned responses.

- [ ] **Step 2: Implement KimiClient**

HTTP POST to `https://api.moonshot.cn/v1/chat/completions` with OpenAI-compatible format. Parse response into `llm.Response`.

- [ ] **Step 3: Implement GLMClient**

HTTP POST to `https://open.bigmodel.cn/api/paas/v4/chat/completions`. Same OpenAI-compatible format.

- [ ] **Step 4: Write contract test with golden file**

Record a real response from Kimi, save as `test/golden/kimi_recipe_parse.json`. Test that deserialization works correctly.

- [ ] **Step 5: Commit**

---

### Task 5: STT Client Interface + Groq Whisper

**Files:**
- Create: `backend/internal/stt/client.go`
- Create: `backend/internal/stt/groq.go`
- Create: `backend/internal/stt/client_test.go`

- [ ] **Step 1: Write interface + test**

```go
package stt

import "context"

type Client interface {
    Transcribe(ctx context.Context, audioData []byte, format string) (string, error)
}
```

- [ ] **Step 2: Implement GroqClient**

HTTP POST multipart/form-data to `https://api.groq.com/openai/v1/audio/transcriptions` with model `whisper-large-v3`. Parse response text.

- [ ] **Step 3: Write contract test with golden file**
- [ ] **Step 4: Commit**

---

### Task 6: Video Ingestion Service

**Files:**
- Create: `backend/internal/service/ingestion.go`
- Create: `backend/internal/service/ingestion_test.go`
- Create: `test/golden/ingestion_transcript.txt`
- Create: `test/golden/ingestion_parsed_recipe.json`

- [ ] **Step 1: Write failing test for URL validation**

```go
func TestValidateURL(t *testing.T) {
    tests := []struct{
        url  string
        ok   bool
    }{
        {"https://www.youtube.com/watch?v=abc123", true},
        {"https://youtu.be/abc123", true},
        {"https://www.tiktok.com/@user/video/123", true},
        {"https://www.instagram.com/reel/abc", true},
        {"https://evil.com/malware", false},
        {"not-a-url", false},
    }
    for _, tt := range tests {
        t.Run(tt.url, func(t *testing.T) {
            err := service.ValidateIngestionURL(tt.url)
            if (err == nil) != tt.ok {
                t.Errorf("ValidateIngestionURL(%q) = %v, want ok=%v", tt.url, err, tt.ok)
            }
        })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement URL validation**

Allowlist: youtube.com, youtu.be, tiktok.com, instagram.com, bilibili.com, xiaohongshu.com. Parse URL, verify host is in list.

- [ ] **Step 4: Write failing test for recipe parsing from transcript**

Use golden file: given a transcript, assert the LLM stub returns a parsed recipe with expected structure.

- [ ] **Step 5: Implement IngestionService**

```go
type IngestionService struct {
    llm       llm.Client
    stt       stt.Client
    recipes   repo.RecipeRepo
    jobs      repo.JobRepo
}

func (s *IngestionService) Ingest(ctx context.Context, userID types.UserID, url string) (jobID string, error) {
    // 1. Validate URL
    // 2. Create job record (status=pending)
    // 3. Return job ID (processing happens async)
}

func (s *IngestionService) ProcessJob(ctx context.Context, jobID string) error {
    // 1. Run yt-dlp to extract audio + metadata
    // 2. Transcribe audio via STT
    // 3. Scrape linked article if present
    // 4. Parse recipe via LLM
    // 5. Save recipe to DB
    // 6. Mark job done
}
```

yt-dlp invocation via `exec.CommandContext` — no shell, arguments as Go strings:
```go
cmd := exec.CommandContext(ctx, "yt-dlp",
    "--extract-audio", "--audio-format", "mp3",
    "--output", filepath.Join(tmpDir, "audio.%(ext)s"),
    "--write-info-json",
    url,
)
```

**Testing yt-dlp execution**: Put yt-dlp behind an interface:
```go
type MediaExtractor interface {
    Extract(ctx context.Context, url string, outputDir string) (*ExtractionResult, error)
}
type ExtractionResult struct {
    AudioPath    string
    Title        string
    Description  string
    Comments     []string
}
```
Unit tests use a stub extractor returning canned `ExtractionResult` with pre-existing audio files in `test/testdata/`. Integration tests can call the real yt-dlp if available (`if _, err := exec.LookPath("yt-dlp"); err != nil { t.Skip("yt-dlp not installed") }`).

- [ ] **Step 6: Run tests to verify they pass**
- [ ] **Step 7: Commit**

---

### Task 7: Job Queue Worker

**Files:**
- Create: `backend/internal/repo/jobs.go`
- Create: `backend/internal/worker/worker.go`
- Create: `backend/internal/worker/worker_test.go`

- [ ] **Step 1: Write failing test for JobRepo interface + Worker**

```go
func TestWorkerProcessesJob(t *testing.T) {
    stub := &stubJobRepo{jobs: []Job{{ID: "j1", Type: "test", Status: JobPending, Payload: map[string]any{}}}}
    processed := false
    w := worker.New(stub, "test", func(ctx context.Context, job *Job) error {
        processed = true
        return nil
    })
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()
    go w.Run(ctx)
    time.Sleep(500 * time.Millisecond)
    cancel()
    if !processed { t.Error("expected job to be processed") }
    if stub.jobs[0].Status != JobDone { t.Error("expected job marked done") }
}
```

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Write JobRepo**

Methods: `Create`, `GetByID`, `ClaimNext(type) (*Job, error)` (atomic: `UPDATE jobs SET status='running' WHERE id = (SELECT id FROM jobs WHERE status='pending' AND type=$1 ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING *`), `Complete`, `Fail`.

- [ ] **Step 4: Write worker loop**

```go
func (w *Worker) Run(ctx context.Context) {
    for {
        select {
        case <-ctx.Done():
            return
        default:
            job, err := w.jobs.ClaimNext(ctx, w.jobType)
            if job == nil {
                time.Sleep(2 * time.Second)
                continue
            }
            if err := w.handler(ctx, job); err != nil {
                w.jobs.Fail(ctx, job.ID, err.Error())
            } else {
                w.jobs.Complete(ctx, job.ID, nil)
            }
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**
- [ ] **Step 6: Commit**

---

### Task 8: Image Generation Service

**Files:**
- Create: `backend/internal/service/imagegen.go`
- Create: `backend/internal/service/imagegen_test.go`

- [ ] **Step 1: Write failing test**

Test that `GenerateStepImage` constructs the correct prompt and returns an image path.

- [ ] **Step 2: Implement Silicon Flow API client**

POST to Silicon Flow's Flux Schnell endpoint. Save returned image bytes to `/data/images/{recipe_id}/{step_index}.webp`. Update `recipe_steps.image_url`.

- [ ] **Step 3: Wire into worker** — register `generate_images` job type handler.
- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 9: Ingestion HTTP Handler + Integration Test

**Files:**
- Create: `backend/internal/handler/ingestion.go`
- Create: `backend/internal/handler/ingestion_test.go`
- Modify: `backend/cmd/server/main.go` (add routes, start worker goroutines)
- Create: `backend/test/integration/ingestion_test.go`

- [ ] **Step 1: Write handler**

`POST /ingest` with `{"url": "https://youtube.com/..."}` → validate → create job → return `{"job_id": "..."}`.
`GET /jobs/:id` → return job status + result.

Routes (add to protected group):
```go
r.Post("/ingest", ingestHandler.Create)
r.Get("/jobs/{id}", ingestHandler.GetJob)
```

- [ ] **Step 2: Write handler tests**
- [ ] **Step 3: Wire worker goroutines into main.go**

Start ingestion worker and image gen worker as goroutines in main, cancelled on shutdown.

- [ ] **Step 4: Write integration test**

Full flow with testcontainers: create user → submit ingestion job (with mocked yt-dlp + stub LLM) → poll job → verify recipe in DB.

- [ ] **Step 5: Run all tests**
- [ ] **Step 6: Commit**

---

## Dependency Graph

```
Task 1 (recipe repo) → Task 2 (recipe service) → Task 3 (recipe handlers)
Task 4 (LLM client) ──┐
Task 5 (STT client) ──┼→ Task 6 (ingestion service) → Task 9 (handler + integration)
Task 7 (job queue) ───┘
Task 8 (image gen) → Task 9
```

**Parallelizable**: Tasks 1, 4, 5, 7 can all run in parallel.
