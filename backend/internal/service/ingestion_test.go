package service

import (
	"context"
	"encoding/json"
	"os"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/stt"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// --- Stubs ---

type stubLLMClient struct {
	response string
}

func (s *stubLLMClient) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	return &llm.Response{Content: s.response}, nil
}

func (s *stubLLMClient) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	return &llm.Response{Content: s.response}, nil
}

type stubSTTClient struct {
	transcript string
}

func (s *stubSTTClient) Transcribe(_ context.Context, _ []byte, _ string) (string, error) {
	return s.transcript, nil
}

var _ stt.Client = (*stubSTTClient)(nil)

type stubMediaExtractor struct{}

func (s *stubMediaExtractor) Extract(_ context.Context, _, _ string) (*ExtractionResult, error) {
	return &ExtractionResult{AudioPath: "/tmp/audio.m4a", Title: "Test"}, nil
}

type stubJobRepo struct {
	jobs   map[string]*types.Job
	nextID int
}

func newStubJobRepo() *stubJobRepo {
	return &stubJobRepo{jobs: make(map[string]*types.Job)}
}

func (s *stubJobRepo) Create(_ context.Context, jobType types.JobType, userID types.UserID, payload map[string]any) (string, error) {
	s.nextID++
	id := "job-1"
	s.jobs[id] = &types.Job{
		ID:      id,
		Type:    jobType,
		Status:  types.JobPending,
		Payload: payload,
		UserID:  userID,
	}
	return id, nil
}

func (s *stubJobRepo) GetByID(_ context.Context, id string) (*types.Job, error) {
	j, ok := s.jobs[id]
	if !ok {
		return nil, nil
	}
	return j, nil
}

func (s *stubJobRepo) Complete(_ context.Context, id string, result map[string]any) error {
	if j, ok := s.jobs[id]; ok {
		j.Status = types.JobDone
		j.Result = result
	}
	return nil
}

func (s *stubJobRepo) Fail(_ context.Context, id string, errMsg string) error {
	if j, ok := s.jobs[id]; ok {
		j.Status = types.JobFailed
		j.Error = errMsg
	}
	return nil
}

// --- Tests ---

func TestValidateIngestionURL(t *testing.T) {
	tests := []struct {
		name    string
		url     string
		wantErr bool
	}{
		{"youtube", "https://www.youtube.com/watch?v=abc", false},
		{"youtu.be", "https://youtu.be/abc", false},
		{"tiktok", "https://www.tiktok.com/@user/video/123", false},
		{"instagram", "https://www.instagram.com/p/abc", false},
		{"bilibili", "https://www.bilibili.com/video/BV123", false},
		{"xiaohongshu", "https://www.xiaohongshu.com/explore/123", false},
		{"disallowed host", "https://evil.com/video", true},
		{"empty", "", true},
		{"no scheme", "youtube.com/watch?v=abc", true},
		{"random text", "not a url", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateIngestionURL(tt.url)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateIngestionURL(%q) error = %v, wantErr %v", tt.url, err, tt.wantErr)
			}
		})
	}
}

func TestIngestionService_Ingest(t *testing.T) {
	jobRepo := newStubJobRepo()
	svc := NewIngestionService(nil, nil, nil, jobRepo, nil)

	_, err := svc.Ingest(context.Background(), "user-1", "https://evil.com/video")
	if err != ErrInvalidURL {
		t.Fatalf("expected ErrInvalidURL, got %v", err)
	}

	jobID, err := svc.Ingest(context.Background(), "user-1", "https://www.youtube.com/watch?v=abc")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if jobID == "" {
		t.Fatal("expected non-empty job ID")
	}
}

func TestIngestionService_ParseRecipeGoldenFile(t *testing.T) {
	goldenData, err := os.ReadFile("../../test/golden/ingestion_parsed_recipe.json")
	if err != nil {
		t.Fatalf("read golden file: %v", err)
	}

	// The stub LLM returns the golden JSON directly
	stubLLM := &stubLLMClient{response: string(goldenData)}
	stubSTT := &stubSTTClient{transcript: "test transcript"}
	stubExtractor := &stubMediaExtractor{}
	jobRepo := newStubJobRepo()
	recipeRepo := newStubRecipeRepo()

	svc := NewIngestionService(stubLLM, stubSTT, recipeRepo, jobRepo, stubExtractor)

	// Create a job first
	jobID, err := svc.Ingest(context.Background(), "user-1", "https://www.youtube.com/watch?v=abc")
	if err != nil {
		t.Fatalf("ingest: %v", err)
	}

	// Process the job
	err = svc.ProcessJob(context.Background(), jobID)
	if err != nil {
		t.Fatalf("process job: %v", err)
	}

	// Verify the job was completed
	job, _ := jobRepo.GetByID(context.Background(), jobID)
	if job.Status != types.JobDone {
		t.Fatalf("expected job status done, got %s", job.Status)
	}

	// Verify the recipe was created with correct data
	recipeID, ok := job.Result["recipe_id"].(string)
	if !ok || recipeID == "" {
		t.Fatal("expected recipe_id in job result")
	}

	recipe, _ := recipeRepo.GetByID(context.Background(), types.RecipeID(recipeID))
	if recipe == nil {
		t.Fatal("expected recipe to be created")
	}

	// Verify against golden file
	var expected ParsedRecipe
	if err := json.Unmarshal(goldenData, &expected); err != nil {
		t.Fatalf("unmarshal golden: %v", err)
	}

	if recipe.Title != expected.Title {
		t.Errorf("title = %q, want %q", recipe.Title, expected.Title)
	}
	if len(recipe.Ingredients) != len(expected.Ingredients) {
		t.Errorf("ingredients count = %d, want %d", len(recipe.Ingredients), len(expected.Ingredients))
	}
	if len(recipe.Steps) != len(expected.Steps) {
		t.Errorf("steps count = %d, want %d", len(recipe.Steps), len(expected.Steps))
	}
}

// Verify stubs satisfy interfaces.
func TestStubInterfaces(t *testing.T) {
	var _ llm.Client = (*stubLLMClient)(nil)
	var _ stt.Client = (*stubSTTClient)(nil)
	var _ MediaExtractor = (*stubMediaExtractor)(nil)
	var _ JobRepo = (*stubJobRepo)(nil)
	var _ repo.RecipeRepo = (*stubRecipeRepo)(nil)
}
