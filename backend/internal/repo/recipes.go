package repo

import (
	"context"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// RecipeRepo defines the interface for recipe persistence operations.
type RecipeRepo interface {
	GetByID(ctx context.Context, id types.RecipeID) (*types.Recipe, error)
	// Other methods omitted — only GetByID needed by SessionService.
}
