package service_test

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// stubLLMClient returns a fixed response for every Chat call.
type stubLLMClient struct {
	response string
	called   bool
}

func (s *stubLLMClient) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	s.called = true
	return &llm.Response{Content: s.response}, nil
}

func (s *stubLLMClient) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	s.called = true
	return &llm.Response{Content: s.response}, nil
}

func goldenPath(name string) string {
	_, thisFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "test", "golden", name)
}

func TestMergeRecipes_SingleRecipe(t *testing.T) {
	stub := &stubLLMClient{}
	svc := service.NewMergeService(stub)

	recipe := types.Recipe{
		ID:    "r1",
		Title: "Pasta Carbonara",
		Steps: []types.RecipeStep{
			{OrderIndex: 0, Text: "Boil water"},
			{OrderIndex: 1, Text: "Cook pasta"},
			{OrderIndex: 2, Text: "Mix sauce"},
		},
	}

	steps, err := svc.MergeRecipes(context.Background(), []types.Recipe{recipe})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if stub.called {
		t.Error("LLM should not be called for a single recipe")
	}

	if len(steps) != 3 {
		t.Fatalf("expected 3 steps, got %d", len(steps))
	}
	for i, step := range steps {
		if step.OrderIndex != i {
			t.Errorf("step %d: order_index = %d, want %d", i, step.OrderIndex, i)
		}
		if step.SourceDishTag != "Pasta Carbonara" {
			t.Errorf("step %d: source_dish_tag = %q, want %q", i, step.SourceDishTag, "Pasta Carbonara")
		}
	}
	if steps[0].Text != "Boil water" {
		t.Errorf("step 0: text = %q, want %q", steps[0].Text, "Boil water")
	}
}

func TestMergeRecipes_MultiRecipe_GoldenResponse(t *testing.T) {
	goldenResp, err := os.ReadFile(goldenPath("merge_response.json"))
	if err != nil {
		t.Fatalf("failed to read golden response: %v", err)
	}

	stub := &stubLLMClient{response: string(goldenResp)}
	svc := service.NewMergeService(stub)

	recipes := []types.Recipe{
		{
			ID:    "r1",
			Title: "Pasta Carbonara",
			Steps: []types.RecipeStep{
				{OrderIndex: 0, Text: "Boil water and cook spaghetti"},
				{OrderIndex: 1, Text: "Fry pancetta until crispy"},
				{OrderIndex: 2, Text: "Mix eggs and parmesan"},
				{OrderIndex: 3, Text: "Combine pasta with pancetta and egg mixture"},
			},
		},
		{
			ID:    "r2",
			Title: "Caesar Salad",
			Steps: []types.RecipeStep{
				{OrderIndex: 0, Text: "Wash and chop romaine lettuce"},
				{OrderIndex: 1, Text: "Make caesar dressing"},
				{OrderIndex: 2, Text: "Toss lettuce with dressing and croutons"},
			},
		},
	}

	steps, err := svc.MergeRecipes(context.Background(), recipes)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !stub.called {
		t.Error("LLM should be called for multiple recipes")
	}

	if len(steps) != 7 {
		t.Fatalf("expected 7 merged steps, got %d", len(steps))
	}

	// Verify first and last step.
	if steps[0].Text != "Boil water and cook spaghetti" {
		t.Errorf("first step text = %q", steps[0].Text)
	}
	if steps[0].SourceDishTag != "Pasta Carbonara" {
		t.Errorf("first step dish tag = %q", steps[0].SourceDishTag)
	}
	if steps[6].Text != "Combine pasta with pancetta and egg mixture" {
		t.Errorf("last step text = %q", steps[6].Text)
	}
}

func TestMergeRecipes_Empty(t *testing.T) {
	stub := &stubLLMClient{}
	svc := service.NewMergeService(stub)

	steps, err := svc.MergeRecipes(context.Background(), []types.Recipe{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(steps) != 0 {
		t.Fatalf("expected 0 steps, got %d", len(steps))
	}
}
