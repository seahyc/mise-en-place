package repo

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// JobRepo defines the interface for job persistence operations.
type JobRepo interface {
	Create(ctx context.Context, jobType types.JobType, userID types.UserID, payload map[string]any) (string, error)
	GetByID(ctx context.Context, id string) (*types.Job, error)
	ClaimNext(ctx context.Context, jobType types.JobType) (*types.Job, error)
	Complete(ctx context.Context, id string, result map[string]any) error
	Fail(ctx context.Context, id string, errMsg string) error
}

// PgJobRepo implements JobRepo using PostgreSQL.
type PgJobRepo struct {
	pool *pgxpool.Pool
}

// NewPgJobRepo creates a new PgJobRepo.
func NewPgJobRepo(pool *pgxpool.Pool) *PgJobRepo {
	return &PgJobRepo{pool: pool}
}

// Create inserts a new job and returns its ID.
func (r *PgJobRepo) Create(ctx context.Context, jobType types.JobType, userID types.UserID, payload map[string]any) (string, error) {
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("repo: marshal payload: %w", err)
	}

	var id string
	err = r.pool.QueryRow(ctx,
		`INSERT INTO jobs (type, user_id, payload) VALUES ($1, $2, $3) RETURNING id`,
		string(jobType), userID, payloadJSON,
	).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("repo: create job: %w", err)
	}
	return id, nil
}

// GetByID retrieves a job by its ID.
func (r *PgJobRepo) GetByID(ctx context.Context, id string) (*types.Job, error) {
	var job types.Job
	var payloadJSON, resultJSON []byte
	err := r.pool.QueryRow(ctx,
		`SELECT id, type, status, payload, result, user_id, created_at, updated_at
		 FROM jobs WHERE id = $1`, id,
	).Scan(&job.ID, &job.Type, &job.Status, &payloadJSON, &resultJSON, &job.UserID, &job.CreatedAt, &job.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("repo: get job: %w", err)
	}

	if payloadJSON != nil {
		_ = json.Unmarshal(payloadJSON, &job.Payload)
	}
	if resultJSON != nil {
		_ = json.Unmarshal(resultJSON, &job.Result)
	}

	return &job, nil
}

// ClaimNext atomically claims the next pending job of the given type using FOR UPDATE SKIP LOCKED.
func (r *PgJobRepo) ClaimNext(ctx context.Context, jobType types.JobType) (*types.Job, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	var job types.Job
	var payloadJSON []byte
	err = tx.QueryRow(ctx,
		`SELECT id, type, status, payload, user_id, created_at, updated_at
		 FROM jobs
		 WHERE type = $1 AND status = $2
		 ORDER BY created_at ASC
		 LIMIT 1
		 FOR UPDATE SKIP LOCKED`,
		string(jobType), string(types.JobPending),
	).Scan(&job.ID, &job.Type, &job.Status, &payloadJSON, &job.UserID, &job.CreatedAt, &job.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("repo: claim job: %w", err)
	}

	if payloadJSON != nil {
		_ = json.Unmarshal(payloadJSON, &job.Payload)
	}

	_, err = tx.Exec(ctx,
		`UPDATE jobs SET status = $1, updated_at = now() WHERE id = $2`,
		string(types.JobRunning), job.ID,
	)
	if err != nil {
		return nil, fmt.Errorf("repo: update job status: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("repo: commit tx: %w", err)
	}

	job.Status = types.JobRunning
	return &job, nil
}

// Complete marks a job as done with a result.
func (r *PgJobRepo) Complete(ctx context.Context, id string, result map[string]any) error {
	resultJSON, err := json.Marshal(result)
	if err != nil {
		return fmt.Errorf("repo: marshal result: %w", err)
	}
	_, err = r.pool.Exec(ctx,
		`UPDATE jobs SET status = $1, result = $2, updated_at = now() WHERE id = $3`,
		string(types.JobDone), resultJSON, id,
	)
	if err != nil {
		return fmt.Errorf("repo: complete job: %w", err)
	}
	return nil
}

// Fail marks a job as failed with an error message.
func (r *PgJobRepo) Fail(ctx context.Context, id string, errMsg string) error {
	resultJSON, _ := json.Marshal(map[string]string{"error": errMsg})
	_, err := r.pool.Exec(ctx,
		`UPDATE jobs SET status = $1, result = $2, updated_at = now() WHERE id = $3`,
		string(types.JobFailed), resultJSON, id,
	)
	if err != nil {
		return fmt.Errorf("repo: fail job: %w", err)
	}
	return nil
}
