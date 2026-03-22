package service

import (
	"context"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// stubRecipeRepo is a minimal in-memory implementation for testing.
type stubRecipeRepo struct {
	recipes map[types.RecipeID]*types.Recipe
	nextID  int
}

func newStubRecipeRepo() *stubRecipeRepo {
	return &stubRecipeRepo{
		recipes: make(map[types.RecipeID]*types.Recipe),
	}
}

func (s *stubRecipeRepo) Create(_ context.Context, args repo.CreateRecipeArgs) (*types.Recipe, error) {
	s.nextID++
	id := types.RecipeID("recipe-" + string(rune('0'+s.nextID)))
	r := &types.Recipe{
		ID:          id,
		UserID:      args.UserID,
		Title:       args.Title,
		Description: args.Description,
		SourceURL:   args.SourceURL,
		SourceType:  args.SourceType,
		Cuisine:     args.Cuisine,
		Ingredients: args.Ingredients,
	}
	for _, step := range args.Steps {
		r.Steps = append(r.Steps, types.RecipeStep{OrderIndex: step.OrderIndex, Text: step.Text})
	}
	s.recipes[id] = r
	return r, nil
}

func (s *stubRecipeRepo) GetByID(_ context.Context, id types.RecipeID) (*types.Recipe, error) {
	r, ok := s.recipes[id]
	if !ok {
		return nil, nil
	}
	return r, nil
}

func (s *stubRecipeRepo) ListByUser(_ context.Context, userID types.UserID, limit, offset int) ([]types.Recipe, int, error) {
	var result []types.Recipe
	for _, r := range s.recipes {
		if r.UserID == userID {
			result = append(result, *r)
		}
	}
	total := len(result)
	if offset > len(result) {
		return []types.Recipe{}, total, nil
	}
	result = result[offset:]
	if limit < len(result) {
		result = result[:limit]
	}
	return result, total, nil
}

func (s *stubRecipeRepo) Update(_ context.Context, id types.RecipeID, args repo.UpdateRecipeArgs) error {
	r, ok := s.recipes[id]
	if !ok {
		return nil
	}
	if args.Title != nil {
		r.Title = *args.Title
	}
	if args.Description != nil {
		r.Description = *args.Description
	}
	return nil
}

func (s *stubRecipeRepo) Delete(_ context.Context, id types.RecipeID) error {
	delete(s.recipes, id)
	return nil
}

func TestRecipeService_CreateEmptyTitle(t *testing.T) {
	svc := NewRecipeService(newStubRecipeRepo())
	_, err := svc.Create(context.Background(), repo.CreateRecipeArgs{
		UserID: "user-1",
		Title:  "",
	})
	if err != ErrEmptyTitle {
		t.Fatalf("expected ErrEmptyTitle, got %v", err)
	}
}

func TestRecipeService_CreateSuccess(t *testing.T) {
	svc := NewRecipeService(newStubRecipeRepo())
	recipe, err := svc.Create(context.Background(), repo.CreateRecipeArgs{
		UserID: "user-1",
		Title:  "Pasta",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if recipe.Title != "Pasta" {
		t.Fatalf("expected title Pasta, got %q", recipe.Title)
	}
}

func TestRecipeService_GetNotFound(t *testing.T) {
	svc := NewRecipeService(newStubRecipeRepo())
	_, err := svc.Get(context.Background(), "nonexistent")
	if err != ErrNotFound {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestRecipeService_UpdateOwnership(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := NewRecipeService(stub)

	recipe, _ := svc.Create(context.Background(), repo.CreateRecipeArgs{
		UserID: "user-1",
		Title:  "Pasta",
	})

	title := "Updated"
	err := svc.Update(context.Background(), "user-2", recipe.ID, repo.UpdateRecipeArgs{Title: &title})
	if err != ErrForbidden {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}

	err = svc.Update(context.Background(), "user-1", recipe.ID, repo.UpdateRecipeArgs{Title: &title})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRecipeService_DeleteOwnership(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := NewRecipeService(stub)

	recipe, _ := svc.Create(context.Background(), repo.CreateRecipeArgs{
		UserID: "user-1",
		Title:  "Pasta",
	})

	err := svc.Delete(context.Background(), "user-2", recipe.ID)
	if err != ErrForbidden {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}

	err = svc.Delete(context.Background(), "user-1", recipe.ID)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRecipeService_ListDefaults(t *testing.T) {
	stub := newStubRecipeRepo()
	svc := NewRecipeService(stub)

	svc.Create(context.Background(), repo.CreateRecipeArgs{UserID: "user-1", Title: "A"})
	svc.Create(context.Background(), repo.CreateRecipeArgs{UserID: "user-1", Title: "B"})

	recipes, total, err := svc.List(context.Background(), "user-1", 0, -1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if total != 2 {
		t.Fatalf("expected total 2, got %d", total)
	}
	if len(recipes) != 2 {
		t.Fatalf("expected 2 recipes, got %d", len(recipes))
	}
}
