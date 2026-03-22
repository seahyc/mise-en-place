package service_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/service"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// --- Stub RecipeRepo ---

type stubRecipeRepo struct {
	recipes map[types.RecipeID]*types.Recipe
}

func (s *stubRecipeRepo) GetByID(_ context.Context, id types.RecipeID) (*types.Recipe, error) {
	r, ok := s.recipes[id]
	if !ok {
		return nil, nil
	}
	return r, nil
}

// --- Stub SessionRepo ---

type stubSessionRepo struct {
	sessions map[types.SessionID]*types.CookingSession
	nextID   int
}

func newStubSessionRepo() *stubSessionRepo {
	return &stubSessionRepo{sessions: make(map[types.SessionID]*types.CookingSession)}
}

func (s *stubSessionRepo) Create(_ context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error) {
	s.nextID++
	id := types.SessionID(fmt.Sprintf("sess-%d", s.nextID))
	sess := &types.CookingSession{
		ID:        id,
		UserID:    userID,
		Status:    types.SessionSetup,
		RecipeIDs: recipeIDs,
		Steps:     []types.SessionStep{},
	}
	s.sessions[id] = sess
	return sess, nil
}

func (s *stubSessionRepo) GetByID(_ context.Context, id types.SessionID) (*types.CookingSession, error) {
	sess, ok := s.sessions[id]
	if !ok {
		return nil, nil
	}
	return sess, nil
}

func (s *stubSessionRepo) UpdateStatus(_ context.Context, id types.SessionID, status types.SessionStatus) error {
	sess := s.sessions[id]
	if sess != nil {
		sess.Status = status
	}
	return nil
}

func (s *stubSessionRepo) AddSteps(_ context.Context, sessionID types.SessionID, steps []repo.SessionStepInput) error {
	sess := s.sessions[sessionID]
	if sess == nil {
		return nil
	}
	for i, st := range steps {
		sess.Steps = append(sess.Steps, types.SessionStep{
			ID:            fmt.Sprintf("step-%d-%d", s.nextID, i),
			OrderIndex:    st.OrderIndex,
			Text:          st.Text,
			SourceDishTag: st.SourceDishTag,
		})
	}
	return nil
}

func (s *stubSessionRepo) UpdateStep(_ context.Context, stepID string, isCompleted bool, agentNotes string) error {
	for _, sess := range s.sessions {
		for i, st := range sess.Steps {
			if st.ID == stepID {
				sess.Steps[i].IsCompleted = isCompleted
				sess.Steps[i].AgentNotes = agentNotes
				return nil
			}
		}
	}
	return nil
}

func (s *stubSessionRepo) ListByUser(_ context.Context, userID types.UserID) ([]types.CookingSession, error) {
	var result []types.CookingSession
	for _, sess := range s.sessions {
		if sess.UserID == userID {
			result = append(result, *sess)
		}
	}
	return result, nil
}

// --- Tests ---

func TestSessionService_CreateSingleRecipe_NoMerge(t *testing.T) {
	recipeRepo := &stubRecipeRepo{
		recipes: map[types.RecipeID]*types.Recipe{
			"r1": {
				ID:    "r1",
				Title: "Pasta",
				Steps: []types.RecipeStep{
					{OrderIndex: 0, Text: "Boil water"},
					{OrderIndex: 1, Text: "Cook pasta"},
				},
			},
		},
	}
	sessRepo := newStubSessionRepo()
	stub := &stubLLMClient{}
	mergeSvc := service.NewMergeService(stub)
	svc := service.NewSessionService(sessRepo, recipeRepo, mergeSvc)

	sess, err := svc.Create(context.Background(), "user1", []types.RecipeID{"r1"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if stub.called {
		t.Error("LLM should not be called for a single recipe")
	}
	if len(sess.Steps) != 2 {
		t.Fatalf("expected 2 steps, got %d", len(sess.Steps))
	}
	if sess.Steps[0].SourceDishTag != "Pasta" {
		t.Errorf("step 0 dish tag = %q, want %q", sess.Steps[0].SourceDishTag, "Pasta")
	}
}

func TestSessionService_CreateMultiRecipe_MergeCalled(t *testing.T) {
	recipeRepo := &stubRecipeRepo{
		recipes: map[types.RecipeID]*types.Recipe{
			"r1": {
				ID:    "r1",
				Title: "Pasta",
				Steps: []types.RecipeStep{
					{OrderIndex: 0, Text: "Boil water"},
				},
			},
			"r2": {
				ID:    "r2",
				Title: "Salad",
				Steps: []types.RecipeStep{
					{OrderIndex: 0, Text: "Chop lettuce"},
				},
			},
		},
	}
	sessRepo := newStubSessionRepo()
	goldenResp := `[{"order_index":0,"text":"Boil water","source_dish_tag":"Pasta"},{"order_index":1,"text":"Chop lettuce","source_dish_tag":"Salad"}]`
	stub := &stubLLMClient{response: goldenResp}
	mergeSvc := service.NewMergeService(stub)
	svc := service.NewSessionService(sessRepo, recipeRepo, mergeSvc)

	sess, err := svc.Create(context.Background(), "user1", []types.RecipeID{"r1", "r2"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if !stub.called {
		t.Error("LLM should be called for multiple recipes")
	}
	if len(sess.Steps) != 2 {
		t.Fatalf("expected 2 steps, got %d", len(sess.Steps))
	}
}

func TestSessionService_CompleteLastStep_AutoCompletes(t *testing.T) {
	recipeRepo := &stubRecipeRepo{
		recipes: map[types.RecipeID]*types.Recipe{
			"r1": {
				ID:    "r1",
				Title: "Pasta",
				Steps: []types.RecipeStep{
					{OrderIndex: 0, Text: "Step 1"},
					{OrderIndex: 1, Text: "Step 2"},
				},
			},
		},
	}
	sessRepo := newStubSessionRepo()
	stub := &stubLLMClient{}
	mergeSvc := service.NewMergeService(stub)
	svc := service.NewSessionService(sessRepo, recipeRepo, mergeSvc)

	sess, err := svc.Create(context.Background(), "user1", []types.RecipeID{"r1"})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	// Start the session.
	if err := svc.Start(context.Background(), sess.ID); err != nil {
		t.Fatalf("Start: %v", err)
	}

	// Complete first step.
	if err := svc.CompleteStep(context.Background(), sess.ID, sess.Steps[0].ID); err != nil {
		t.Fatalf("CompleteStep 0: %v", err)
	}

	// Session should still be in progress.
	state, err := svc.GetState(context.Background(), sess.ID)
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}
	if state.Status == types.SessionCompleted {
		t.Error("session should not be completed yet")
	}

	// Complete last step.
	if err := svc.CompleteStep(context.Background(), sess.ID, sess.Steps[1].ID); err != nil {
		t.Fatalf("CompleteStep 1: %v", err)
	}

	// Session should auto-complete.
	state, err = svc.GetState(context.Background(), sess.ID)
	if err != nil {
		t.Fatalf("GetState: %v", err)
	}
	if state.Status != types.SessionCompleted {
		t.Errorf("expected status %q, got %q", types.SessionCompleted, state.Status)
	}
}
