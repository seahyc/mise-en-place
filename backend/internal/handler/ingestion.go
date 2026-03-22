package handler

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/yingcong/mise-en-place/backend/internal/service"
)

// IngestHandler contains HTTP handlers for video ingestion endpoints.
type IngestHandler struct {
	ingestion *service.IngestionService
	jobs      service.JobRepo
}

// NewIngestHandler creates a new IngestHandler.
func NewIngestHandler(ingestion *service.IngestionService, jobs service.JobRepo) *IngestHandler {
	return &IngestHandler{ingestion: ingestion, jobs: jobs}
}

// Ingest handles POST /ingest.
func (h *IngestHandler) Ingest(w http.ResponseWriter, r *http.Request) {
	userID := GetUserID(r.Context())

	var req struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
		return
	}
	if req.URL == "" {
		WriteJSON(w, http.StatusBadRequest, map[string]string{"error": "url is required"})
		return
	}

	jobID, err := h.ingestion.Ingest(r.Context(), userID, req.URL)
	if err != nil {
		if errors.Is(err, service.ErrInvalidURL) {
			WriteJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
			return
		}
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
		return
	}

	WriteJSON(w, http.StatusAccepted, map[string]string{"job_id": jobID})
}

// GetJob handles GET /jobs/{id}.
func (h *IngestHandler) GetJob(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	job, err := h.jobs.GetByID(r.Context(), id)
	if err != nil {
		WriteJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal server error"})
		return
	}
	if job == nil {
		WriteJSON(w, http.StatusNotFound, map[string]string{"error": "job not found"})
		return
	}

	WriteJSON(w, http.StatusOK, job)
}
