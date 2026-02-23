# Technical Specifications

## Architecture
- **Frontend**: Flutter (Mobile/Tablet).
- **Backend/DB**: Supabase (PostgreSQL).
- **Orchestration**: n8n (Workflow Automation).
- **Voice AI**: ElevenLabs (Conversational Agent).

## Data Flow
1.  **App Start**: Fetch Recipes from Supabase `recipes` table.
2.  **User Interaction**:
    - Select Recipe -> View Details (`getRecipeById`).
    - "Start Cooking" -> Enters `CookingModeScreen`.
3.  **Voice Mode**:
    - App initializes ElevenLabs WebSocket/Widget.
    - Agent receives context (current step, ingredients).
    - User asks "What's next?", Agent responds based on context.

## Integration Details

### Supabase
- **Auth**: Anon Key for public read access.
- **Tables**:
    - `recipes` (Core metadata)
    - `ingredient_master`, `equipment_master` (Reference data)
    - `recipe_ingredients`, `recipe_equipment` (Join tables)
    - `instruction_steps` (Ordered steps)
    - `user_pantry` (User inventory - *New*)

### ElevenLabs
- **SDK**: `elevenlabs_flutter` (or UI Kit).
- **Agent config**:
    - Create a Conversational Agent in ElevenLabs Dashboard.
    - **Knowledge Base**: Can be dynamic or pre-loaded.
    - **Tools**: Client tools to navigate app (e.g., `nextStep()`, `repeatStep()`).

### n8n
- **Trigger**: Webhook from App (e.g., "Merge these 3 recipes").
- **Process**: LLM Chain to merge ingredients and re-order instructions.
- **Output**: JSON payload of new temporary recipe.
