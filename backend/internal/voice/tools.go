package voice

import "github.com/yingcong/mise-en-place/backend/internal/llm"

// CookingToolDefs returns the tool definitions available to the cooking
// assistant during voice interactions.
func CookingToolDefs() []llm.ToolDef {
	return []llm.ToolDef{
		{
			Name:        "navigate_step",
			Description: "Navigate to a specific step in the recipe",
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"step_number": map[string]any{
						"type":        "integer",
						"description": "The step number to navigate to",
					},
				},
				"required": []string{"step_number"},
			},
		},
		{
			Name:        "mark_step_complete",
			Description: "Mark the current step as done and advance to the next step",
			Parameters: map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
		{
			Name:        "set_timer",
			Description: "Set a cooking timer with a label and duration",
			Parameters: map[string]any{
				"type": "object",
				"properties": map[string]any{
					"label": map[string]any{
						"type":        "string",
						"description": "A descriptive label for the timer",
					},
					"duration_seconds": map[string]any{
						"type":        "integer",
						"description": "Timer duration in seconds",
					},
				},
				"required": []string{"label", "duration_seconds"},
			},
		},
		{
			Name:        "get_cooking_state",
			Description: "Get the current cooking session state including step, timers, and ingredients",
			Parameters: map[string]any{
				"type":       "object",
				"properties": map[string]any{},
			},
		},
	}
}
