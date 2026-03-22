package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// RecipeHandler contains HTTP handlers for recipe endpoints.
type RecipeHandler struct {
	svc *service.RecipeService
}

// NewRecipeHandler creates a new RecipeHandler.
func NewRecipeHandler(svc *service.RecipeService) *RecipeHandler {
	return &RecipeHandler{svc: svc}
}

// Create handles POST /recipes.
func (h *RecipeHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())

	var req struct {
		Title       string   `json:"title"`
		Description string   `json:"description"`
		SourceURL   string   `json:"source_url"`
		SourceType  string   `json:"source_type"`
		Cuisine     string   `json:"cuisine"`
		Ingredients []string `json:"ingredients"`
		Steps       []struct {
			OrderIndex int    `json:"order_index"`
			Text       string `json:"text"`
		} `json:"steps"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}

	steps := make([]repo.StepInput, len(req.Steps))
	for i, s := range req.Steps {
		steps[i] = repo.StepInput{OrderIndex: s.OrderIndex, Text: s.Text}
	}

	recipe, err := h.svc.Create(r.Context(), repo.CreateRecipeArgs{
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		SourceURL:   req.SourceURL,
		SourceType:  req.SourceType,
		Cuisine:     req.Cuisine,
		Ingredients: req.Ingredients,
		Steps:       steps,
	})
	if err != nil {
		h.writeError(w, err)
		return
	}

	WriteJSON(w, http.StatusCreated, recipe)
}

// List handles GET /recipes.
func (h *RecipeHandler) List(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	recipes, total, err := h.svc.List(r.Context(), userID, limit, offset)
	if err != nil {
		h.writeError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, map[string]any{
		"recipes": recipes,
		"total":   total,
	})
}

// Get handles GET /recipes/{id}.
func (h *RecipeHandler) Get(w http.ResponseWriter, r *http.Request) {
	id := types.RecipeID(chi.URLParam(r, "id"))

	recipe, err := h.svc.Get(r.Context(), id)
	if err != nil {
		h.writeError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, recipe)
}

// Update handles PUT /recipes/{id}.
func (h *RecipeHandler) Update(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())
	id := types.RecipeID(chi.URLParam(r, "id"))

	var req struct {
		Title       *string  `json:"title"`
		Description *string  `json:"description"`
		SourceURL   *string  `json:"source_url"`
		SourceType  *string  `json:"source_type"`
		Cuisine     *string  `json:"cuisine"`
		Ingredients []string `json:"ingredients"`
		Steps       *[]struct {
			OrderIndex int    `json:"order_index"`
			Text       string `json:"text"`
		} `json:"steps"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}

	args := repo.UpdateRecipeArgs{
		Title:       req.Title,
		Description: req.Description,
		SourceURL:   req.SourceURL,
		SourceType:  req.SourceType,
		Cuisine:     req.Cuisine,
		Ingredients: req.Ingredients,
	}
	if req.Steps != nil {
		steps := make([]repo.StepInput, len(*req.Steps))
		for i, s := range *req.Steps {
			steps[i] = repo.StepInput{OrderIndex: s.OrderIndex, Text: s.Text}
		}
		args.Steps = steps
	}

	if err := h.svc.Update(r.Context(), userID, id, args); err != nil {
		h.writeError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// Delete handles DELETE /recipes/{id}.
func (h *RecipeHandler) Delete(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())
	id := types.RecipeID(chi.URLParam(r, "id"))

	if err := h.svc.Delete(r.Context(), userID, id); err != nil {
		h.writeError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// writeError maps service errors to HTTP status codes.
func (h *RecipeHandler) writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrEmptyTitle):
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrNotFound):
		WriteJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrForbidden):
		WriteJSON(w, http.StatusForbidden, map[string]string{"error": err.Error()})
	default:
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
	}
}
