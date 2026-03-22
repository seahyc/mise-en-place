package handler_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"github.com/yingcong/mise-en-place/backend/internal/handler"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// stubRecipeRepo is a minimal in-memory implementation for handler tests.
type stubRecipeRepo struct {
	recipes map[types.RecipeID]*types.Recipe
	nextID  int
}

func newStubRecipeRepo() *stubRecipeRepo {
	return &stubRecipeRepo{recipes: make(map[types.RecipeID]*types.Recipe)}
}

func (s *stubRecipeRepo) Create(_ context.Context, args repo.CreateRecipeArgs) (*types.Recipe, error) {
	s.nextID++
	id := types.RecipeID("recipe-1")
	r := &types.Recipe{
		ID:          id,
		UserID:      args.UserID,
		Title:       args.Title,
		Description: args.Description,
		SourceType:  args.SourceType,
		Ingredients: args.Ingredients,
	}
	for _, step := range args.Steps {
		r.Steps = append(r.Steps, types.RecipeStep{OrderIndex: step.OrderIndex, Text: step.Text})
	}
	s.recipes[id] = r
	return r, nil
}

func (s *stubRecipeRepo) GetByID(_ context.Context, id types.RecipeID) (*types.Recipe, error) {
	r, ok := s.recipes[id]
	if !ok {
		return nil, nil
	}
	return r, nil
}

func (s *stubRecipeRepo) ListByUser(_ context.Context, _ types.UserID, _, _ int) ([]types.Recipe, int, error) {
	return []types.Recipe{}, 0, nil
}

func (s *stubRecipeRepo) Update(_ context.Context, _ types.RecipeID, _ repo.UpdateRecipeArgs) error {
	return nil
}

func (s *stubRecipeRepo) Delete(_ context.Context, _ types.RecipeID) error {
	return nil
}

func setupRouter(h *handler.RecipeHandler) *chi.Mux {
	r := chi.NewRouter()
	r.Post("/recipes", h.Create)
	r.Get("/recipes", h.List)
	r.Get("/recipes/{id}", h.Get)
	r.Put("/recipes/{id}", h.Update)
	r.Delete("/recipes/{id}", h.Delete)
	return r
}

func TestRecipeHandler_CreateMissingTitle(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	body := `{"description":"test"}`
	req := httptest.NewRequest(http.MethodPost, "/recipes", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}

	var resp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if _, ok := resp["error"]; !ok {
		t.Fatal("expected error field in response")
	}
}

func TestRecipeHandler_CreateSuccess(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	body := `{"title":"Pasta","description":"Delicious pasta"}`
	req := httptest.NewRequest(http.MethodPost, "/recipes", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status 201, got %d; body: %s", rec.Code, rec.Body.String())
	}
}

func TestRecipeHandler_GetNotFound(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	req := httptest.NewRequest(http.MethodGet, "/recipes/nonexistent", nil)
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rec.Code)
	}
}

func TestRecipeHandler_DeleteNotFound(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	req := httptest.NewRequest(http.MethodDelete, "/recipes/nonexistent", nil)
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rec.Code)
	}
}

func TestRecipeHandler_ListEmpty(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	req := httptest.NewRequest(http.MethodGet, "/recipes", nil)
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var resp map[string]any
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if resp["total"].(float64) != 0 {
		t.Fatalf("expected total 0, got %v", resp["total"])
	}
}

func TestRecipeHandler_InvalidJSON(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := service.NewRecipeService(stub)
	h := handler.NewRecipeHandler(svc)

	req := httptest.NewRequest(http.MethodPost, "/recipes", strings.NewReader("not json"))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}
