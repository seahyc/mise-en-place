package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// MergedStep is a single step in a merged cooking session.
type MergedStep struct {
	OrderIndex    int    `json:"order_index"`
	Text          string `json:"text"`
	SourceDishTag string `json:"source_dish_tag"`
}

// MergeService merges one or more recipes into an optimised sequence of steps.
type MergeService struct {
	llmClient llm.Client
}

// NewMergeService creates a MergeService with the given LLM client.
func NewMergeService(client llm.Client) *MergeService {
	return &MergeService{llmClient: client}
}

const mergeSystemPrompt = "You are a professional chef. Merge these recipes into one optimised cooking session. Identify shared prep, parallel steps, optimal ordering. Output a JSON array of objects with order_index, text, source_dish_tag."

// MergeRecipes takes one or more recipes and returns a merged list of steps.
// For a single recipe the steps pass through directly with the recipe title as
// the dish tag. For multiple recipes the LLM is called.
func (s *MergeService) MergeRecipes(ctx context.Context, recipes []types.Recipe) ([]MergedStep, error) {
	if len(recipes) == 0 {
		return []MergedStep{}, nil
	}

	// Single recipe — pass through without calling the LLM.
	if len(recipes) == 1 {
		r := recipes[0]
		steps := make([]MergedStep, len(r.Steps))
		for i, st := range r.Steps {
			steps[i] = MergedStep{
				OrderIndex:    i,
				Text:          st.Text,
				SourceDishTag: r.Title,
			}
		}
		return steps, nil
	}

	// Multi-recipe — ask the LLM to merge.
	var userContent strings.Builder
	for _, r := range recipes {
		fmt.Fprintf(&userContent, "## %s\n", r.Title)
		for i, st := range r.Steps {
			fmt.Fprintf(&userContent, "%d. %s\n", i+1, st.Text)
		}
		userContent.WriteString("\n")
	}

	messages := []llm.Message{
		{Role: "system", Content: mergeSystemPrompt},
		{Role: "user", Content: userContent.String()},
	}

	resp, err := s.llmClient.Chat(ctx, messages)
	if err != nil {
		return nil, fmt.Errorf("merge: llm chat: %w", err)
	}

	// Parse the JSON array from the response.
	content := strings.TrimSpace(resp.Content)
	// Strip markdown code fences if present.
	if strings.HasPrefix(content, "```") {
		lines := strings.SplitN(content, "\n", 2)
		if len(lines) == 2 {
			content = lines[1]
		}
		if idx := strings.LastIndex(content, "```"); idx >= 0 {
			content = content[:idx]
		}
		content = strings.TrimSpace(content)
	}

	var steps []MergedStep
	if err := json.Unmarshal([]byte(content), &steps); err != nil {
		return nil, fmt.Errorf("merge: parse response: %w", err)
	}

	return steps, nil
}
