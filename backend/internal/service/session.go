package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/yingcong/mise-en-place/backend/internal/repo"
	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// Sentinel errors for the session service.
var (
	ErrSessionNotFound = errors.New("session: not found")
	ErrRecipeNotFound  = errors.New("session: recipe not found")
	ErrNoRecipes       = errors.New("session: at least one recipe ID is required")
)

// SessionService orchestrates cooking session lifecycle.
type SessionService struct {
	sessions repo.SessionRepo
	recipes  repo.RecipeRepo
	merge    *MergeService
}

// NewSessionService creates a SessionService.
func NewSessionService(sessions repo.SessionRepo, recipes repo.RecipeRepo, merge *MergeService) *SessionService {
	return &SessionService{
		sessions: sessions,
		recipes:  recipes,
		merge:    merge,
	}
}

// Create fetches the recipes, merges their steps (if >1), creates the session,
// and adds the merged steps.
func (s *SessionService) Create(ctx context.Context, userID types.UserID, recipeIDs []types.RecipeID) (*types.CookingSession, error) {
	if len(recipeIDs) == 0 {
		return nil, ErrNoRecipes
	}

	// Fetch all recipes.
	recipes := make([]types.Recipe, 0, len(recipeIDs))
	for _, id := range recipeIDs {
		r, err := s.recipes.GetByID(ctx, id)
		if err != nil {
			return nil, fmt.Errorf("session: fetch recipe %s: %w", id, err)
		}
		if r == nil {
			return nil, fmt.Errorf("%w: %s", ErrRecipeNotFound, id)
		}
		recipes = append(recipes, *r)
	}

	// Merge steps.
	merged, err := s.merge.MergeRecipes(ctx, recipes)
	if err != nil {
		return nil, fmt.Errorf("session: merge: %w", err)
	}

	// Create session.
	session, err := s.sessions.Create(ctx, userID, recipeIDs)
	if err != nil {
		return nil, fmt.Errorf("session: create: %w", err)
	}

	// Add merged steps.
	inputs := make([]repo.SessionStepInput, len(merged))
	for i, m := range merged {
		inputs[i] = repo.SessionStepInput{
			OrderIndex:    m.OrderIndex,
			Text:          m.Text,
			SourceDishTag: m.SourceDishTag,
		}
	}
	if err := s.sessions.AddSteps(ctx, session.ID, inputs); err != nil {
		return nil, fmt.Errorf("session: add steps: %w", err)
	}

	// Re-fetch to get the full state with steps.
	return s.sessions.GetByID(ctx, session.ID)
}

// Start sets the session status to in_progress.
func (s *SessionService) Start(ctx context.Context, sessionID types.SessionID) error {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil {
		return err
	}
	if sess == nil {
		return ErrSessionNotFound
	}
	return s.sessions.UpdateStatus(ctx, sessionID, types.SessionInProgress)
}

// Pause sets the session status to paused.
func (s *SessionService) Pause(ctx context.Context, sessionID types.SessionID) error {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil {
		return err
	}
	if sess == nil {
		return ErrSessionNotFound
	}
	return s.sessions.UpdateStatus(ctx, sessionID, types.SessionPaused)
}

// Resume sets the session status to in_progress.
func (s *SessionService) Resume(ctx context.Context, sessionID types.SessionID) error {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil {
		return err
	}
	if sess == nil {
		return ErrSessionNotFound
	}
	return s.sessions.UpdateStatus(ctx, sessionID, types.SessionInProgress)
}

// CompleteStep marks a step as done. If all steps are completed, the session
// auto-completes.
func (s *SessionService) CompleteStep(ctx context.Context, sessionID types.SessionID, stepID string) error {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil {
		return err
	}
	if sess == nil {
		return ErrSessionNotFound
	}

	if err := s.sessions.UpdateStep(ctx, stepID, true, ""); err != nil {
		return err
	}

	// Check if all steps are now completed.
	allDone := true
	for _, step := range sess.Steps {
		if step.ID == stepID {
			continue // This one is being completed now.
		}
		if !step.IsCompleted {
			allDone = false
			break
		}
	}

	if allDone {
		return s.sessions.UpdateStatus(ctx, sessionID, types.SessionCompleted)
	}

	return nil
}

// ListByUser returns all sessions for a user (without steps).
func (s *SessionService) ListByUser(ctx context.Context, userID types.UserID) ([]types.CookingSession, error) {
	return s.sessions.ListByUser(ctx, userID)
}

// GetState returns the full session state including steps.
func (s *SessionService) GetState(ctx context.Context, sessionID types.SessionID) (*types.CookingSession, error) {
	sess, err := s.sessions.GetByID(ctx, sessionID)
	if err != nil {
		return nil, err
	}
	if sess == nil {
		return nil, ErrSessionNotFound
	}
	return sess, nil
}
