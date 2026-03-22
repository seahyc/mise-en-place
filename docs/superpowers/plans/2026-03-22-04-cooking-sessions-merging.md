# Cooking Sessions + Multi-Recipe Merging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the cooking session lifecycle (create, start, pause, complete) and the multi-recipe runtime merging feature — the core differentiator where multiple recipes are merged into one optimised cooking session via LLM.

**Architecture:** Session service creates sessions from selected recipes, calls LLM to merge steps (for multi-recipe), persists merged steps, manages state transitions. WebSocket endpoint streams session updates to connected clients.

**Tech Stack:** Go, pgx, Kimi/GLM (from Plan 2), WebSocket (from Plan 3)

**Spec:** `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md` (section 3)

**Dependency:** Plan 1 (foundation), Plan 2 Task 1 (recipe repo), Plan 2 Task 4 (LLM client)

---

### Task 1: Session Repository

**Files:**
- Create: `backend/internal/repo/sessions.go`
- Create: `backend/internal/repo/sessions_test.go`

- [ ] **Step 1: Write failing test**
- [ ] **Step 2: Implement PgSessionRepo**

Methods:
- `Create(ctx, userID, recipeIDs) (*types.CookingSession, error)` — insert session + session_recipes
- `GetByID(ctx, id) (*types.CookingSession, error)` — with steps and recipe IDs
- `UpdateStatus(ctx, id, status) error`
- `AddSteps(ctx, sessionID, steps []SessionStepInput) error` — bulk insert merged steps
- `UpdateStep(ctx, stepID, updates) error` — mark complete, add agent notes
- `ListByUser(ctx, userID) ([]types.CookingSession, error)`

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 2: Recipe Merge Service

**Files:**
- Create: `backend/internal/service/merge.go`
- Create: `backend/internal/service/merge_test.go`
- Create: `backend/test/golden/merge_prompt.txt`
- Create: `backend/test/golden/merge_response.json`

- [ ] **Step 1: Write failing test with golden files**

Given 2 recipes (Pad Thai + Green Curry), assert the merge service:
1. Constructs the correct prompt (compare to golden `merge_prompt.txt`)
2. Parses the LLM response into ordered SessionSteps with dish tags

Use stub LLM that returns content from `merge_response.json`.

- [ ] **Step 2: Run test to verify it fails**

- [ ] **Step 3: Implement MergeService**

```go
type MergeService struct {
    llm llm.Client
}

type MergeResult struct {
    Steps []MergedStep
}

type MergedStep struct {
    OrderIndex    int    `json:"order_index"`
    Text          string `json:"text"`
    SourceDishTag string `json:"source_dish_tag"`
}

func (s *MergeService) MergeRecipes(ctx context.Context, recipes []types.Recipe) (*MergeResult, error) {
    // 1. Build system prompt: "You are a professional chef..."
    // 2. Build user message: all recipes' ingredients + steps as structured text
    // 3. Call LLM
    // 4. Parse JSON response into MergedSteps
    // 5. Return
}
```

System prompt (store as constant):
```
You are a professional chef. Merge these recipes into one optimised cooking session.
Identify shared prep (e.g., garlic/onion for multiple dishes), parallel steps
(rice soaking while you prep curry), and optimal ordering.
Output a JSON array of steps, each with: order_index, text, source_dish_tag.
source_dish_tag is the recipe title(s) this step belongs to.
```

- [ ] **Step 4: Test single-recipe degenerate case** — one recipe in, steps pass through unchanged with dish tag
- [ ] **Step 5: Run tests**
- [ ] **Step 6: Commit**

---

### Task 3: Session Service

**Files:**
- Create: `backend/internal/service/session.go`
- Create: `backend/internal/service/session_test.go`

- [ ] **Step 1: Write failing tests**

Test:
- `CreateSession` with 1 recipe → steps copied from recipe, no merge
- `CreateSession` with 3 recipes → merge service called, merged steps saved
- `StartSession` → status changes to in_progress, started_at set
- `CompleteStep` → step marked done, check if all done → auto-complete session
- `PauseSession` / `ResumeSession` state transitions

- [ ] **Step 2: Implement SessionService**

```go
type SessionService struct {
    sessions repo.SessionRepo
    recipes  repo.RecipeRepo
    merge    *MergeService
}

func (s *SessionService) Create(ctx context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error) {
    // 1. Fetch all recipes
    // 2. If len > 1: call merge service
    //    If len == 1: convert recipe steps to session steps directly
    // 3. Create session with steps
    // 4. Return session
}

func (s *SessionService) Start(ctx context.Context, sessionID types.SessionID) error
func (s *SessionService) Pause(ctx context.Context, sessionID types.SessionID) error
func (s *SessionService) Resume(ctx context.Context, sessionID types.SessionID) error
func (s *SessionService) CompleteStep(ctx context.Context, sessionID types.SessionID, stepID string) error
func (s *SessionService) GetState(ctx context.Context, sessionID types.SessionID) (*types.CookingSession, error)
```

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 4: Session HTTP Handlers

**Files:**
- Create: `backend/internal/handler/sessions.go`
- Create: `backend/internal/handler/sessions_test.go`
- Modify: `backend/cmd/server/main.go`

- [ ] **Step 1: Write failing handler tests**

- POST `/sessions` with `{"recipe_ids": ["id1", "id2"]}` → 201 with session
- GET `/sessions/:id` → 200 with full session state
- POST `/sessions/:id/start` → 200
- POST `/sessions/:id/steps/:step_id/complete` → 200
- GET `/sessions` → 200 list

- [ ] **Step 2: Implement handlers**

Routes (add to protected group):
```go
r.Route("/sessions", func(r chi.Router) {
    r.Post("/", sessionHandler.Create)
    r.Get("/", sessionHandler.List)
    r.Get("/{id}", sessionHandler.Get)
    r.Post("/{id}/start", sessionHandler.Start)
    r.Post("/{id}/pause", sessionHandler.Pause)
    r.Post("/{id}/resume", sessionHandler.Resume)
    r.Post("/{id}/steps/{stepID}/complete", sessionHandler.CompleteStep)
})
```

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 5: Realtime Session Updates WebSocket

**Files:**
- Create: `backend/internal/handler/session_ws.go`
- Create: `backend/internal/handler/session_ws_test.go`

- [ ] **Step 1: Write failing test**

WebSocket test: connect to `/ws/session/:id` → when a step is completed via HTTP, the WebSocket receives an update message.

- [ ] **Step 2: Implement session update broadcaster**

```go
// Simple pub/sub: sessions register WebSocket connections,
// session service publishes updates when state changes.

type SessionHub struct {
    mu       sync.RWMutex
    sessions map[types.SessionID][]chan SessionEvent
}

type SessionEvent struct {
    Type string         `json:"type"` // step_completed, session_started, etc.
    Data map[string]any `json:"data"`
}

func (h *SessionHub) Subscribe(sessionID types.SessionID) <-chan SessionEvent
func (h *SessionHub) Publish(sessionID types.SessionID, event SessionEvent)
```

WebSocket handler: authenticate, subscribe to session events, write events as JSON text frames.

- [ ] **Step 3: Wire into session service** — publish events on state transitions
- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 6: Integration Test — Full Session Flow

**Files:**
- Create: `backend/test/integration/session_test.go`

- [ ] **Step 1: Write integration test**

Full flow with testcontainers + stub LLM:
1. Create user
2. Create 2 recipes
3. Create session with both recipe IDs (merge service uses stub LLM)
4. Assert session has merged steps with dish tags
5. Start session → assert status = in_progress
6. Complete each step → assert progress
7. Complete last step → assert session auto-completes

- [ ] **Step 2: Run integration test**
- [ ] **Step 3: Commit**

---

## Dependency Graph

```
Task 1 (session repo) → Task 3 (session service) → Task 4 (handlers) → Task 6 (integration)
Task 2 (merge service) → Task 3
Task 5 (realtime WS) → Task 6
```

**Parallelizable**: Tasks 1, 2, 5 can run in parallel.
