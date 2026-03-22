package repo_test

import (
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
)

// TestRecipeRepoInterface verifies PgRecipeRepo satisfies RecipeRepo at compile time.
func TestRecipeRepoInterface(t *testing.T) {
	var _ repo.RecipeRepo = (*repo.PgRecipeRepo)(nil)
}

// TestCreateRecipeArgsFields verifies the CreateRecipeArgs struct has the expected fields.
func TestCreateRecipeArgsFields(t *testing.T) {
	args := repo.CreateRecipeArgs{
		UserID:      "user-1",
		Title:       "Test Recipe",
		Description: "A test recipe",
		SourceURL:   "https://example.com",
		SourceType:  "manual",
		Cuisine:     "Italian",
		Ingredients: []string{"flour", "water"},
		Steps: []repo.StepInput{
			{OrderIndex: 0, Text: "Mix ingredients"},
			{OrderIndex: 1, Text: "Bake at 350F"},
		},
	}

	if args.Title != "Test Recipe" {
		t.Errorf("Title = %q, want %q", args.Title, "Test Recipe")
	}
	if len(args.Ingredients) != 2 {
		t.Errorf("Ingredients count = %d, want 2", len(args.Ingredients))
	}
	if len(args.Steps) != 2 {
		t.Errorf("Steps count = %d, want 2", len(args.Steps))
	}
}

// TestUpdateRecipeArgsFields verifies the UpdateRecipeArgs struct has the expected fields.
func TestUpdateRecipeArgsFields(t *testing.T) {
	title := "Updated Title"
	args := repo.UpdateRecipeArgs{
		Title:       &title,
		Ingredients: []string{"new ingredient"},
		Steps:       []repo.StepInput{{OrderIndex: 0, Text: "New step"}},
	}

	if *args.Title != "Updated Title" {
		t.Errorf("Title = %q, want %q", *args.Title, "Updated Title")
	}
	if len(args.Ingredients) != 1 {
		t.Errorf("Ingredients count = %d, want 1", len(args.Ingredients))
	}
}
