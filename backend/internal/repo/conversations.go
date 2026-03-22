package repo

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/yingcong/mise-en-place/backend/internal/types"
)

// ConversationRepo defines the interface for conversation turn persistence.
type ConversationRepo interface {
	// AddTurn persists a new conversation turn.
	AddTurn(ctx context.Context, sessionID types.SessionID, role, content string, toolCalls map[string]any) error

	// GetHistory returns all turns for a session ordered by created_at.
	GetHistory(ctx context.Context, sessionID types.SessionID) ([]types.ConversationTurn, error)

	// GetRecentHistory returns the most recent `limit` turns ordered by created_at.
	GetRecentHistory(ctx context.Context, sessionID types.SessionID, limit int) ([]types.ConversationTurn, error)
}

// PgConversationRepo implements ConversationRepo using PostgreSQL.
type PgConversationRepo struct {
	pool *pgxpool.Pool
}

// NewPgConversationRepo creates a new PgConversationRepo.
func NewPgConversationRepo(pool *pgxpool.Pool) *PgConversationRepo {
	return &PgConversationRepo{pool: pool}
}

// AddTurn inserts a new conversation turn.
func (r *PgConversationRepo) AddTurn(ctx context.Context, sessionID types.SessionID, role, content string, toolCalls map[string]any) error {
	var toolCallsJSON []byte
	var err error
	if toolCalls != nil {
		toolCallsJSON, err = json.Marshal(toolCalls)
		if err != nil {
			return fmt.Errorf("repo: marshal tool_calls: %w", err)
		}
	}

	_, err = r.pool.Exec(ctx,
		`INSERT INTO conversation_turns (session_id, role, content, tool_calls)
		 VALUES ($1, $2, $3, $4)`,
		sessionID, role, content, toolCallsJSON,
	)
	if err != nil {
		return fmt.Errorf("repo: insert turn: %w", err)
	}
	return nil
}

// GetHistory returns all turns for a session ordered by created_at ascending.
func (r *PgConversationRepo) GetHistory(ctx context.Context, sessionID types.SessionID) ([]types.ConversationTurn, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, session_id, role, content, tool_calls, created_at
		 FROM conversation_turns
		 WHERE session_id = $1
		 ORDER BY created_at ASC`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("repo: query turns: %w", err)
	}
	defer rows.Close()

	var turns []types.ConversationTurn
	for rows.Next() {
		var t types.ConversationTurn
		var toolCallsJSON []byte
		if err := rows.Scan(&t.ID, &t.SessionID, &t.Role, &t.Content, &toolCallsJSON, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("repo: scan turn: %w", err)
		}
		if toolCallsJSON != nil {
			if err := json.Unmarshal(toolCallsJSON, &t.ToolCalls); err != nil {
				return nil, fmt.Errorf("repo: unmarshal tool_calls: %w", err)
			}
		}
		turns = append(turns, t)
	}
	return turns, rows.Err()
}

// GetRecentHistory returns the most recent `limit` turns ordered by created_at ascending.
func (r *PgConversationRepo) GetRecentHistory(ctx context.Context, sessionID types.SessionID, limit int) ([]types.ConversationTurn, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, session_id, role, content, tool_calls, created_at
		 FROM (
		   SELECT id, session_id, role, content, tool_calls, created_at
		   FROM conversation_turns
		   WHERE session_id = $1
		   ORDER BY created_at DESC
		   LIMIT $2
		 ) sub
		 ORDER BY created_at ASC`, sessionID, limit)
	if err != nil {
		return nil, fmt.Errorf("repo: query recent turns: %w", err)
	}
	defer rows.Close()

	var turns []types.ConversationTurn
	for rows.Next() {
		var t types.ConversationTurn
		var toolCallsJSON []byte
		if err := rows.Scan(&t.ID, &t.SessionID, &t.Role, &t.Content, &toolCallsJSON, &t.CreatedAt); err != nil {
			return nil, fmt.Errorf("repo: scan turn: %w", err)
		}
		if toolCallsJSON != nil {
			if err := json.Unmarshal(toolCallsJSON, &t.ToolCalls); err != nil {
				return nil, fmt.Errorf("repo: unmarshal tool_calls: %w", err)
			}
		}
		turns = append(turns, t)
	}
	return turns, rows.Err()
}
