package types

import "time"

type UserID string
type RecipeID string
type SessionID string

type User struct {
	ID           UserID    `json:"id"`
	Email        string    `json:"email"`
	DisplayName  string    `json:"display_name"`
	PasswordHash string    `json:"-"`
	GoogleID     string    `json:"google_id,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

type Recipe struct {
	ID          RecipeID     `json:"id"`
	Title       string       `json:"title"`
	Description string       `json:"description"`
	SourceURL   string       `json:"source_url,omitempty"`
	SourceType  string       `json:"source_type"`
	Cuisine     string       `json:"cuisine,omitempty"`
	ImageURL    string       `json:"image_url,omitempty"`
	UserID      UserID       `json:"user_id"`
	Ingredients []string     `json:"ingredients"`
	Steps       []RecipeStep `json:"steps"`
	CreatedAt   time.Time    `json:"created_at"`
	UpdatedAt   time.Time    `json:"updated_at"`
}

type RecipeStep struct {
	OrderIndex int    `json:"order_index"`
	Text       string `json:"text"`
	ImageURL   string `json:"image_url,omitempty"`
}

type SessionStatus string

const (
	SessionSetup      SessionStatus = "setup"
	SessionInProgress SessionStatus = "in_progress"
	SessionPaused     SessionStatus = "paused"
	SessionCompleted  SessionStatus = "completed"
)

type CookingSession struct {
	ID          SessionID     `json:"id"`
	UserID      UserID        `json:"user_id"`
	Status      SessionStatus `json:"status"`
	RecipeIDs   []RecipeID    `json:"recipe_ids"`
	Steps       []SessionStep `json:"steps"`
	CreatedAt   time.Time     `json:"created_at"`
	StartedAt   *time.Time    `json:"started_at,omitempty"`
	CompletedAt *time.Time    `json:"completed_at,omitempty"`
}

type SessionStep struct {
	ID            string     `json:"id"`
	OrderIndex    int        `json:"order_index"`
	Text          string     `json:"text"`
	SourceDishTag string     `json:"source_dish_tag,omitempty"`
	IsCompleted   bool       `json:"is_completed"`
	CompletedAt   *time.Time `json:"completed_at,omitempty"`
	AgentNotes    string     `json:"agent_notes,omitempty"`
}

type ConversationTurn struct {
	ID        string         `json:"id"`
	SessionID SessionID      `json:"session_id"`
	Role      string         `json:"role"` // user, assistant, system
	Content   string         `json:"content"`
	ToolCalls map[string]any `json:"tool_calls,omitempty"`
	CreatedAt time.Time      `json:"created_at"`
}

type JobType string
type JobStatus string

const (
	JobIngestVideo    JobType = "ingest_video"
	JobGenerateImages JobType = "generate_images"

	JobPending JobStatus = "pending"
	JobRunning JobStatus = "running"
	JobDone    JobStatus = "done"
	JobFailed  JobStatus = "failed"
)
