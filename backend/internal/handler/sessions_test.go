package handler_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// --- Stubs ---

type stubLLMClient struct{}

func (s *stubLLMClient) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	return &llm.Response{Content: "[]"}, nil
}
func (s *stubLLMClient) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	return &llm.Response{Content: "[]"}, nil
}

type sessStubRecipeRepo struct {
	recipes map[types.RecipeID]*types.Recipe
}

func (s *sessStubRecipeRepo) GetByID(_ context.Context, id types.RecipeID) (*types.Recipe, error) {
	r := s.recipes[id]
	return r, nil
}

func (s *sessStubRecipeRepo) Create(_ context.Context, _ repo.CreateRecipeArgs) (*types.Recipe, error) {
	return nil, nil
}

func (s *sessStubRecipeRepo) ListByUser(_ context.Context, _ types.UserID, _, _ int) ([]types.Recipe, int, error) {
	return nil, 0, nil
}

func (s *sessStubRecipeRepo) Update(_ context.Context, _ types.RecipeID, _ repo.UpdateRecipeArgs) error {
	return nil
}

func (s *sessStubRecipeRepo) Delete(_ context.Context, _ types.RecipeID) error {
	return nil
}

type stubSessionRepo struct {
	sessions map[types.SessionID]*types.CookingSession
	nextID   int
}

func newStubSessionRepo() *stubSessionRepo {
	return &stubSessionRepo{sessions: make(map[types.SessionID]*types.CookingSession)}
}

func (s *stubSessionRepo) Create(_ context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error) {
	s.nextID++
	id := types.SessionID(fmt.Sprintf("sess-%d", s.nextID))
	sess := &types.CookingSession{
		ID: id, UserID: userID, Status: types.SessionSetup,
		RecipeIDs: recipeIDs, Steps: []types.SessionStep{},
	}
	s.sessions[id] = sess
	return sess, nil
}

func (s *stubSessionRepo) GetByID(_ context.Context, id types.SessionID) (*types.CookingSession, error) {
	sess := s.sessions[id]
	return sess, nil
}

func (s *stubSessionRepo) UpdateStatus(_ context.Context, id types.SessionID, status types.SessionStatus) error {
	if sess := s.sessions[id]; sess != nil {
		sess.Status = status
	}
	return nil
}

func (s *stubSessionRepo) AddSteps(_ context.Context, sessionID types.SessionID, steps []repo.SessionStepInput) error {
	sess := s.sessions[sessionID]
	if sess == nil {
		return nil
	}
	for i, st := range steps {
		sess.Steps = append(sess.Steps, types.SessionStep{
			ID: fmt.Sprintf("step-%d", i), OrderIndex: st.OrderIndex,
			Text: st.Text, SourceDishTag: st.SourceDishTag,
		})
	}
	return nil
}

func (s *stubSessionRepo) UpdateStep(_ context.Context, stepID string, isCompleted bool, agentNotes string) error {
	return nil
}

func (s *stubSessionRepo) ListByUser(_ context.Context, _ types.UserID) ([]types.CookingSession, error) {
	return []types.CookingSession{}, nil
}

// --- Helpers ---

func setupSessionHandler() *handler.SessionHandler {
	recipeRepo := &sessStubRecipeRepo{
		recipes: map[types.RecipeID]*types.Recipe{
			"r1": {ID: "r1", Title: "Pasta", Steps: []types.RecipeStep{{OrderIndex: 0, Text: "Boil"}}},
		},
	}
	sessRepo := newStubSessionRepo()
	mergeSvc := service.NewMergeService(&stubLLMClient{})
	svc := service.NewSessionService(sessRepo, recipeRepo, mergeSvc)
	return handler.NewSessionHandler(svc)
}

// withUserID injects a user ID into the request context via the handler middleware key.
func withUserID(r *http.Request, userID types.UserID) *http.Request {
	// Use the handler's AuthMiddleware approach: set context value.
	// Since the contextKey is unexported we generate a token and use the real middleware.
	// For simplicity, we'll use service.GenerateAccessToken + handler.AuthMiddleware.
	token, _ := service.GenerateAccessToken(userID, "test-secret", 60*1e9)
	r.Header.Set("Authorization", "Bearer "+token)

	// Run through middleware to set context.
	var captured *http.Request
	mw := handler.AuthMiddleware("test-secret")
	h := mw(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		captured = r
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, r)
	return captured
}

func TestSessionHandler_Create(t *testing.T) {
	h := setupSessionHandler()

	body := `{"recipe_ids":["r1"]}`
	req := httptest.NewRequest(http.MethodPost, "/sessions", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUserID(req, "user1")
	if req == nil {
		t.Fatal("withUserID returned nil — auth middleware rejected request")
	}

	rec := httptest.NewRecorder()
	h.Create(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", rec.Code, rec.Body.String())
	}

	var sess types.CookingSession
	if err := json.NewDecoder(rec.Body).Decode(&sess); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if sess.ID == "" {
		t.Error("expected non-empty session ID")
	}
}

func TestSessionHandler_Create_MissingRecipeIDs(t *testing.T) {
	h := setupSessionHandler()

	body := `{}`
	req := httptest.NewRequest(http.MethodPost, "/sessions", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req = withUserID(req, "user1")

	rec := httptest.NewRecorder()
	h.Create(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestSessionHandler_List(t *testing.T) {
	h := setupSessionHandler()

	req := httptest.NewRequest(http.MethodGet, "/sessions", nil)
	req = withUserID(req, "user1")

	rec := httptest.NewRecorder()
	h.List(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}

func TestSessionHandler_Get_NotFound(t *testing.T) {
	h := setupSessionHandler()

	req := httptest.NewRequest(http.MethodGet, "/sessions/nonexistent", nil)
	req = withUserID(req, "user1")

	// Set chi URL param.
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("id", "nonexistent")
	req = req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))

	rec := httptest.NewRecorder()
	h.Get(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d: %s", rec.Code, rec.Body.String())
	}
}
