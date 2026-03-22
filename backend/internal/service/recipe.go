package service

import (
	"context"
	"errors"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Sentinel errors for the recipe service.
var (
	ErrEmptyTitle  = errors.New("recipe: title is required")
	ErrNotFound    = errors.New("recipe: not found")
	ErrForbidden   = errors.New("recipe: forbidden")
)

// RecipeService handles recipe business logic.
type RecipeService struct {
	recipes repo.RecipeRepo
}

// NewRecipeService creates a new RecipeService.
func NewRecipeService(recipes repo.RecipeRepo) *RecipeService {
	return &RecipeService{recipes: recipes}
}

// Create validates input and creates a new recipe.
func (s *RecipeService) Create(ctx context.Context, args repo.CreateRecipeArgs) (*types.Recipe, error) {
	if args.Title == "" {
		return nil, ErrEmptyTitle
	}
	if args.SourceType == "" {
		args.SourceType = "manual"
	}
	return s.recipes.Create(ctx, args)
}

// Get retrieves a recipe by ID.
func (s *RecipeService) Get(ctx context.Context, id types.RecipeID) (*types.Recipe, error) {
	recipe, err := s.recipes.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if recipe == nil {
		return nil, ErrNotFound
	}
	return recipe, nil
}

// List retrieves recipes for a user with pagination.
func (s *RecipeService) List(ctx context.Context, userID types.UserID, limit, offset int) ([]types.Recipe, int, error) {
	if limit <= 0 {
		limit = 20
	}
	if offset < 0 {
		offset = 0
	}
	return s.recipes.ListByUser(ctx, userID, limit, offset)
}

// Update verifies ownership and updates a recipe.
func (s *RecipeService) Update(ctx context.Context, userID types.UserID, id types.RecipeID, args repo.UpdateRecipeArgs) error {
	recipe, err := s.recipes.GetByID(ctx, id)
	if err != nil {
		return err
	}
	if recipe == nil {
		return ErrNotFound
	}
	if recipe.UserID != userID {
		return ErrForbidden
	}
	return s.recipes.Update(ctx, id, args)
}

// Delete verifies ownership and deletes a recipe.
func (s *RecipeService) Delete(ctx context.Context, userID types.UserID, id types.RecipeID) error {
	recipe, err := s.recipes.GetByID(ctx, id)
	if err != nil {
		return err
	}
	if recipe == nil {
		return ErrNotFound
	}
	if recipe.UserID != userID {
		return ErrForbidden
	}
	return s.recipes.Delete(ctx, id)
}
