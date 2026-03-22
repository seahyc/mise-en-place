package worker

import (
	"context"
	"log"
	"time"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// JobRepo defines the interface the worker needs for job management.
type JobRepo interface {
	ClaimNext(ctx context.Context, jobType types.JobType) (*types.Job, error)
	Complete(ctx context.Context, id string, result map[string]any) error
	Fail(ctx context.Context, id string, errMsg string) error
}

// HandlerFunc processes a claimed job and returns an optional result or error.
type HandlerFunc func(ctx context.Context, job *types.Job) (map[string]any, error)

// Worker polls for jobs and processes them.
type Worker struct {
	repo     JobRepo
	jobType  types.JobType
	handler  HandlerFunc
	interval time.Duration
}

// NewWorker creates a new Worker.
func NewWorker(repo JobRepo, jobType types.JobType, handler HandlerFunc, interval time.Duration) *Worker {
	return &Worker{
		repo:     repo,
		jobType:  jobType,
		handler:  handler,
		interval: interval,
	}
}

// Run starts the worker loop. It blocks until the context is cancelled.
func (w *Worker) Run(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.poll(ctx)
		}
	}
}

// poll claims and processes a single job.
func (w *Worker) poll(ctx context.Context) {
	job, err := w.repo.ClaimNext(ctx, w.jobType)
	if err != nil {
		log.Printf("worker: claim error: %v", err)
		return
	}
	if job == nil {
		return // No jobs available
	}

	result, err := w.handler(ctx, job)
	if err != nil {
		log.Printf("worker: job %s failed: %v", job.ID, err)
		if failErr := w.repo.Fail(ctx, job.ID, err.Error()); failErr != nil {
			log.Printf("worker: failed to mark job %s as failed: %v", job.ID, failErr)
		}
		return
	}

	if err := w.repo.Complete(ctx, job.ID, result); err != nil {
		log.Printf("worker: failed to complete job %s: %v", job.ID, err)
	}
}

// ProcessOne claims and processes a single job. Returns true if a job was processed.
// Useful for testing.
func (w *Worker) ProcessOne(ctx context.Context) bool {
	job, err := w.repo.ClaimNext(ctx, w.jobType)
	if err != nil || job == nil {
		return false
	}

	result, err := w.handler(ctx, job)
	if err != nil {
		_ = w.repo.Fail(ctx, job.ID, err.Error())
		return true
	}

	_ = w.repo.Complete(ctx, job.ID, result)
	return true
}
