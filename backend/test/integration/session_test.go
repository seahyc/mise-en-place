package integration

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/llm"
	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// stubLLM returns a canned merge response.
type stubLLM struct {
	response string
}

func (s *stubLLM) Chat(_ context.Context, _ []llm.Message) (*llm.Response, error) {
	return &llm.Response{Content: s.response}, nil
}
func (s *stubLLM) ChatWithTools(_ context.Context, _ []llm.Message, _ []llm.ToolDef) (*llm.Response, error) {
	return &llm.Response{Content: s.response}, nil
}

// sqlRecipeRepo is a minimal RecipeRepo backed by pgxpool for integration tests.
type sqlRecipeRepo struct {
	pool *pgxpool.Pool
}

func (r *sqlRecipeRepo) GetByID(ctx context.Context, id types.RecipeID) (*types.Recipe, error) {
	var recipe types.Recipe
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, title, description, COALESCE(source_url, ''), source_type,
		        COALESCE(cuisine, ''), COALESCE(image_url, ''), created_at, updated_at
		 FROM recipes WHERE id = $1`, id,
	).Scan(&recipe.ID, &recipe.UserID, &recipe.Title, &recipe.Description,
		&recipe.SourceURL, &recipe.SourceType, &recipe.Cuisine, &recipe.ImageURL,
		&recipe.CreatedAt, &recipe.UpdatedAt)
	if err == pgx.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	rows, err := r.pool.Query(ctx,
		`SELECT order_index, text, COALESCE(image_url, '')
		 FROM recipe_steps WHERE recipe_id = $1 ORDER BY order_index`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var st types.RecipeStep
		if err := rows.Scan(&st.OrderIndex, &st.Text, &st.ImageURL); err != nil {
			return nil, err
		}
		recipe.Steps = append(recipe.Steps, st)
	}
	if recipe.Steps == nil {
		recipe.Steps = []types.RecipeStep{}
	}

	return &recipe, rows.Err()
}

func TestSessionLifecycle_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration test")
	}

	pool, cleanup := SetupTestDB(t)
	defer cleanup()

	ctx := context.Background()

	// 1. Create a user.
	userRepo := repo.NewPgUserRepo(pool)
	user, err := userRepo.Create(ctx, repo.CreateUserArgs{
		Email:        "session-chef@example.com",
		DisplayName:  "Session Chef",
		PasswordHash: "hash",
	})
	if err != nil {
		t.Fatalf("create user: %v", err)
	}

	// 2. Insert 2 recipes directly via SQL.
	var recipeID1, recipeID2 types.RecipeID
	err = pool.QueryRow(ctx,
		`INSERT INTO recipes (user_id, title, source_type) VALUES ($1, 'Pasta Carbonara', 'manual') RETURNING id`,
		user.ID,
	).Scan(&recipeID1)
	if err != nil {
		t.Fatalf("insert recipe 1: %v", err)
	}
	_, err = pool.Exec(ctx,
		`INSERT INTO recipe_steps (recipe_id, order_index, text) VALUES ($1, 0, 'Boil water'), ($1, 1, 'Cook pasta'), ($1, 2, 'Mix sauce')`,
		recipeID1,
	)
	if err != nil {
		t.Fatalf("insert recipe 1 steps: %v", err)
	}

	err = pool.QueryRow(ctx,
		`INSERT INTO recipes (user_id, title, source_type) VALUES ($1, 'Caesar Salad', 'manual') RETURNING id`,
		user.ID,
	).Scan(&recipeID2)
	if err != nil {
		t.Fatalf("insert recipe 2: %v", err)
	}
	_, err = pool.Exec(ctx,
		`INSERT INTO recipe_steps (recipe_id, order_index, text) VALUES ($1, 0, 'Chop lettuce'), ($1, 1, 'Make dressing')`,
		recipeID2,
	)
	if err != nil {
		t.Fatalf("insert recipe 2 steps: %v", err)
	}

	// 3. Set up services.
	recipeRepo := &sqlRecipeRepo{pool: pool}
	sessRepo := repo.NewPgSessionRepo(pool)

	mergeResponse := `[
		{"order_index":0,"text":"Boil water","source_dish_tag":"Pasta Carbonara"},
		{"order_index":1,"text":"Chop lettuce","source_dish_tag":"Caesar Salad"},
		{"order_index":2,"text":"Cook pasta","source_dish_tag":"Pasta Carbonara"},
		{"order_index":3,"text":"Make dressing","source_dish_tag":"Caesar Salad"},
		{"order_index":4,"text":"Mix sauce","source_dish_tag":"Pasta Carbonara"}
	]`
	mergeSvc := service.NewMergeService(&stubLLM{response: mergeResponse})
	sessSvc := service.NewSessionService(sessRepo, recipeRepo, mergeSvc)

	// 4. Create session with both recipes.
	sess, err := sessSvc.Create(ctx, user.ID, []types.RecipeID{recipeID1, recipeID2})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	// 5. Assert session has merged steps with dish tags.
	if len(sess.Steps) != 5 {
		t.Fatalf("expected 5 merged steps, got %d", len(sess.Steps))
	}
	if sess.Steps[0].SourceDishTag != "Pasta Carbonara" {
		t.Errorf("step 0 dish tag = %q, want %q", sess.Steps[0].SourceDishTag, "Pasta Carbonara")
	}
	if sess.Steps[1].SourceDishTag != "Caesar Salad" {
		t.Errorf("step 1 dish tag = %q, want %q", sess.Steps[1].SourceDishTag, "Caesar Salad")
	}

	// 6. Start session.
	if err := sessSvc.Start(ctx, sess.ID); err != nil {
		t.Fatalf("start session: %v", err)
	}
	state, err := sessSvc.GetState(ctx, sess.ID)
	if err != nil {
		t.Fatalf("get state after start: %v", err)
	}
	if state.Status != types.SessionInProgress {
		t.Errorf("expected status %q, got %q", types.SessionInProgress, state.Status)
	}

	// 7. Complete each step.
	for i, step := range sess.Steps {
		if err := sessSvc.CompleteStep(ctx, sess.ID, step.ID); err != nil {
			t.Fatalf("complete step %d: %v", i, err)
		}
	}

	// 8. Verify session auto-completed.
	state, err = sessSvc.GetState(ctx, sess.ID)
	if err != nil {
		t.Fatalf("get state after complete: %v", err)
	}
	if state.Status != types.SessionCompleted {
		t.Errorf("expected status %q, got %q", types.SessionCompleted, state.Status)
	}
	if state.CompletedAt == nil {
		t.Error("expected completed_at to be set")
	}
}
