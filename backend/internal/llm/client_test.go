package llm_test

import (
	"os"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
)

// TestKimiClientInterface verifies KimiClient satisfies Client at compile time.
func TestKimiClientInterface(t *testing.T) {
	var _ llm.Client = (*llm.KimiClient)(nil)
}

// TestGLMClientInterface verifies GLMClient satisfies Client at compile time.
func TestGLMClientInterface(t *testing.T) {
	var _ llm.Client = (*llm.GLMClient)(nil)
}

// TestParseOpenAIResponse_GoldenFile tests parsing a golden OpenAI-compatible response.
func TestParseOpenAIResponse_GoldenFile(t *testing.T) {
	data, err := os.ReadFile("../../test/golden/llm_response.json")
	if err != nil {
		t.Fatalf("read golden file: %v", err)
	}

	resp, err := llm.ParseOpenAIResponse(data)
	if err != nil {
		t.Fatalf("parse response: %v", err)
	}

	if resp.Content != "Here is the recipe." {
		t.Errorf("Content = %q, want %q", resp.Content, "Here is the recipe.")
	}

	if len(resp.ToolCalls) != 1 {
		t.Fatalf("ToolCalls count = %d, want 1", len(resp.ToolCalls))
	}

	tc := resp.ToolCalls[0]
	if tc.Name != "save_recipe" {
		t.Errorf("ToolCall.Name = %q, want %q", tc.Name, "save_recipe")
	}
	if tc.Args["title"] != "Pasta Carbonara" {
		t.Errorf("ToolCall.Args[title] = %v, want %q", tc.Args["title"], "Pasta Carbonara")
	}
	if tc.Args["servings"].(float64) != 4 {
		t.Errorf("ToolCall.Args[servings] = %v, want 4", tc.Args["servings"])
	}
}

// TestParseOpenAIResponse_NoChoices tests parsing a response with no choices.
func TestParseOpenAIResponse_NoChoices(t *testing.T) {
	data := []byte(`{"choices":[]}`)
	resp, err := llm.ParseOpenAIResponse(data)
	if err != nil {
		t.Fatalf("parse response: %v", err)
	}
	if resp.Content != "" {
		t.Errorf("Content = %q, want empty", resp.Content)
	}
	if len(resp.ToolCalls) != 0 {
		t.Errorf("ToolCalls count = %d, want 0", len(resp.ToolCalls))
	}
}
