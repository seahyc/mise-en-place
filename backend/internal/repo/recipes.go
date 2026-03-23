package repo

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// StepInput holds the data for creating or updating a recipe step.
type StepInput struct {
	OrderIndex int
	Text       string
	ImageURL   string
}

// CreateRecipeArgs holds the arguments for creating a new recipe.
type CreateRecipeArgs struct {
	UserID      types.UserID
	Title       string
	Description string
	SourceURL   string
	SourceType  string
	Cuisine     string
	Ingredients []string
	Steps       []StepInput
}

// UpdateRecipeArgs holds the arguments for updating a recipe.
type UpdateRecipeArgs struct {
	Title       *string
	Description *string
	SourceURL   *string
	SourceType  *string
	Cuisine     *string
	ImageURL    *string
	Ingredients []string
	Steps       []StepInput
}

// RecipeRepo defines the interface for recipe persistence operations.
type RecipeRepo interface {
	Create(ctx context.Context, args CreateRecipeArgs) (*types.Recipe, error)
	GetByID(ctx context.Context, id types.RecipeID) (*types.Recipe, error)
	ListByUser(ctx context.Context, userID types.UserID, limit, offset int) ([]types.Recipe, int, error)
	Update(ctx context.Context, id types.RecipeID, args UpdateRecipeArgs) error
	Delete(ctx context.Context, id types.RecipeID) error
}

// PgRecipeRepo implements RecipeRepo using PostgreSQL.
type PgRecipeRepo struct {
	pool *pgxpool.Pool
}

// NewPgRecipeRepo creates a new PgRecipeRepo.
func NewPgRecipeRepo(pool *pgxpool.Pool) *PgRecipeRepo {
	return &PgRecipeRepo{pool: pool}
}

// Create inserts a new recipe with its ingredients and steps in a transaction.
func (r *PgRecipeRepo) Create(ctx context.Context, args CreateRecipeArgs) (*types.Recipe, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var recipe types.Recipe
	err = tx.QueryRow(ctx,
		`INSERT INTO recipes (user_id, title, description, source_url, source_type, cuisine)
		 VALUES ($1, $2, $3, NULLIF($4, ''), $5, NULLIF($6, ''))
		 RETURNING id, user_id, title, description, COALESCE(source_url, ''), source_type, COALESCE(cuisine, ''), COALESCE(image_url, ''), created_at, updated_at`,
		args.UserID, args.Title, args.Description, args.SourceURL, args.SourceType, args.Cuisine,
	).Scan(&recipe.ID, &recipe.UserID, &recipe.Title, &recipe.Description,
		&recipe.SourceURL, &recipe.SourceType, &recipe.Cuisine, &recipe.ImageURL,
		&recipe.CreatedAt, &recipe.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("repo: insert recipe: %w", err)
	}

	for i, ing := range args.Ingredients {
		_, err = tx.Exec(ctx,
			`INSERT INTO recipe_ingredients (recipe_id, order_index, text) VALUES ($1, $2, $3)`,
			recipe.ID, i, ing,
		)
		if err != nil {
			return nil, fmt.Errorf("repo: insert ingredient: %w", err)
		}
	}
	recipe.Ingredients = args.Ingredients

	recipe.Steps = make([]types.RecipeStep, 0, len(args.Steps))
	for _, s := range args.Steps {
		_, err = tx.Exec(ctx,
			`INSERT INTO recipe_steps (recipe_id, order_index, text, image_url) VALUES ($1, $2, $3, NULLIF($4, ''))`,
			recipe.ID, s.OrderIndex, s.Text, s.ImageURL,
		)
		if err != nil {
			return nil, fmt.Errorf("repo: insert step: %w", err)
		}
		recipe.Steps = append(recipe.Steps, types.RecipeStep{
			OrderIndex: s.OrderIndex,
			Text:       s.Text,
			ImageURL:   s.ImageURL,
		})
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("repo: commit tx: %w", err)
	}

	return &recipe, nil
}

// GetByID fetches a recipe with its ingredients and steps via separate queries.
func (r *PgRecipeRepo) GetByID(ctx context.Context, id types.RecipeID) (*types.Recipe, error) {
	// Query 1: recipe
	var recipe types.Recipe
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, title, description, COALESCE(source_url, ''), source_type, COALESCE(cuisine, ''), COALESCE(image_url, ''), created_at, updated_at
		 FROM recipes WHERE id = $1`, id,
	).Scan(&recipe.ID, &recipe.UserID, &recipe.Title, &recipe.Description,
		&recipe.SourceURL, &recipe.SourceType, &recipe.Cuisine, &recipe.ImageURL,
		&recipe.CreatedAt, &recipe.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("repo: get recipe: %w", err)
	}

	// Query 2: ingredients
	rows, err := r.pool.Query(ctx,
		`SELECT text FROM recipe_ingredients WHERE recipe_id = $1 ORDER BY order_index`, id)
	if err != nil {
		return nil, fmt.Errorf("repo: get ingredients: %w", err)
	}
	defer rows.Close()
	recipe.Ingredients = []string{}
	for rows.Next() {
		var text string
		if err := rows.Scan(&text); err != nil {
			return nil, fmt.Errorf("repo: scan ingredient: %w", err)
		}
		recipe.Ingredients = append(recipe.Ingredients, text)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("repo: ingredients rows: %w", err)
	}

	// Query 3: steps
	rows2, err := r.pool.Query(ctx,
		`SELECT order_index, text, COALESCE(image_url, '') FROM recipe_steps WHERE recipe_id = $1 ORDER BY order_index`, id)
	if err != nil {
		return nil, fmt.Errorf("repo: get steps: %w", err)
	}
	defer rows2.Close()
	recipe.Steps = []types.RecipeStep{}
	for rows2.Next() {
		var step types.RecipeStep
		if err := rows2.Scan(&step.OrderIndex, &step.Text, &step.ImageURL); err != nil {
			return nil, fmt.Errorf("repo: scan step: %w", err)
		}
		recipe.Steps = append(recipe.Steps, step)
	}
	if err := rows2.Err(); err != nil {
		return nil, fmt.Errorf("repo: steps rows: %w", err)
	}

	return &recipe, nil
}

// ListByUser lists recipes for a user without ingredients/steps and returns the total count.
func (r *PgRecipeRepo) ListByUser(ctx context.Context, userID types.UserID, limit, offset int) ([]types.Recipe, int, error) {
	var total int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM recipes WHERE user_id = $1`, userID,
	).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("repo: count recipes: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, title, description, COALESCE(source_url, ''), source_type, COALESCE(cuisine, ''), COALESCE(image_url, ''), created_at, updated_at
		 FROM recipes WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2 OFFSET $3`,
		userID, limit, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("repo: list recipes: %w", err)
	}
	defer rows.Close()

	recipes := []types.Recipe{}
	for rows.Next() {
		var recipe types.Recipe
		if err := rows.Scan(&recipe.ID, &recipe.UserID, &recipe.Title, &recipe.Description,
			&recipe.SourceURL, &recipe.SourceType, &recipe.Cuisine, &recipe.ImageURL,
			&recipe.CreatedAt, &recipe.UpdatedAt); err != nil {
			return nil, 0, fmt.Errorf("repo: scan recipe: %w", err)
		}
		recipes = append(recipes, recipe)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("repo: recipes rows: %w", err)
	}

	return recipes, total, nil
}

// Update updates recipe fields and replaces ingredients and steps in a transaction.
func (r *PgRecipeRepo) Update(ctx context.Context, id types.RecipeID, args UpdateRecipeArgs) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Build dynamic SET clause
	setClauses := []string{}
	setArgs := []any{}
	argIdx := 1

	if args.Title != nil {
		setClauses = append(setClauses, fmt.Sprintf("title = $%d", argIdx))
		setArgs = append(setArgs, *args.Title)
		argIdx++
	}
	if args.Description != nil {
		setClauses = append(setClauses, fmt.Sprintf("description = $%d", argIdx))
		setArgs = append(setArgs, *args.Description)
		argIdx++
	}
	if args.SourceURL != nil {
		setClauses = append(setClauses, fmt.Sprintf("source_url = NULLIF($%d, '')", argIdx))
		setArgs = append(setArgs, *args.SourceURL)
		argIdx++
	}
	if args.SourceType != nil {
		setClauses = append(setClauses, fmt.Sprintf("source_type = $%d", argIdx))
		setArgs = append(setArgs, *args.SourceType)
		argIdx++
	}
	if args.Cuisine != nil {
		setClauses = append(setClauses, fmt.Sprintf("cuisine = NULLIF($%d, '')", argIdx))
		setArgs = append(setArgs, *args.Cuisine)
		argIdx++
	}
	if args.ImageURL != nil {
		setClauses = append(setClauses, fmt.Sprintf("image_url = NULLIF($%d, '')", argIdx))
		setArgs = append(setArgs, *args.ImageURL)
		argIdx++
	}

	if len(setClauses) > 0 {
		setClauses = append(setClauses, fmt.Sprintf("updated_at = now()"))
		setArgs = append(setArgs, id)
		query := fmt.Sprintf("UPDATE recipes SET %s WHERE id = $%d",
			joinStrings(setClauses, ", "), argIdx)
		_, err = tx.Exec(ctx, query, setArgs...)
		if err != nil {
			return fmt.Errorf("repo: update recipe: %w", err)
		}
	} else {
		// Still touch updated_at
		_, err = tx.Exec(ctx, `UPDATE recipes SET updated_at = now() WHERE id = $1`, id)
		if err != nil {
			return fmt.Errorf("repo: update recipe timestamp: %w", err)
		}
	}

	// Replace ingredients if provided
	if args.Ingredients != nil {
		_, err = tx.Exec(ctx, `DELETE FROM recipe_ingredients WHERE recipe_id = $1`, id)
		if err != nil {
			return fmt.Errorf("repo: delete ingredients: %w", err)
		}
		for i, ing := range args.Ingredients {
			_, err = tx.Exec(ctx,
				`INSERT INTO recipe_ingredients (recipe_id, order_index, text) VALUES ($1, $2, $3)`,
				id, i, ing,
			)
			if err != nil {
				return fmt.Errorf("repo: insert ingredient: %w", err)
			}
		}
	}

	// Replace steps if provided
	if args.Steps != nil {
		_, err = tx.Exec(ctx, `DELETE FROM recipe_steps WHERE recipe_id = $1`, id)
		if err != nil {
			return fmt.Errorf("repo: delete steps: %w", err)
		}
		for _, s := range args.Steps {
			_, err = tx.Exec(ctx,
				`INSERT INTO recipe_steps (recipe_id, order_index, text, image_url) VALUES ($1, $2, $3, NULLIF($4, ''))`,
				id, s.OrderIndex, s.Text, s.ImageURL,
			)
			if err != nil {
				return fmt.Errorf("repo: insert step: %w", err)
			}
		}
	}

	return tx.Commit(ctx)
}

// Delete removes a recipe by ID. CASCADE handles ingredients and steps.
func (r *PgRecipeRepo) Delete(ctx context.Context, id types.RecipeID) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM recipes WHERE id = $1`, id)
	if err != nil {
		return fmt.Errorf("repo: delete recipe: %w", err)
	}
	return nil
}

// joinStrings joins a slice of strings with a separator.
func joinStrings(strs []string, sep string) string {
	result := ""
	for i, s := range strs {
		if i > 0 {
			result += sep
		}
		result += s
	}
	return result
}
