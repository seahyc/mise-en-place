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
	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// --- Stubs for ingestion handler tests ---

type stubLLM struct{}

func (s *stubLLM) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	return &llm.Response{}, nil
}
func (s *stubLLM) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	return &llm.Response{}, nil
}

type stubSTT struct{}

func (s *stubSTT) Transcribe(_ context.Context, _ []byte, _ string) (string, error) {
	return "", nil
}

type stubExtractor struct{}

func (s *stubExtractor) Extract(_ context.Context, _, _ string) (*service.ExtractionResult, error) {
	return &service.ExtractionResult{}, nil
}

type stubIngestionJobRepo struct {
	jobs map[string]*types.Job
}

func newStubIngestionJobRepo() *stubIngestionJobRepo {
	return &stubIngestionJobRepo{jobs: make(map[string]*types.Job)}
}

func (s *stubIngestionJobRepo) Create(_ context.Context, jobType types.JobType, userID types.UserID, payload map[string]any) (string, error) {
	id := "job-123"
	s.jobs[id] = &types.Job{
		ID:      id,
		Type:    jobType,
		Status:  types.JobPending,
		Payload: payload,
		UserID:  userID,
	}
	return id, nil
}

func (s *stubIngestionJobRepo) GetByID(_ context.Context, id string) (*types.Job, error) {
	j, ok := s.jobs[id]
	if !ok {
		return nil, nil
	}
	return j, nil
}

func (s *stubIngestionJobRepo) Complete(_ context.Context, id string, result map[string]any) error {
	return nil
}

func (s *stubIngestionJobRepo) Fail(_ context.Context, id string, errMsg string) error {
	return nil
}

var _ stt.Client = (*stubSTT)(nil)

func setupIngestionRouter(h *handler.IngestHandler) *chi.Mux {
	r := chi.NewRouter()
	r.Post("/ingest", h.Ingest)
	r.Get("/jobs/{id}", h.GetJob)
	return r
}

func TestIngestHandler_MissingURL(t *testing.T) {
	jobRepo := newStubIngestionJobRepo()
	svc := service.NewIngestionService(nil, nil, nil, jobRepo, nil)
	h := handler.NewIngestHandler(svc, jobRepo)

	body := `{}`
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupIngestionRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d", rec.Code)
	}
}

func TestIngestHandler_InvalidURL(t *testing.T) {
	jobRepo := newStubIngestionJobRepo()
	svc := service.NewIngestionService(nil, nil, nil, jobRepo, nil)
	h := handler.NewIngestHandler(svc, jobRepo)

	body := `{"url":"https://evil.com/video"}`
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupIngestionRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d; body: %s", rec.Code, rec.Body.String())
	}
}

func TestIngestHandler_Success(t *testing.T) {
	jobRepo := newStubIngestionJobRepo()
	svc := service.NewIngestionService(nil, nil, nil, jobRepo, nil)
	h := handler.NewIngestHandler(svc, jobRepo)

	body := `{"url":"https://www.youtube.com/watch?v=abc"}`
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router := setupIngestionRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusAccepted {
		t.Fatalf("expected status 202, got %d; body: %s", rec.Code, rec.Body.String())
	}

	var resp map[string]string
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["job_id"] == "" {
		t.Fatal("expected non-empty job_id")
	}
}

func TestIngestHandler_GetJobNotFound(t *testing.T) {
	jobRepo := newStubIngestionJobRepo()
	svc := service.NewIngestionService(nil, nil, nil, jobRepo, nil)
	h := handler.NewIngestHandler(svc, jobRepo)

	req := httptest.NewRequest(http.MethodGet, "/jobs/nonexistent", nil)
	rec := httptest.NewRecorder()

	router := setupIngestionRouter(h)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", rec.Code)
	}
}

func TestIngestHandler_GetJobSuccess(t *testing.T) {
	jobRepo := newStubIngestionJobRepo()
	svc := service.NewIngestionService(nil, nil, nil, jobRepo, nil)
	h := handler.NewIngestHandler(svc, jobRepo)

	// Create a job first
	body := `{"url":"https://www.youtube.com/watch?v=abc"}`
	req := httptest.NewRequest(http.MethodPost, "/ingest", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	router := setupIngestionRouter(h)
	router.ServeHTTP(rec, req)

	var createResp map[string]string
	json.NewDecoder(rec.Body).Decode(&createResp)

	// Now get the job
	req = httptest.NewRequest(http.MethodGet, "/jobs/"+createResp["job_id"], nil)
	rec = httptest.NewRecorder()
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}
}
