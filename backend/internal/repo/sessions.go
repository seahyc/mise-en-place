package repo

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// SessionStepInput holds the arguments for inserting a session step.
type SessionStepInput struct {
	OrderIndex    int
	Text          string
	SourceDishTag string
}

// SessionRepo defines the interface for cooking session persistence.
type SessionRepo interface {
	Create(ctx context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error)
	GetByID(ctx context.Context, id types.SessionID) (*types.CookingSession, error)
	UpdateStatus(ctx context.Context, id types.SessionID, status types.SessionStatus) error
	AddSteps(ctx context.Context, sessionID types.SessionID, steps []SessionStepInput) error
	UpdateStep(ctx context.Context, stepID string, isCompleted bool, agentNotes string) error
	ListByUser(ctx context.Context, userID types.UserID) ([]types.CookingSession, error)
}

// PgSessionRepo implements SessionRepo using PostgreSQL.
type PgSessionRepo struct {
	pool *pgxpool.Pool
}

// NewPgSessionRepo creates a new PgSessionRepo.
func NewPgSessionRepo(pool *pgxpool.Pool) *PgSessionRepo {
	return &PgSessionRepo{pool: pool}
}

// Create inserts a cooking session and its session_recipes rows, returning the
// session with empty steps.
func (r *PgSessionRepo) Create(ctx context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var s types.CookingSession
	err = tx.QueryRow(ctx,
		`INSERT INTO cooking_sessions (user_id) VALUES ($1)
		 RETURNING id, user_id, status, created_at, started_at, completed_at`,
		userID,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt, &s.StartedAt, &s.CompletedAt)
	if err != nil {
		return nil, err
	}

	for _, rid := range recipeIDs {
		_, err = tx.Exec(ctx,
			`INSERT INTO session_recipes (session_id, recipe_id) VALUES ($1, $2)`,
			s.ID, rid,
		)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	s.RecipeIDs = recipeIDs
	s.Steps = []types.SessionStep{}
	return &s, nil
}

// GetByID retrieves a session by ID including its recipe IDs and steps.
func (r *PgSessionRepo) GetByID(ctx context.Context, id types.SessionID) (*types.CookingSession, error) {
	// 1. Session row.
	var s types.CookingSession
	err := r.pool.QueryRow(ctx,
		`SELECT id, user_id, status, created_at, started_at, completed_at
		 FROM cooking_sessions WHERE id = $1`, id,
	).Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt, &s.StartedAt, &s.CompletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	// 2. Recipe IDs.
	rows, err := r.pool.Query(ctx,
		`SELECT recipe_id FROM session_recipes WHERE session_id = $1`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var rid types.RecipeID
		if err := rows.Scan(&rid); err != nil {
			return nil, err
		}
		s.RecipeIDs = append(s.RecipeIDs, rid)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if s.RecipeIDs == nil {
		s.RecipeIDs = []types.RecipeID{}
	}

	// 3. Steps.
	stepRows, err := r.pool.Query(ctx,
		`SELECT id, order_index, text, COALESCE(source_dish_tag, ''), is_completed, completed_at, COALESCE(agent_notes, '')
		 FROM session_steps WHERE session_id = $1 ORDER BY order_index`, id)
	if err != nil {
		return nil, err
	}
	defer stepRows.Close()
	for stepRows.Next() {
		var st types.SessionStep
		if err := stepRows.Scan(&st.ID, &st.OrderIndex, &st.Text, &st.SourceDishTag, &st.IsCompleted, &st.CompletedAt, &st.AgentNotes); err != nil {
			return nil, err
		}
		s.Steps = append(s.Steps, st)
	}
	if err := stepRows.Err(); err != nil {
		return nil, err
	}
	if s.Steps == nil {
		s.Steps = []types.SessionStep{}
	}

	return &s, nil
}

// UpdateStatus sets the status of a session. It also sets started_at or
// completed_at timestamps when appropriate.
func (r *PgSessionRepo) UpdateStatus(ctx context.Context, id types.SessionID, status types.SessionStatus) error {
	var query string
	switch status {
	case types.SessionInProgress:
		query = `UPDATE cooking_sessions SET status = $2, started_at = COALESCE(started_at, now()) WHERE id = $1`
	case types.SessionCompleted:
		query = `UPDATE cooking_sessions SET status = $2, completed_at = now() WHERE id = $1`
	default:
		query = `UPDATE cooking_sessions SET status = $2 WHERE id = $1`
	}
	_, err := r.pool.Exec(ctx, query, id, status)
	return err
}

// AddSteps bulk-inserts session steps.
func (r *PgSessionRepo) AddSteps(ctx context.Context, sessionID types.SessionID, steps []SessionStepInput) error {
	if len(steps) == 0 {
		return nil
	}
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	for _, step := range steps {
		_, err := tx.Exec(ctx,
			`INSERT INTO session_steps (session_id, order_index, text, source_dish_tag)
			 VALUES ($1, $2, $3, NULLIF($4, ''))`,
			sessionID, step.OrderIndex, step.Text, step.SourceDishTag,
		)
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

// UpdateStep updates a session step's completion status and agent notes.
func (r *PgSessionRepo) UpdateStep(ctx context.Context, stepID string, isCompleted bool, agentNotes string) error {
	var query string
	if isCompleted {
		query = `UPDATE session_steps SET is_completed = $2, completed_at = now(), agent_notes = NULLIF($3, '') WHERE id = $1`
	} else {
		query = `UPDATE session_steps SET is_completed = $2, completed_at = NULL, agent_notes = NULLIF($3, '') WHERE id = $1`
	}
	_, err := r.pool.Exec(ctx, query, stepID, isCompleted, agentNotes)
	return err
}

// ListByUser returns all sessions for a user without steps.
func (r *PgSessionRepo) ListByUser(ctx context.Context, userID types.UserID) ([]types.CookingSession, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, user_id, status, created_at, started_at, completed_at
		 FROM cooking_sessions WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []types.CookingSession
	for rows.Next() {
		var s types.CookingSession
		if err := rows.Scan(&s.ID, &s.UserID, &s.Status, &s.CreatedAt, &s.StartedAt, &s.CompletedAt); err != nil {
			return nil, err
		}
		s.RecipeIDs = []types.RecipeID{}
		s.Steps = []types.SessionStep{}
		sessions = append(sessions, s)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if sessions == nil {
		sessions = []types.CookingSession{}
	}
	return sessions, nil
}
