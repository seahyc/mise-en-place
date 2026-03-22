package worker_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/yingcong/mise-en-place/backend/internal/types"
	"github.com/yingcong/mise-en-place/backend/internal/worker"
)

// stubJobRepo is a minimal in-memory job repo for testing the worker.
type stubJobRepo struct {
	jobs []*types.Job
}

func (s *stubJobRepo) ClaimNext(_ context.Context, jobType types.JobType) (*types.Job, error) {
	for _, j := range s.jobs {
		if j.Type == jobType && j.Status == types.JobPending {
			j.Status = types.JobRunning
			return j, nil
		}
	}
	return nil, nil
}

func (s *stubJobRepo) Complete(_ context.Context, id string, result map[string]any) error {
	for _, j := range s.jobs {
		if j.ID == id {
			j.Status = types.JobDone
			j.Result = result
			return nil
		}
	}
	return nil
}

func (s *stubJobRepo) Fail(_ context.Context, id string, errMsg string) error {
	for _, j := range s.jobs {
		if j.ID == id {
			j.Status = types.JobFailed
			return nil
		}
	}
	return nil
}

func TestWorker_ProcessOneSuccess(t *testing.T) {
	repo := &stubJobRepo{
		jobs: []*types.Job{
			{ID: "j1", Type: types.JobIngestVideo, Status: types.JobPending, UserID: "u1"},
		},
	}

	handler := func(_ context.Context, job *types.Job) (map[string]any, error) {
		return map[string]any{"recipe_id": "r1"}, nil
	}

	w := worker.NewWorker(repo, types.JobIngestVideo, handler, time.Second)
	ok := w.ProcessOne(context.Background())
	if !ok {
		t.Fatal("expected ProcessOne to return true")
	}
	if repo.jobs[0].Status != types.JobDone {
		t.Fatalf("expected job status done, got %s", repo.jobs[0].Status)
	}
}

func TestWorker_ProcessOneFailure(t *testing.T) {
	repo := &stubJobRepo{
		jobs: []*types.Job{
			{ID: "j1", Type: types.JobIngestVideo, Status: types.JobPending, UserID: "u1"},
		},
	}

	handler := func(_ context.Context, job *types.Job) (map[string]any, error) {
		return nil, errors.New("something broke")
	}

	w := worker.NewWorker(repo, types.JobIngestVideo, handler, time.Second)
	ok := w.ProcessOne(context.Background())
	if !ok {
		t.Fatal("expected ProcessOne to return true")
	}
	if repo.jobs[0].Status != types.JobFailed {
		t.Fatalf("expected job status failed, got %s", repo.jobs[0].Status)
	}
}

func TestWorker_ProcessOneNoJobs(t *testing.T) {
	repo := &stubJobRepo{jobs: []*types.Job{}}

	handler := func(_ context.Context, job *types.Job) (map[string]any, error) {
		return nil, nil
	}

	w := worker.NewWorker(repo, types.JobIngestVideo, handler, time.Second)
	ok := w.ProcessOne(context.Background())
	if ok {
		t.Fatal("expected ProcessOne to return false when no jobs")
	}
}

func TestWorkerInterface(t *testing.T) {
	var _ worker.JobRepo = (*stubJobRepo)(nil)
}
