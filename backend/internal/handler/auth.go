package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/yingcong/mise-en-place/backend/internal/service"
)

// WriteJSON encodes v as JSON and writes it with the given status code.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// HealthCheck returns {"status":"ok"} with a 200 status.
func HealthCheck(w http.ResponseWriter, r *http.Request) {
	WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// AuthHandler contains HTTP handlers for authentication endpoints.
type AuthHandler struct {
	auth *service.AuthService
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(auth *service.AuthService) *AuthHandler {
	return &AuthHandler{auth: auth}
}

// Register handles user registration.
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.Email == "" || req.Password == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "email and password are required"})
		return
	}

	tp, err := h.auth.Register(r.Context(), req.Email, req.Password, req.DisplayName)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}

	WriteJSON(w, http.StatusCreated, tp)
}

// Login handles email/password authentication.
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.Email == "" || req.Password == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "email and password are required"})
		return
	}

	tp, err := h.auth.Login(r.Context(), req.Email, req.Password)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, tp)
}

// Refresh handles token refresh.
func (h *AuthHandler) Refresh(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.RefreshToken == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "refresh_token is required"})
		return
	}

	tp, err := h.auth.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, tp)
}

// GoogleLogin handles Google OAuth authentication.
func (h *AuthHandler) GoogleLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IDToken string `json:"id_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.IDToken == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "id_token is required"})
		return
	}

	tp, err := h.auth.GoogleLogin(r.Context(), req.IDToken)
	if err != nil {
		h.writeServiceError(w, err)
		return
	}

	WriteJSON(w, http.StatusOK, tp)
}

// writeServiceError maps service-layer sentinel errors to HTTP status codes.
func (h *AuthHandler) writeServiceError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, service.ErrEmailTaken):
		WriteJSON(w, http.StatusConflict, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrInvalidCreds):
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrInvalidToken), errors.Is(err, service.ErrTokenExpired):
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
	case errors.Is(err, service.ErrGoogleIDToken):
		WriteJSON(w, http.StatusUnauthorized, map[string]string{"error": err.Error()})
	default:
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
	}
}
