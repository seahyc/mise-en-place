# n8n Workflows Specification

This document describes the n8n workflows that power the Mise en Place cooking assistant backend.

## Architecture Overview

```
Flutter App                         n8n Workflows                      External Services
───────────                         ─────────────                      ─────────────────

┌─────────────┐    HTTP POST       ┌──────────────────────────────┐
│ Start       │───────────────────▶│ Workflow 1: Generate Session │──┐
│ Cooking     │                    │ • AI Agent + Postgres Tool   │  │
└─────────────┘                    └──────────────────────────────┘  │
                                                                      │
                                   ┌──────────────────────────────┐  │   ┌────────────┐
                                   │ Workflow 2: Init Voice Agent │◀─┘   │ ElevenLabs │
                                   │ • HTTP Request to ElevenLabs │─────▶│ Agent API  │
                                   └──────────────────────────────┘      └────────────┘
                                              │
                                              │ WebSocket
                                              ▼
┌─────────────┐                    ┌──────────────────────────────┐
│ Voice Agent │◀──────────────────▶│ ElevenLabs Conversational    │
│ (in app)    │                    │ Agent with Tool Calls        │
└─────────────┘                    └──────────────────────────────┘
       │                                      │
       │ Tool calls trigger                   │
       ▼                                      ▼
┌──────────────────────────────────────────────────────────────────┐
│ Workflows 3-5: Modify Instructions / Adjust Servings / Missing   │
│ • AI Agent intelligently updates Supabase                        │
└──────────────────────────────────────────────────────────────────┘
```

## Database Tables (New)

These tables must be added to Supabase to support cooking sessions:

```sql
-- Cooking sessions (mutable runtime instance)
CREATE TABLE cooking_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID, -- References auth.users if using Supabase Auth
    status TEXT DEFAULT 'preparing', -- preparing, active, paused, completed, cancelled
    source_recipe_ids UUID[], -- Array of original recipe IDs
    original_servings JSONB, -- {"recipe_id": servings, ...}
    current_servings JSONB,  -- Can be modified mid-session
    current_step_index INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- Merged instruction steps for a session
CREATE TABLE cooking_session_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    short_text TEXT NOT NULL,
    detailed_description TEXT,
    source_recipe_ids UUID[], -- Which original recipes this step came from
    scaled_ingredients JSONB, -- [{"name": "Garlic", "amount": 4, "unit": "cloves", "original": 2}]
    equipment_needed TEXT[],
    estimated_duration_sec INTEGER,
    tips TEXT[], -- Additional tips for voice agent to share
    status TEXT DEFAULT 'pending', -- pending, in_progress, completed, skipped
    completed_at TIMESTAMPTZ,
    notes TEXT -- Modifications made mid-session
);

-- Audit trail for session modifications
CREATE TABLE session_modifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    step_index INTEGER,
    modification_type TEXT NOT NULL, -- ingredient_issue, serving_change, substitution, step_added, step_removed
    request_details JSONB, -- What was requested
    changes_made JSONB, -- What changes were applied
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Workflow 1: Generate Cooking Session

Creates a new cooking session by fetching recipes, scaling ingredients, checking inventory, and merging instructions.

### Endpoint
```
POST /webhook/cooking-session/generate
```

### Request Body
```json
{
    "user_id": "uuid-or-null-for-anonymous",
    "selected_recipes": [
        {
            "recipe_id": "uuid-of-recipe",
            "servings_requested": 4
        },
        {
            "recipe_id": "uuid-of-another-recipe",
            "servings_requested": 2
        }
    ],
    "user_context": {
        "name": "Alex",
        "experience_level": "beginner"
    }
}
```

### n8n Node Configuration

#### Node 1: Webhook Trigger
- **HTTP Method**: POST
- **Path**: `cooking-session/generate`
- **Response Mode**: Using "Respond to Webhook" node

#### Node 2: AI Agent (Tools Agent)
- **Agent Type**: Tools Agent
- **Model**: GPT-4 or Claude (via LangChain)
- **System Prompt**:

```
You are a culinary assistant for the Mise en Place cooking app. Generate an optimized cooking session by:

1. FETCH recipes from database using the provided recipe_ids
2. SCALE ingredient amounts based on (servings_requested / base_servings)
3. MERGE multiple recipes into a single optimized instruction set following mise en place principles:
   - Group all prep work together (all chopping first, all measuring first)
   - Identify tasks that can run in parallel (while X simmers, prep Y)
   - Order steps efficiently (consider shared equipment, cooking times)
   - Add a "mise en place checkpoint" step before active cooking begins
4. CREATE a cooking_sessions record
5. INSERT merged steps into cooking_session_steps

SCALING RULES:
- Most ingredients: linear scaling (2x servings = 2x amount)
- Spices/seasonings: scale at 0.7 power (prevents over-seasoning)
- Salt: scale at 0.8 power
- Cooking oil for frying: minimum amount needed, doesn't scale linearly
- Eggs: round to nearest whole number

DATABASE SCHEMA:
- recipes(id, title, base_servings, ...)
- recipe_ingredients(recipe_id, ingredient_id, amount, unit, display_string)
- instruction_steps(recipe_id, order_index, short_text, detailed_description)
- ingredient_master(id, name)
- cooking_sessions(id, user_id, status, source_recipe_ids, original_servings, current_servings, ...)
- cooking_session_steps(id, session_id, order_index, short_text, detailed_description, scaled_ingredients, ...)

After creating the session, return:
- session_id
- total_steps count
- estimated_total_time_minutes
- prep_checklist (list of items to gather)
```

**Connected Sub-nodes:**

##### Postgres Tool
- **Credential**: Supabase PostgreSQL connection
- **Allowed Operations**: SELECT, INSERT

Example queries the agent will construct:
```sql
-- Fetch recipes with ingredients and steps
SELECT r.id, r.title, r.base_servings,
    json_agg(DISTINCT jsonb_build_object(
        'ingredient_id', ri.ingredient_id,
        'name', im.name,
        'amount', ri.amount,
        'unit', ri.unit
    )) as ingredients,
    json_agg(DISTINCT jsonb_build_object(
        'order_index', ins.order_index,
        'short_text', ins.short_text,
        'detailed_description', ins.detailed_description
    ) ORDER BY ins.order_index) as steps
FROM recipes r
LEFT JOIN recipe_ingredients ri ON r.id = ri.recipe_id
LEFT JOIN ingredient_master im ON ri.ingredient_id = im.id
LEFT JOIN instruction_steps ins ON r.id = ins.recipe_id
WHERE r.id = ANY($1::uuid[])
GROUP BY r.id;

-- Create session
INSERT INTO cooking_sessions (user_id, status, source_recipe_ids, original_servings, current_servings)
VALUES ($1, 'preparing', $2, $3, $3)
RETURNING id;

-- Insert merged steps
INSERT INTO cooking_session_steps (session_id, order_index, short_text, detailed_description, source_recipe_ids, scaled_ingredients, tips)
VALUES ($1, $2, $3, $4, $5, $6, $7);
```

##### Code Tool (Scaling Logic)
```javascript
// Intelligent ingredient scaling
function scaleIngredients(ingredients, scaleFactor) {
    const spiceKeywords = ['cumin', 'paprika', 'oregano', 'chili', 'coriander', 'turmeric'];

    return ingredients.map(ing => {
        let factor = scaleFactor;
        const nameLower = ing.name.toLowerCase();

        // Non-linear scaling for certain ingredients
        if (spiceKeywords.some(s => nameLower.includes(s))) {
            factor = Math.pow(scaleFactor, 0.7);
        } else if (nameLower.includes('salt')) {
            factor = Math.pow(scaleFactor, 0.8);
        } else if (ing.unit === 'for frying' || nameLower.includes('oil') && ing.amount < 50) {
            factor = Math.max(1, scaleFactor * 0.5); // Oil doesn't scale much
        } else if (nameLower.includes('egg')) {
            return { ...ing, amount: Math.round(ing.amount * scaleFactor) };
        }

        return {
            ...ing,
            amount: Math.round(ing.amount * factor * 10) / 10,
            original_amount: ing.amount,
            scale_factor: factor
        };
    });
}

return scaleIngredients($input.all()[0].json.ingredients, $input.all()[0].json.scaleFactor);
```

#### Node 3: Respond to Webhook

### Response Body
```json
{
    "success": true,
    "session_id": "uuid-of-new-session",
    "total_steps": 8,
    "estimated_total_time_minutes": 45,
    "prep_checklist": [
        "2 cans black beans",
        "1 medium onion",
        "2 bell peppers",
        "Large pot",
        "Wooden spoon"
    ],
    "merged_recipe_titles": ["Vegan Chili", "Pad Thai"]
}
```

---

## Workflow 2: Initialize Voice Agent

Loads the cooking session into ElevenLabs and returns connection details.

### Endpoint
```
POST /webhook/voice-agent/init
```

### Request Body
```json
{
    "session_id": "uuid-of-session",
    "user_context": {
        "name": "Alex",
        "experience_level": "beginner"
    }
}
```

### n8n Node Configuration

#### Node 1: Webhook Trigger
- **Path**: `voice-agent/init`

#### Node 2: Postgres Node
Fetch the session with all steps:
```sql
SELECT
    cs.*,
    json_agg(css.* ORDER BY css.order_index) as steps
FROM cooking_sessions cs
JOIN cooking_session_steps css ON cs.id = css.session_id
WHERE cs.id = $1
GROUP BY cs.id;
```

#### Node 3: HTTP Request Node (ElevenLabs API)
- **Method**: POST
- **URL**: `https://api.elevenlabs.io/v1/convai/conversations`
- **Authentication**: Header Auth (`xi-api-key`)
- **Body**:
```json
{
    "agent_id": "{{ $env.ELEVENLABS_AGENT_ID }}",
    "conversation_config_override": {
        "agent": {
            "prompt": {
                "prompt": "You are a friendly cooking assistant guiding {{user_name}} through their cooking session..."
            }
        },
        "tts": {
            "voice_id": "{{ $env.ELEVENLABS_VOICE_ID }}"
        }
    },
    "dynamic_variables": {
        "user_name": "{{ $json.user_context.name }}",
        "experience_level": "{{ $json.user_context.experience_level }}",
        "total_steps": "{{ $json.steps.length }}",
        "recipe_titles": "{{ $json.merged_recipe_titles.join(', ') }}",
        "instruction_set": "{{ JSON.stringify($json.steps) }}"
    }
}
```

#### Node 4: Postgres Node (Update session status)
```sql
UPDATE cooking_sessions
SET status = 'active', started_at = NOW()
WHERE id = $1;
```

#### Node 5: Respond to Webhook

### Response Body
```json
{
    "success": true,
    "conversation_id": "elevenlabs-conversation-id",
    "signed_url": "wss://...",
    "session_status": "active",
    "first_step": {
        "order_index": 0,
        "short_text": "Mise en Place",
        "detailed_description": "Let's gather everything we need..."
    }
}
```

---

## Workflow 3: Modify Instructions (Structured Operations)

Called by Flutter app when ElevenLabs agent's `modify_instructions` client tool is invoked.
Returns **atomic operations** instead of wholesale rewrites to optimize video generation.

### Design Philosophy

**Why structured operations?**
- Video generation (Veo3) is expensive - don't regenerate when only quantities change
- Atomic operations enable precise tracking and rollback
- Content hashing allows video reuse across sessions/recipes

### Operation Types

| Operation | Video Generation? | Use Case |
|-----------|-------------------|----------|
| `insert` | YES | Add recovery step (burnt food) |
| `update` | MAYBE | Change technique (if core action changes) |
| `delete` | NO | Remove unnecessary step |
| `adjust_quantity` | NO | Scale ingredient amounts |
| `substitute` | NO | Replace ingredient (same visual action) |
| `reorder` | NO | Optimize step order |

### Endpoint
```
POST /webhook/session/modify
```

### Request Body
```json
{
    "session_id": "uuid",
    "current_step_index": 3,
    "issue_type": "burnt_ingredient",
    "details": "User burnt the onions",
    "affected_ingredient": "onion",
    "remaining_steps": [
        {
            "index": 3,
            "id": "step-uuid",
            "short_text": "Sauté aromatics",
            "detailed_description": "Heat {i:oil:qty} in {e:pan}. Add {i:onion:qty} of diced {i:onion}...",
            "ingredients": [
                {"placeholder_key": "onion", "name": "Onion", "amount": 200, "unit": "g"},
                {"placeholder_key": "oil", "name": "Olive oil", "amount": 30, "unit": "ml"}
            ]
        }
    ]
}
```

**Supported issue_type values:**
- `burnt_ingredient` - Food is burnt, needs replacement
- `missing_ingredient` - Ran out or don't have ingredient
- `equipment_issue` - Equipment broken/missing/malfunctioning
- `timing_issue` - Something took longer/shorter than expected
- `user_request` - User wants to change something (make it spicier, add veggies, etc.)
- `dietary_restriction` - User mentions allergy/diet mid-cooking
- `portion_change` - User wants more/less servings mid-cook
- `other` - General modification request

### n8n Node Configuration

#### Node 1: Webhook Trigger
- **HTTP Method**: POST
- **Path**: `session/modify`

#### Node 2: AI Agent (Tools Agent)
**System Prompt**:
```
You are a cooking session modifier. Given an issue reported by the user,
return a JSON array of ATOMIC OPERATIONS to fix the session.

CONTEXT:
- Session ID: {{session_id}}
- Current step: {{current_step_index}}
- Issue type: {{issue_type}}
- Issue details: {{details}}
- Affected ingredient: {{affected_ingredient}}
- Remaining steps: {{remaining_steps}}

OPERATION TYPES (use the MOST SPECIFIC one):

1. `insert` - Add a completely new step
   - Use for: Recovery steps, additional prep
   - Requires: step_index, short_text, detailed_description
   - Note: Requires video generation

2. `update` - Modify step text/instructions
   - Use for: Changing technique (e.g., "pan fry" → "air fry")
   - Requires: step_index, short_text, detailed_description
   - Note: May require video if core action changes

3. `delete` - Remove a step entirely
   - Use for: Skip unnecessary steps
   - Requires: step_index

4. `adjust_quantity` - Change ingredient amount (NO video needed!)
   - Use for: Reducing onions because some burnt, scaling up/down
   - Requires: step_index, placeholder_key, new_amount

5. `substitute` - Replace ingredient with another (NO video needed!)
   - Use for: Missing ingredient, dietary swap
   - Requires: step_index, placeholder_key, new_ingredient_name, substitution_note

6. `reorder` - Move step to different position (NO video needed!)
   - Use for: Optimize cooking flow
   - Requires: step_index, new_index

CRITICAL RULES:
1. PREFER adjust_quantity and substitute over update when possible
2. Only use insert for genuinely NEW steps (not modifications)
3. Never rewrite steps wholesale - make minimal targeted changes
4. Return operations in execution order
5. Only modify steps with index >= current_step_index

OUTPUT FORMAT (strict JSON):
{
  "operations": [
    {
      "operation": "insert",
      "step_index": 3,
      "short_text": "Prep replacement onions",
      "detailed_description": "Dice {i:onion:qty} of fresh {i:onion}..."
    },
    {
      "operation": "adjust_quantity",
      "step_index": 5,
      "placeholder_key": "onion",
      "new_amount": 150
    }
  ],
  "agent_message": "What to tell the user verbally",
  "time_impact_minutes": 5
}
```

**Connected Tools:**
- None required - AI returns structured JSON, Flutter applies operations

#### Node 3: Respond to Webhook

### Response Body (Structured Operations)
```json
{
    "success": true,
    "operations": [
        {
            "operation": "insert",
            "step_index": 3,
            "short_text": "Prep replacement onions",
            "detailed_description": "Dice {i:onion:qty} of fresh {i:onion}. We're using a bit less this time."
        },
        {
            "operation": "adjust_quantity",
            "step_index": 5,
            "placeholder_key": "onion",
            "new_amount": 150
        }
    ],
    "agent_message": "No worries! I've added a step to prep new onions. We'll use a bit less this time - about 150 grams.",
    "requires_video_generation": true,
    "time_impact_minutes": 5
}
```

### Architecture: n8n Writes to Supabase, Flutter Subscribes via Realtime

**New Flow (Recommended):**
```
Flutter calls n8n → n8n applies operations to Supabase → Supabase Realtime notifies Flutter
```

This approach is cleaner because:
- n8n has direct Supabase/Postgres access
- Flutter doesn't need to parse and apply operations
- Realtime subscription ensures UI stays in sync
- Single source of truth (database)

### Flutter Client Tool Implementation

The `modify_instructions` is a **client tool** - Flutter calls n8n, which writes to Supabase. Flutter receives updates via Realtime subscription:

```dart
class ModifyInstructionsTool implements ClientTool {
  final String n8nWebhookUrl;
  final String sessionId;
  final int Function() getCurrentStepIndex;
  final List<Map<String, dynamic>> Function() getRemainingSteps;

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> params) async {
    // 1. Call n8n webhook - n8n will write to Supabase
    final response = await http.post(
      Uri.parse('$n8nWebhookUrl/session/modify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'session_id': sessionId,
        'current_step_index': getCurrentStepIndex(),
        'issue_type': params['issue_type'],
        'details': params['details'],
        'affected_ingredient': params['affected_ingredient'],
        'affected_equipment': params['affected_equipment'],
        'completed_steps': [], // TODO: pass completed steps
        'remaining_steps': getRemainingSteps(),
      }),
    );

    // 2. n8n writes to Supabase, Flutter will receive updates via Realtime
    final data = jsonDecode(response.body);

    // 3. Return message for agent to speak
    // UI updates happen automatically via Supabase Realtime subscription
    return ClientToolResult.success({
      'success': data['success'] ?? true,
      'operations_applied': data['operations_count'] ?? 0,
      'agent_message': data['agent_message'] ?? "I've adjusted the recipe.",
    });
  }
}
```

### Flutter Supabase Realtime Subscription

Subscribe to session_steps changes in CookingModeScreen:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class _CookingModeScreenState extends State<CookingModeScreen> {
  RealtimeChannel? _stepsChannel;

  @override
  void initState() {
    super.initState();
    _subscribeToStepChanges();
  }

  void _subscribeToStepChanges() {
    if (_session == null) return;

    _stepsChannel = supabase
      .channel('session_steps:${_session!.id}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'session_steps',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'session_id',
          value: _session!.id,
        ),
        callback: (payload) {
          debugPrint('Step change: ${payload.eventType}');
          _refreshSession(); // Re-fetch full session from Supabase
        },
      )
      .subscribe();
  }

  Future<void> _refreshSession() async {
    final updated = await _sessionService.getSession(_session!.id);
    if (updated != null && mounted) {
      setState(() {
        _session = updated;
      });
    }
  }

  @override
  void dispose() {
    _stepsChannel?.unsubscribe();
    super.dispose();
  }
}
```

### Why Realtime Over Direct Application

| Approach | Pros | Cons |
|----------|------|------|
| **Flutter applies ops** | Faster UI update | Two sources of truth, sync issues |
| **n8n writes, Realtime notifies** | Single source of truth, automatic sync | Slight latency (usually <100ms) |

For a cooking app where real-time sync is critical and modifications are infrequent, Realtime subscription is the better choice.

### Video Generation Logic

When applying operations, determine if new video is needed:

```dart
bool requiresVideoGeneration(Map<String, dynamic> op) {
  switch (op['operation']) {
    case 'insert':
      return true;  // New step = new video
    case 'update':
      // Check if core action changed (would need semantic analysis)
      return _hasActionChanged(op);
    case 'delete':
    case 'adjust_quantity':
    case 'substitute':
    case 'reorder':
      return false;  // Same visual, different data
  }
}
```

### Content Hash for Video Deduplication

```
hash = SHA256(canonical_action + ingredient_category + equipment)

Examples:
- "dice onion with knife" → hash_abc123
- "dice shallot with knife" → hash_abc123  (SAME - both alliums, same action)
- "julienne onion with knife" → hash_def456 (DIFFERENT - different technique)
```

---

## Workflow 4: Adjust Serving Size

Real-time serving adjustment during cooking.

### Endpoint
```
POST /webhook/session/adjust-servings
```

### Request Body
```json
{
    "session_id": "uuid",
    "current_step_index": 2,
    "adjustment": {
        "scope": "all",
        "new_servings": 6
    }
}
```

**scope options:**
- `"all"` - Scale all recipes proportionally
- `"recipe_uuid"` - Scale only one specific recipe
- `"ingredient_name"` - Adjust a single ingredient (e.g., "more garlic")

### n8n Node Configuration

#### Node 1: Webhook Trigger

#### Node 2: Postgres Node (Fetch session + remaining steps)

#### Node 3: AI Agent (Tools Agent)
**System Prompt**:
```
Adjust serving sizes for an active cooking session.

ADJUSTMENT REQUEST:
- Scope: {{adjustment.scope}}
- New servings: {{adjustment.new_servings}}
- Current step: {{current_step_index}}
- Current servings config: {{current_servings}}

RULES:
1. Only modify steps with order_index >= current_step_index (can't change what's already done)
2. Recalculate scaled_ingredients using intelligent scaling:
   - Spices: 0.7 power scaling
   - Salt: 0.8 power scaling
   - Frying oil: minimal scaling
   - Everything else: linear
3. Update detailed_description text where quantities are mentioned
4. Update cooking_sessions.current_servings
5. Log the change to session_modifications

IMPORTANT: Some ingredients may have already been prepped at original quantity.
Note in response which prepped ingredients won't match new serving size.
```

#### Node 4: Respond to Webhook

### Response Body
```json
{
    "success": true,
    "previous_servings": 4,
    "new_servings": 6,
    "steps_updated": 5,
    "agent_message": "I've scaled up to 6 servings. For the remaining steps, you'll need about 50% more of each ingredient.",
    "warnings": [
        "Note: You already prepped 4 servings worth of chopped onions in step 1. The final dish may have slightly less onion per serving."
    ],
    "updated_steps": [/* remaining steps with new quantities */]
}
```

---

## Workflow 5: Handle Missing Item

Handles missing ingredients or equipment discovered pre-cook or mid-session.

### Endpoint
```
POST /webhook/session/handle-missing
```

### Request Body
```json
{
    "session_id": "uuid",
    "context": "pre_cooking",
    "missing_item": {
        "type": "ingredient",
        "name": "Garlic",
        "required_amount": 4,
        "required_unit": "cloves"
    },
    "user_has_available": [
        {"name": "Garlic Powder", "amount": "1", "unit": "jar"},
        {"name": "Onion", "amount": 3, "unit": "whole"}
    ]
}
```

**context options:**
- `"pre_cooking"` - During stock check before starting
- `"mid_session"` - Discovered missing during cooking

### n8n Node Configuration

#### Node 1: Webhook Trigger

#### Node 2: AI Agent (Tools Agent)
**System Prompt**:
```
Handle a missing item for a cooking session.

MISSING ITEM:
- Type: {{missing_item.type}}
- Name: {{missing_item.name}}
- Required: {{missing_item.required_amount}} {{missing_item.required_unit}}
- Context: {{context}}

USER HAS AVAILABLE:
{{user_has_available}}

YOUR OPTIONS (choose best one):

1. SUBSTITUTION - Find suitable replacement from available items
   Common substitutions:
   - Fresh garlic → garlic powder (1 clove = 1/4 tsp powder)
   - Lime → lemon (1:1)
   - Fresh herbs → dried (3:1 fresh to dried)
   - Butter → oil (for cooking, not baking)
   - Vegetable stock → chicken stock or water + bouillon

2. OMISSION - If ingredient is non-critical
   - Garnishes can be skipped
   - Secondary seasonings can be reduced
   - Note impact on final dish

3. REDUCE SERVINGS - If ingredient is critical and no substitute
   - Calculate new max servings based on available amount
   - Offer to scale down the recipe

4. PROCEED WITHOUT - For equipment
   - Suggest alternative technique
   - e.g., No wok → use large skillet

FOR MID-SESSION CONTEXT:
Also update cooking_session_steps to reflect the chosen solution.

Return your recommendation with:
- chosen_option
- reasoning (1-2 sentences)
- impact_on_dish
- steps_to_modify (if any)
```

#### Node 3: Respond to Webhook

### Response Body
```json
{
    "success": true,
    "recommendation": {
        "option": "substitution",
        "substitute": {
            "name": "Garlic Powder",
            "amount": 1,
            "unit": "tsp"
        },
        "reasoning": "Garlic powder provides similar flavor. Use 1/4 tsp per clove of fresh garlic.",
        "impact_on_dish": "Slightly less pungent garlic flavor, but dish will still taste great.",
        "preparation_note": "Add garlic powder directly when the recipe calls for adding minced garlic."
    },
    "steps_modified": [
        {
            "order_index": 2,
            "change": "Updated instruction to use 1 tsp garlic powder instead of 4 cloves minced garlic"
        }
    ],
    "agent_message": "No fresh garlic? No problem! We'll use garlic powder instead - about 1 teaspoon. I've updated the recipe steps."
}
```

---

## ElevenLabs Agent Tool Definitions

The ElevenLabs conversational agent should be configured with these tool calls that trigger the n8n workflows:

```json
{
    "tools": [
        {
            "name": "modify_instructions",
            "description": "Modify the cooking session when the user reports an issue like burnt food, missing ingredient discovered mid-cook, or equipment problems. Returns structured operations for efficient updates.",
            "parameters": {
                "type": "object",
                "properties": {
                    "issue_type": {
                        "type": "string",
                        "enum": ["burnt_ingredient", "missing_ingredient", "equipment_issue", "timing_issue", "user_request", "dietary_restriction", "portion_change", "other"],
                        "description": "Category of the cooking issue or user request"
                    },
                    "details": {
                        "type": "string",
                        "description": "Specific details about what happened"
                    },
                    "affected_ingredient": {
                        "type": "string",
                        "description": "The ingredient that was affected, if applicable"
                    },
                    "affected_equipment": {
                        "type": "string",
                        "description": "The equipment that's not working/missing, if applicable"
                    }
                },
                "required": ["issue_type", "details"]
            },
            "client_side": true
        },
        {
            "name": "adjust_servings",
            "description": "Adjust the serving size for the remaining steps when user wants more or less food",
            "parameters": {
                "type": "object",
                "properties": {
                    "new_servings": {
                        "type": "number",
                        "description": "New number of servings desired"
                    },
                    "scope": {
                        "type": "string",
                        "description": "Which recipe to adjust: 'all' or specific recipe name"
                    }
                },
                "required": ["new_servings"]
            },
            "webhook_url": "https://your-n8n.com/webhook/session/adjust-servings"
        },
        {
            "name": "navigate_to_step",
            "description": "Move to a different step in the cooking process",
            "parameters": {
                "type": "object",
                "properties": {
                    "step_index": {
                        "type": "number",
                        "description": "The step number to navigate to (0-indexed)"
                    },
                    "direction": {
                        "type": "string",
                        "enum": ["next", "previous", "specific"],
                        "description": "Navigation direction"
                    }
                }
            },
            "client_side": true
        },
        {
            "name": "mark_step_complete",
            "description": "Mark the current step as completed and get the next step",
            "parameters": {
                "type": "object",
                "properties": {
                    "step_index": {
                        "type": "number"
                    }
                }
            },
            "client_side": true
        },
        {
            "name": "get_ingredient_details",
            "description": "Get detailed information about an ingredient including amount and any special preparation",
            "parameters": {
                "type": "object",
                "properties": {
                    "ingredient_name": {
                        "type": "string"
                    }
                },
                "required": ["ingredient_name"]
            },
            "client_side": true
        }
    ]
}
```

---

## Environment Variables Required

```bash
# n8n instance
N8N_WEBHOOK_BASE_URL=https://your-n8n-instance.com/webhook

# Supabase (for Postgres tool)
SUPABASE_DB_HOST=db.xxxxx.supabase.co
SUPABASE_DB_NAME=postgres
SUPABASE_DB_USER=postgres
SUPABASE_DB_PASSWORD=your-password
SUPABASE_DB_PORT=5432

# ElevenLabs
ELEVENLABS_API_KEY=your-api-key
ELEVENLABS_AGENT_ID=your-agent-id
ELEVENLABS_VOICE_ID=your-preferred-voice-id

# LLM for AI Agent
OPENAI_API_KEY=your-openai-key
# OR
ANTHROPIC_API_KEY=your-anthropic-key
```

---

## Error Handling

All workflows should return consistent error responses:

```json
{
    "success": false,
    "error": {
        "code": "SESSION_NOT_FOUND",
        "message": "No cooking session found with the provided ID",
        "details": {}
    }
}
```

Common error codes:
- `SESSION_NOT_FOUND` - Invalid session_id
- `RECIPE_NOT_FOUND` - Invalid recipe_id in request
- `INVALID_STEP_INDEX` - Step index out of range
- `DATABASE_ERROR` - Supabase query failed
- `ELEVENLABS_ERROR` - ElevenLabs API call failed
- `AGENT_ERROR` - AI agent failed to process request

---

## ElevenLabs Agent Configuration

This section describes the full configuration for the ElevenLabs Conversational AI agent that powers the voice-guided cooking experience.

### Agent Overview

The agent acts as a friendly cooking assistant that:
- Guides users through each step of their cooking session
- Provides tips and techniques beyond what's displayed on screen
- Waits for user confirmation before proceeding
- Adapts dynamically to issues (burnt food, missing ingredients, timing)
- Controls the app UI via client-side tools

### Dynamic Variables

Dynamic variables use the `{{variable_name}}` syntax and are **injected once at conversation start**. They are immutable during the session - for real-time state, use client tools instead.

#### Static Context (Set Once at Start)
| Variable | Type | Description | Example Value |
|----------|------|-------------|---------------|
| `user_name` | string | User's display name | `"Alex"` |
| `experience_level` | string | Cooking skill level | `"beginner"`, `"intermediate"`, `"advanced"` |
| `recipe_titles` | string | Comma-separated list of recipes | `"Pad Thai, Vegan Chili"` |
| `total_steps` | number | Total steps in session | `8` |
| `session_id` | string | UUID of cooking session | `"uuid-..."` |
| `initial_servings` | number | Starting serving size | `4` |
| `recipe_summary` | string | Brief overview of what we're cooking | `"A spicy Thai noodle dish with shrimp and peanuts"` |
| `key_ingredients` | string | Main ingredients to highlight | `"rice noodles, shrimp, tamarind paste, fish sauce"` |
| `estimated_time` | string | Total estimated cooking time | `"45 minutes"` |

#### Real-Time State (Fetch via Tools)
These should NOT be dynamic variables - use `get_cooking_state` tool instead:
- Current step index and details
- Completed steps list
- Active timers and their remaining time
- Adjusted serving size (if changed mid-session)
- Any modifications made to instructions

**Flutter SDK Usage:**
```dart
await client.startSession(
  agentId: 'YOUR_AGENT_ID',
  dynamicVariables: {
    // STATIC - set once, never changes
    'user_name': 'Alex',
    'experience_level': 'beginner',
    'recipe_titles': 'Pad Thai',
    'total_steps': 8,
    'session_id': 'uuid-...',
    'initial_servings': 4,
    'recipe_summary': 'Classic Thai stir-fried rice noodles...',
    'key_ingredients': 'rice noodles, shrimp, eggs, bean sprouts',
    'estimated_time': '45 minutes',
  },
);
```

### System Prompt

Two persona options are provided. Choose based on your app's personality:

#### Option A: Chef Mia (Warm & Encouraging)

```
You are Chef Mia, a friendly cooking assistant for the Mise en Place app. You're guiding {{user_name}} through cooking {{recipe_titles}} ({{total_steps}} steps, ~{{estimated_time}}).

## PERSONALITY
- Warm, patient, encouraging
- Use sensory cues ("you should hear a sizzle", "it should smell fragrant")
- Celebrate small wins ("Perfect!")
- Stay calm when issues arise

## CRITICAL: GETTING CURRENT STATE
You do NOT know the current step - you must call `get_cooking_state` to find out:
- What step the user is on
- Which steps are completed
- Any active timers
- Current serving size

ALWAYS call `get_cooking_state` when:
- Starting the conversation
- User returns after being away
- You're unsure what step they're on
- Before briefing a new step

## FLOW FOR EACH STEP
1. Call `get_cooking_state` to see current step
2. Brief the step (explain what & why)
3. Provide tips not shown on screen
4. Wait for confirmation ("Ready?" or "Let me know when done")
5. When confirmed, call `mark_step_complete`

## EXPERIENCE LEVEL: {{experience_level}}
- beginner: Explain terms, detailed guidance, more reassurance
- intermediate: Assume basics, focus on timing/flavor tips
- advanced: Keep concise, trust their judgment

## HANDLING ISSUES
- Stay calm ("No worries, we can fix this!")
- Call `modify_instructions` to adapt the recipe
- If unsalvageable, help pivot gracefully

## TOOLS
- `get_cooking_state` - ALWAYS call this to know current state
- `get_current_step_details` - Get full details of current step
- `mark_step_complete` - Advance to next step (call when user confirms done)
- `navigate_to_step` - Jump to specific step
- `get_ingredient_details` - Look up ingredient amounts
- `set_timer` - Start a timer on user's device
- `modify_instructions` - (webhook) Adapt recipe for issues
- `adjust_servings` - (webhook) Scale recipe up/down

## RULES
1. NEVER assume state - always call `get_cooking_state`
2. NEVER skip steps without confirmation
3. Keep responses SHORT for voice
4. Don't repeat what's on screen - add value beyond it
```

#### Option B: Gordon Ramsay (Direct & Passionate)

```
You are Gordon Ramsay coaching {{user_name}} through cooking {{recipe_titles}} via voice. You can hear them but cannot see what they're doing - rely on them telling you when steps are complete.

## PERSONALITY
- Direct, passionate, demanding excellence
- Supportive when things go wrong, stern when careless
- British expressions naturally ("bloody," "right," "brilliant")
- Never coddle, but always care about success
- Keep responses brief - they see instructions on screen

## CRITICAL: GETTING CURRENT STATE
You have NO visibility into the app state. You MUST call `get_cooking_state` to find out:
- Current step index and details
- Completed steps
- Active timers and remaining time
- Current servings

Call `get_cooking_state`:
- At conversation start
- When user returns after silence
- Before briefing any step
- When you've lost track

## INTERACTION STYLE
- One question at a time
- Wait for user confirmation before proceeding
- Listen for audio cues (chopping, timer beeps, sizzling)
- Acknowledge briefly, then next instruction
- If user sounds uncertain, check in

## HANDLING MISTAKES
1. Assess damage with specific questions
2. Never panic - stay calm and authoritative
3. Always offer practical solution
4. Remind them mistakes = learning
5. Inject humor to ease tension when appropriate

## SAFETY FIRST
- Always ask if they're hurt before worrying about food
- If things are burning: "Turn that heat down NOW!"
- Never rush knife work or hot oil

## TOOLS
- `get_cooking_state` - CRITICAL: Call to know where user is
- `get_current_step_details` - Full current step info
- `mark_step_complete` - When user confirms step done
- `navigate_to_step` - Jump forward/back
- `get_ingredient_details` - Look up amounts
- `set_timer` - Set timer on device
- `log_disaster` - Record what went wrong and recovery
- `modify_instructions` - (webhook) Adapt recipe for issues

## RULES
1. NEVER guess state - call `get_cooking_state`
2. Don't repeat on-screen instructions
3. Focus on encouragement, timing, real-time adjustments
4. When complete, sincere congratulations
5. Use the user's name occasionally but not excessively
6. Session ID for webhook tools: {{session_id}}
```

### First Message

```
Hey {{user_name}}! I'm Chef Mia, and I'll be your cooking companion today. We're making {{recipe_titles}} - {{#if total_steps > 6}}it's a bit of a journey but we'll have fun!{{else}}nice and straightforward!{{/if}}

Before we dive in, let's do a quick mise en place - that's French for "everything in its place." Can you gather these items? {{prep_checklist}}

Let me know when you're all set and we'll get cooking!
```

### Tool Configurations

#### Server Tools (Webhook to n8n)

##### 1. adjust_servings
Calls n8n workflow to scale recipe up/down.

```json
{
    "type": "webhook",
    "name": "adjust_servings",
    "description": "Adjust the serving size for remaining steps. Use when user says things like 'actually I need to feed 6 people' or 'can we make half?'",
    "api_schema": {
        "url": "https://your-n8n.com/webhook/session/adjust-servings",
        "method": "POST",
        "request_body_schema": {
            "type": "object",
            "properties": [
                {
                    "id": "session_id",
                    "type": "string",
                    "value_type": "dynamic_variable",
                    "dynamic_variable": "session_id"
                },
                {
                    "id": "current_step_index",
                    "type": "integer",
                    "value_type": "dynamic_variable",
                    "dynamic_variable": "current_step"
                },
                {
                    "id": "new_servings",
                    "type": "integer",
                    "description": "The new number of servings desired",
                    "value_type": "llm_prompt"
                },
                {
                    "id": "scope",
                    "type": "string",
                    "description": "Which recipe to adjust: 'all' for everything, or specific recipe name",
                    "value_type": "llm_prompt"
                }
            ]
        }
    },
    "response_timeout_secs": 10
}
```

##### 3. handle_missing_item
Calls n8n workflow when user discovers missing ingredient/equipment.

```json
{
    "type": "webhook",
    "name": "handle_missing_item",
    "description": "Handle a missing ingredient or equipment. Use when user says they don't have something needed for the recipe.",
    "api_schema": {
        "url": "https://your-n8n.com/webhook/session/handle-missing",
        "method": "POST",
        "request_body_schema": {
            "type": "object",
            "properties": [
                {
                    "id": "session_id",
                    "type": "string",
                    "value_type": "dynamic_variable",
                    "dynamic_variable": "session_id"
                },
                {
                    "id": "context",
                    "type": "string",
                    "description": "Either 'pre_cooking' or 'mid_session'",
                    "value_type": "llm_prompt"
                },
                {
                    "id": "missing_item_type",
                    "type": "string",
                    "description": "Either 'ingredient' or 'equipment'",
                    "value_type": "llm_prompt"
                },
                {
                    "id": "missing_item_name",
                    "type": "string",
                    "description": "Name of the missing item",
                    "value_type": "llm_prompt"
                }
            ]
        }
    },
    "response_timeout_secs": 10
}
```

#### Client Tools (Handled by Flutter App)

##### 1. modify_instructions (Structured Operations)
Handles cooking issues by calling n8n and applying atomic operations. This is a **client tool** that Flutter intercepts, forwards to n8n, then applies the returned operations.

```json
{
    "type": "client",
    "name": "modify_instructions",
    "description": "Modify the cooking session when the user reports an issue OR requests a change. Use when: food is burnt or dropped, ingredient ran out, equipment isn't working, timing went wrong, user wants to change something (spicier, add veggies), dietary restriction discovered, or portion change needed. Returns structured operations for efficient updates.",
    "parameters": {
        "type": "object",
        "properties": {
            "issue_type": {
                "type": "string",
                "enum": ["burnt_ingredient", "missing_ingredient", "equipment_issue", "timing_issue", "user_request", "dietary_restriction", "portion_change", "other"],
                "description": "Category of the cooking issue or user request"
            },
            "details": {
                "type": "string",
                "description": "Specific details about what happened or what the user wants"
            },
            "affected_ingredient": {
                "type": "string",
                "description": "The ingredient that was affected, if applicable"
            },
            "affected_equipment": {
                "type": "string",
                "description": "The equipment that's not working/missing, if applicable"
            }
        },
        "required": ["issue_type", "details"]
    },
    "response_timeout_secs": 15
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'modify_instructions': (Map<String, dynamic> params) async {
    // 1. Call n8n webhook with issue details + remaining steps
    final response = await http.post(
      Uri.parse('$n8nWebhookUrl/session/modify'),
      body: jsonEncode({
        'session_id': _sessionId,
        'current_step_index': _currentStepIndex,
        'issue_type': params['issue_type'],
        'details': params['details'],
        'affected_ingredient': params['affected_ingredient'],
        'remaining_steps': _getRemainingStepsJson(),
      }),
    );

    // 2. Parse structured operations from n8n
    final data = jsonDecode(response.body);
    final operations = data['operations'] as List;

    // 3. Apply each operation to Supabase
    for (final op in operations) {
      switch (op['operation']) {
        case 'insert':
          await _sessionService.insertStep(...);
          break;
        case 'adjust_quantity':
          await _sessionService.adjustIngredientAmount(...);
          break;
        case 'substitute':
          await _sessionService.substituteIngredient(...);
          break;
        case 'delete':
          await _sessionService.markStepSkipped(...);
          break;
      }
    }

    // 4. Refresh local state and return message for agent
    await _refreshSession();
    return jsonEncode({
      'success': true,
      'operations_applied': operations.length,
      'agent_message': data['agent_message'],
    });
  },
}
```

##### 2. get_cooking_state (CRITICAL)
Returns the complete current state of the cooking session. **The agent should call this first** at the start of every conversation and whenever it needs to know current progress.

```json
{
    "type": "client",
    "name": "get_cooking_state",
    "description": "Get the complete current state of the cooking session including current step, completed steps, active timers, and servings. ALWAYS call this at the start of the conversation and when you need to know where the user is.",
    "parameters": {
        "type": "object",
        "properties": {}
    },
    "response_timeout_secs": 2
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'get_cooking_state': (Map<String, dynamic> params) {
    return jsonEncode({
      'current_step_index': _currentStepIndex,
      'current_step': {
        'title': _steps[_currentStepIndex].shortText,
        'description': _steps[_currentStepIndex].detailedDescription,
      },
      'total_steps': _steps.length,
      'completed_steps': _completedSteps,
      'active_timers': _activeTimers.map((t) => {
        'label': t.label,
        'remaining_seconds': t.remainingSeconds,
      }).toList(),
      'current_servings': _currentServings,
      'is_first_step': _currentStepIndex == 0,
      'is_last_step': _currentStepIndex == _steps.length - 1,
    });
  },
}
```

##### 2. navigate_to_step
Controls UI navigation between cooking steps.

```json
{
    "type": "client",
    "name": "navigate_to_step",
    "description": "Navigate to a specific step in the cooking process. Use when user asks to go back, go forward, or jump to a specific step.",
    "parameters": {
        "type": "object",
        "properties": {
            "direction": {
                "type": "string",
                "enum": ["next", "previous", "specific"],
                "description": "Navigation direction"
            },
            "step_index": {
                "type": "integer",
                "description": "Target step index (only needed if direction is 'specific')"
            }
        },
        "required": ["direction"]
    },
    "response_timeout_secs": 2
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'navigate_to_step': (Map<String, dynamic> params) {
    final direction = params['direction'] as String;
    final stepIndex = params['step_index'] as int?;

    if (direction == 'next') {
      _goToNextStep();
      return 'Moved to next step';
    } else if (direction == 'previous') {
      _goToPreviousStep();
      return 'Moved to previous step';
    } else if (direction == 'specific' && stepIndex != null) {
      _goToStep(stepIndex);
      return 'Moved to step ${stepIndex + 1}';
    }
    return 'Invalid navigation request';
  },
}
```

##### 3. mark_step_complete
Marks current step as done and updates UI.

```json
{
    "type": "client",
    "name": "mark_step_complete",
    "description": "Mark the current step as completed. Use when user confirms they've finished the current step.",
    "parameters": {
        "type": "object",
        "properties": {
            "step_index": {
                "type": "integer",
                "description": "The step index to mark complete"
            }
        },
        "required": ["step_index"]
    },
    "response_timeout_secs": 2
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'mark_step_complete': (Map<String, dynamic> params) {
    final stepIndex = params['step_index'] as int;
    _markStepComplete(stepIndex);
    _updateDynamicVariable('current_step', stepIndex + 1);

    if (stepIndex + 1 >= _totalSteps) {
      return 'All steps completed! Dish is ready.';
    }
    return 'Step ${stepIndex + 1} marked complete. Moving to step ${stepIndex + 2}.';
  },
}
```

##### 4. get_ingredient_details
Retrieves ingredient info from current session.

```json
{
    "type": "client",
    "name": "get_ingredient_details",
    "description": "Get detailed information about a specific ingredient including exact amount and any preparation notes.",
    "parameters": {
        "type": "object",
        "properties": {
            "ingredient_name": {
                "type": "string",
                "description": "Name of the ingredient to look up"
            }
        },
        "required": ["ingredient_name"]
    },
    "response_timeout_secs": 2
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'get_ingredient_details': (Map<String, dynamic> params) {
    final name = params['ingredient_name'] as String;
    final ingredient = _findIngredient(name);

    if (ingredient != null) {
      return jsonEncode({
        'name': ingredient.name,
        'amount': ingredient.amount,
        'unit': ingredient.unit,
        'preparation': ingredient.comment,
      });
    }
    return 'Ingredient not found in this recipe.';
  },
}
```

##### 5. set_timer
Starts a timer on the device.

```json
{
    "type": "client",
    "name": "set_timer",
    "description": "Set a cooking timer. Use when a step requires waiting for a specific duration.",
    "parameters": {
        "type": "object",
        "properties": {
            "duration_seconds": {
                "type": "integer",
                "description": "Timer duration in seconds"
            },
            "label": {
                "type": "string",
                "description": "What the timer is for (e.g., 'simmer chili')"
            }
        },
        "required": ["duration_seconds", "label"]
    },
    "response_timeout_secs": 2
}
```

##### 6. get_current_step_details
Returns full details of current step.

```json
{
    "type": "client",
    "name": "get_current_step_details",
    "description": "Get complete details of the current step including ingredients and equipment needed.",
    "parameters": {
        "type": "object",
        "properties": {}
    },
    "response_timeout_secs": 2
}
```

##### 7. log_disaster (Optional - for Gordon Ramsay persona)
Records cooking mishaps for recovery tracking and learning.

```json
{
    "type": "client",
    "name": "log_disaster",
    "description": "Record what went wrong and how we recovered. Use when user reports a cooking mishap (burnt food, dropped ingredient, wrong measurement, etc.)",
    "parameters": {
        "type": "object",
        "properties": {
            "what_happened": {
                "type": "string",
                "description": "Brief description of the mishap"
            },
            "severity": {
                "type": "string",
                "enum": ["minor", "moderate", "major"],
                "description": "How bad was it? minor=easy fix, moderate=needs adjustment, major=start over"
            },
            "recovery_action": {
                "type": "string",
                "description": "What we did to fix or adapt"
            }
        },
        "required": ["what_happened", "severity", "recovery_action"]
    },
    "response_timeout_secs": 2
}
```

**Flutter Implementation:**
```dart
clientTools: {
  'log_disaster': (Map<String, dynamic> params) {
    final disaster = CookingDisaster(
      stepIndex: _currentStepIndex,
      whatHappened: params['what_happened'],
      severity: params['severity'],
      recoveryAction: params['recovery_action'],
      timestamp: DateTime.now(),
    );
    _sessionDisasters.add(disaster);

    // Could also send to analytics/backend
    return 'Logged: ${params['what_happened']} - Recovery: ${params['recovery_action']}';
  },
}
```

### System Tools

Enable these built-in ElevenLabs system tools:

```json
{
    "built_in_tools": [
        {
            "name": "end_call",
            "description": "End the cooking session when the user is done or wants to stop"
        },
        {
            "name": "skip_turn",
            "description": "When user needs a moment (e.g., 'hold on', 'just a sec', 'let me check')"
        }
    ]
}
```

### Voice Configuration

```json
{
    "tts": {
        "voice_id": "EXAVITQu4vr4xnSDxMaL",  // "Sarah" - warm, friendly female voice
        "model_id": "eleven_turbo_v2_5",
        "stability": 0.5,
        "similarity_boost": 0.75,
        "style": 0.3,
        "use_speaker_boost": true
    }
}
```

**Alternative Voice Options:**
- `21m00Tcm4TlvDq8ikWAM` - "Rachel" - calm, clear
- `pNInz6obpgDQGcFmaJgB` - "Adam" - warm male voice
- `ThT5KcBeYPX3keUQqHPh` - "Dorothy" - friendly, British accent

### Conversation Settings

```json
{
    "conversation": {
        "max_duration_seconds": 3600,  // 1 hour max session
        "silence_end_call_timeout_seconds": 300,  // End if silent for 5 minutes
        "max_tokens_per_response": 150,  // Keep responses concise for voice
        "temperature": 0.7,  // Balanced creativity
        "model": "gpt-4o"  // Or "claude-3-5-sonnet"
    }
}
```

### Full Agent Creation API Call

```bash
curl -X POST "https://api.elevenlabs.io/v1/convai/agents/create" \
  -H "xi-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Chef Mia - Mise en Place",
    "conversation_config": {
        "agent": {
            "prompt": {
                "prompt": "You are Chef Mia, a friendly and encouraging cooking assistant...",
                "llm": "gpt-4o",
                "temperature": 0.7,
                "max_tokens": 150,
                "tools": []
            },
            "first_message": "Hey {{user_name}}! I'\''m Chef Mia...",
            "language": "en"
        },
        "tts": {
            "voice_id": "EXAVITQu4vr4xnSDxMaL",
            "model_id": "eleven_turbo_v2_5"
        },
        "conversation": {
            "max_duration_seconds": 3600,
            "silence_end_call_timeout_seconds": 300
        }
    },
    "platform_settings": {
        "widget": {
            "avatar_image_url": "https://your-cdn.com/chef-mia-avatar.png",
            "color_scheme": {
                "primary": "#FF9800"
            }
        }
    }
}'
```

### Updating Dynamic Variables Mid-Conversation

When a step is completed or serving size changes, update the dynamic variables:

```dart
// After completing a step
conversation.updateDynamicVariables({
  'current_step': newStepIndex,
});

// After serving adjustment
conversation.updateDynamicVariables({
  'servings': newServings,
});
```

---

## References

- [ElevenLabs Dynamic Variables](https://elevenlabs.io/docs/agents-platform/customization/personalization)
- [ElevenLabs Tools Configuration](https://elevenlabs.io/docs/conversational-ai/customization/tools)
- [ElevenLabs Client Tools](https://elevenlabs.io/docs/conversational-ai/customization/tools/client-tools)
- [n8n AI Agent Documentation](https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain.agent/)
- [n8n Webhook Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)
