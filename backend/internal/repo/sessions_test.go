package repo_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
)

// TestSessionRepoInterface verifies PgSessionRepo satisfies SessionRepo at compile time.
func TestSessionRepoInterface(t *testing.T) {
	var _ repo.SessionRepo = (*repo.PgSessionRepo)(nil)
}

// TestSessionStepInputFields verifies the SessionStepInput struct has the expected fields.
func TestSessionStepInputFields(t *testing.T) {
	input := repo.SessionStepInput{
		OrderIndex:    1,
		Text:          "Preheat oven to 350F",
		SourceDishTag: "Lasagna",
	}

	if input.OrderIndex != 1 {
		t.Errorf("OrderIndex = %d, want 1", input.OrderIndex)
	}
	if input.Text != "Preheat oven to 350F" {
		t.Errorf("Text = %q, want %q", input.Text, "Preheat oven to 350F")
	}
	if input.SourceDishTag != "Lasagna" {
		t.Errorf("SourceDishTag = %q, want %q", input.SourceDishTag, "Lasagna")
	}
}
