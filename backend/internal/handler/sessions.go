package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// SessionHandler contains HTTP handlers for cooking session endpoints.
type SessionHandler struct {
	svc *service.SessionService
}

// NewSessionHandler creates a new SessionHandler.
func NewSessionHandler(svc *service.SessionService) *SessionHandler {
	return &SessionHandler{svc: svc}
}

// Create handles POST /sessions.
func (h *SessionHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RecipeIDs []types.RecipeID `json:"recipe_ids"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if len(req.RecipeIDs) == 0 {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "recipe_ids is required"})
		return
	}

	userID := GetUserID(r.Context())
	sess, err := h.svc.Create(r.Context(), userID, req.RecipeIDs)
	if err != nil {
		h.writeError(w, err)
		return
	}

	WriteJSON(w, http.StatusCreated, sess)
}

// List handles GET /sessions.
func (h *SessionHandler) List(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())
	sessions, err := h.svc.ListByUser(r.Context(), userID)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
		return
	}
	WriteJSON(w, http.StatusOK, sessions)
}

// Get handles GET /sessions/{id}.
func (h *SessionHandler) Get(w http.ResponseWriter, r *http.Request) {
	id := types.SessionID(chi.URLParam(r, "id"))
	sess, err := h.svc.GetState(r.Context(), id)
	if err != nil {
		h.writeError(w, err)
		return
	}
	WriteJSON(w, http.StatusOK, sess)
}

// Start handles POST /sessions/{id}/start.
func (h *SessionHandler) Start(w http.ResponseWriter, r *http.Request) {
	id := types.SessionID(chi.URLParam(r, "id"))
	if err := h.svc.Start(r.Context(), id); err != nil {
		h.writeError(w, err)
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"status": "started"})
}

// Pause handles POST /sessions/{id}/pause.
func (h *SessionHandler) Pause(w http.ResponseWriter, r *http.Request) {
	id := types.SessionID(chi.URLParam(r, "id"))
	if err := h.svc.Pause(r.Context(), id); err != nil {
		h.writeError(w, err)
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"status": "paused"})
}

// Resume handles POST /sessions/{id}/resume.
func (h *SessionHandler) Resume(w http.ResponseWriter, r *http.Request) {
	id := types.SessionID(chi.URLParam(r, "id"))
	if err := h.svc.Resume(r.Context(), id); err != nil {
		h.writeError(w, err)
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"status": "resumed"})
}

// CompleteStep handles POST /sessions/{id}/steps/{stepID}/complete.
func (h *SessionHandler) CompleteStep(w http.ResponseWriter, r *http.Request) {
	id := types.SessionID(chi.URLParam(r, "id"))
	stepID := chi.URLParam(r, "stepID")
	if err := h.svc.CompleteStep(r.Context(), id, stepID); err != nil {
		h.writeError(w, err)
		return
	}
	WriteJSON(w, http.StatusOK, map[string]string{"status": "completed"})
}

// writeError maps service errors to HTTP responses.
func (h *SessionHandler) writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrSessionNotFound):
		WriteJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrRecipeNotFound):
		WriteJSON(w, http.StatusNotFound, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrNoRecipes):
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
	default:
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
	}
}
