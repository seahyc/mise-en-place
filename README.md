# Mise en Place

An iPad Flutter app for voice-driven recipe guidance. Users browse recipes, select one or more to cook simultaneously, and enter a hands-free cooking mode powered by an ElevenLabs voice agent.

## What it does

1. **Browse Recipes** - Grid view of available recipes
2. **View Details** - Full recipe with ingredients, equipment, and step-by-step instructions
3. **Multi-Recipe Cooking** - Select multiple recipes to cook simultaneously
4. **Voice-Guided Cooking** - Hands-free mode where an AI agent guides you through each step, adapts to substitutions, and controls the UI via voice

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend/DB**: Supabase (PostgreSQL)
- **Workflow Orchestration**: n8n (merges multi-recipe instructions)
- **Voice AI**: ElevenLabs Conversational Agent
- **Image Generation**: OpenAI DALL-E + Cloudflare R2

---

## Architecture

### How It All Works Together

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Flutter App (iPad)                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐ │
│  │ Recipe List │→ │Recipe Detail│→ │Cooking Mode │← │ Real-time       │ │
│  │   Screen    │  │   Screen    │  │   Screen    │  │ Supabase Sync   │ │
│  └─────────────┘  └─────────────┘  └──────┬──────┘  └────────┬────────┘ │
└────────────────────────────────────────────┼─────────────────┼──────────┘
                                             │                 │
                    ┌────────────────────────┼─────────────────┘
                    │                        │
                    ▼                        ▼
┌──────────────────────────────┐  ┌─────────────────────────────────────┐
│     ElevenLabs Voice Agent   │  │              Supabase               │
│  ┌────────────────────────┐  │  │  ┌─────────────────────────────┐    │
│  │ Gordon Ramsay Persona  │  │  │  │ recipes, sessions, steps    │    │
│  │ (Claude Sonnet 4.5)    │  │  │  │ ingredients, equipment      │    │
│  └───────────┬────────────┘  │  │  └─────────────────────────────┘    │
│              │               │  └─────────────────────────────────────┘
│   Client Tools (→ Flutter)   │                    ▲
│   • mark_step_complete       │                    │
│   • navigate_to_step         │                    │
│   • manage_timer             │                    │
│   • get_cooking_state        │                    │
│   • switch_units             │                    │
│              │               │                    │
│   Webhook Tool (→ n8n)       │                    │
│   • modify_instructions ─────┼────────┐           │
└──────────────────────────────┘        │           │
                                        ▼           │
                              ┌─────────────────────┴───────────────────┐
                              │              n8n Workflows              │
                              │  ┌───────────────────────────────────┐  │
                              │  │ modify_instructions               │  │
                              │  │ • AI analyzes cooking issues      │  │
                              │  │ • Generates atomic DB operations  │  │
                              │  │ • Updates session_steps table     │  │
                              │  └───────────────────────────────────┘  │
                              │  ┌───────────────────────────────────┐  │
                              │  │ generate_image                    │  │
                              │  │ • DALL-E image generation         │  │
                              │  │ • Upload to Cloudflare R2         │  │
                              │  └───────────────────────────────────┘  │
                              └─────────────────────────────────────────┘
```

### Flow Example

1. **User starts cooking** → Flutter creates `CookingSession` in Supabase, connects to ElevenLabs agent
2. **Agent guides user** → Uses client tools (`mark_step_complete`, `manage_timer`) to control Flutter UI
3. **Something goes wrong** (burnt food, missing ingredient) → Agent calls `modify_instructions` webhook
4. **n8n processes** → AI analyzes issue, generates operations, updates Supabase
5. **Flutter sees changes** → Real-time subscription shows new/modified steps
6. **Images needed** → `generate_image` workflow creates step illustrations on-demand

---

## ElevenLabs Voice Agent

**Config location**: `prototype/elevenlabs/agent_config.json`

### Agent Personality

- **Name**: Gordon Ramsay
- **Model**: Claude Sonnet 4.5 (temperature 0.31)
- **Voice**: Custom ElevenLabs voice at 1.07x speed
- **Style**: Short, punchy. "Bloody hell" when frustrated, "Beautiful!" when they nail it.

### Dynamic Variables (passed at session start)

| Variable | Example | Description |
|----------|---------|-------------|
| `user_name` | "Chef" | User's name |
| `recipe_title` | "Pad Thai" | Current recipe |
| `total_steps` | "12" | Number of steps |
| `estimated_time` | "30 mins" | Cook time |
| `initial_servings` | "4" | Serving size |
| `experience_level` | "intermediate" | Adjusts verbosity |

### Client Tools (handled by Flutter)

| Tool | Description |
|------|-------------|
| `mark_step_complete` | Mark current step done, auto-advance to next |
| `navigate_to_step` | Go to next/previous/first/last/specific step |
| `get_cooking_state` | Get full session state (current step, timers, servings) |
| `get_full_recipe_details` | Get all ingredients, equipment, steps |
| `manage_timer` | Set/update/get/dismiss cooking timers with milestones |
| `switch_units` | Toggle metric ↔ imperial measurements |

### Webhook Tool (calls n8n)

| Tool | Description |
|------|-------------|
| `modify_instructions` | Adapts recipe when issues occur (burnt ingredient, missing item, portion change) |

### Managing the Agent

```bash
cd prototype/elevenlabs

# Pull latest config from ElevenLabs
./pull_agent.sh

# Edit agent_config.json...

# Push changes back
./push_agent.sh
```

---

## n8n Workflows

### 1. modify_instructions

**Purpose**: AI-powered recipe adaptation when something goes wrong mid-cook

**Trigger**: `POST /webhook/session/modify`

**Flow**:
```
Webhook
  → Fetch Session Steps (from Supabase)
  → Prepare Session Data (split completed/remaining)
  → AI Agent (Claude Sonnet 4.5)
      ├── Lookup Ingredients (tool)
      └── Lookup Equipment (tool)
  → Parse & Split Operations
  → Route by Operation
      ├── insert → Insert Step
      ├── adjust_quantity → Adjust Quantity
      ├── substitute_ingredient → Substitute Ingredient
      ├── substitute_equipment → Substitute Equipment
      ├── skip → Skip Step
      └── update → Update Step
  → Merge Results
  → Respond
```

**Supported Operations**:

| Operation | Use Case | Example |
|-----------|----------|---------|
| `insert` | Add recovery steps | "Clean wok" after burnt protein |
| `adjust_quantity` | Change amounts | Reduce chili for less spice |
| `substitute_ingredient` | Swap ingredients | White wine for red wine |
| `substitute_equipment` | Swap equipment | Pan instead of wok |
| `skip` | Skip optional steps | Skip garnish |
| `update` | Modify step text | Add clarification |

**Input Example**:
```json
{
  "session_id": "uuid",
  "issue_type": "burnt_ingredient",
  "details": "User burnt the chicken, need to start fresh",
  "affected_ingredient": "chicken breast"
}
```

**Output Example**:
```json
{
  "success": true,
  "operations_count": 2,
  "agent_message": "Right, let's start fresh. I've added cleanup and prep steps.",
  "time_impact_minutes": 5
}
```

### 2. generate_image

**Purpose**: Generate step illustrations via DALL-E and upload to R2

**Triggers**:
- Called by other workflows via `Execute Workflow Trigger`
- Direct webhook: `POST /webhook/generate-image`

**Flow**:
```
Trigger
  → OpenAI Generate Image (DALL-E 3, returns base64)
  → Prepare Upload (AWS SigV4 signing for R2)
  → Upload to R2
  → Build Response (public URL)
```

**Input**:
```json
{
  "prompt": "Watercolor illustration of dicing onions",
  "filename": "sessions/abc123/step_2.png",
  "options": { "model": "dall-e-3", "size": "1024x1024" }
}
```

**Output**:
```json
{
  "success": true,
  "url": "https://pub-xxx.r2.dev/sessions/abc123/step_2.png",
  "model_used": "dall-e-3",
  "revised_prompt": "..."
}
```

---

## Setup

### Prerequisites

- Flutter SDK ^3.5.4
- FVM (Flutter Version Manager) recommended

### Environment Variables

Copy `.env.example` to `.env` in the `prototype/` folder and fill in:

| Variable | Description | Where to get it |
|----------|-------------|-----------------|
| `SUPABASE_URL` | Supabase project URL | [Supabase Dashboard](https://supabase.com) → Project Settings → API |
| `SUPABASE_ANON_KEY` | Supabase anonymous/public key | Same location |
| `DB_CONNECTION_STRING` | PostgreSQL connection string (for Python scripts) | Supabase → Settings → Database |
| `ELEVENLABS_API_KEY` | ElevenLabs API key | [ElevenLabs](https://elevenlabs.io) → Profile → API Keys |
| `ELEVENLABS_AGENT_ID` | Your conversational agent ID | ElevenLabs → Agents → Your Agent |
| `SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_SECRET` | Google OAuth client secret | [Google Cloud Console](https://console.cloud.google.com) |
| `N8N_INSTANCE_URL` | Your n8n instance URL | Your n8n deployment |
| `N8N_MCP_SERVER_URL` | n8n MCP server endpoint | n8n settings |
| `N8N_API_KEY` | n8n API key | n8n → Settings → API |
| `OPENAI_API_KEY` | OpenAI API key (for n8n workflows) | [OpenAI](https://platform.openai.com/api-keys) |
| `R2_ACCOUNT_ID` | Cloudflare account ID | [Cloudflare Dashboard](https://dash.cloudflare.com) |
| `R2_BUCKET_NAME` | R2 bucket name | Cloudflare → R2 |
| `R2_ENDPOINT` | R2 S3-compatible endpoint | Cloudflare → R2 → Bucket Settings |
| `R2_ACCESS_KEY_ID` | R2 access key | Cloudflare → R2 → Manage R2 API Tokens |
| `R2_SECRET_ACCESS_KEY` | R2 secret key | Same location |
| `R2_API_TOKEN` | R2 API token | Same location |
| `R2_PUBLIC_URL` | Public URL for serving assets | Cloudflare → R2 → Public Access |

### Running the App

```bash
cd prototype
flutter pub get
flutter run -d "iPad Pro"  # or your device

# For web development with live logs:
FLUTTER_WEB_PORT=50000 FLUTTER_WEB_HOST=0.0.0.0 \
  fvm flutter run -d chrome --web-port=50000 \
  2>&1 | tee /tmp/prototype-web.log

# Live logs are at /tmp/prototype-web.log
```

### Database Seeding

```bash
cd prototype
source venv/bin/activate  # or create venv first
python scripts/seed_supabase.py
```

---

## Project Structure

```
mise-en-place/
└── prototype/
    ├── lib/               # Flutter app source
    │   ├── models/        # Data models (Recipe, Ingredient, etc.)
    │   ├── screens/       # UI screens
    │   ├── services/      # API services (Supabase, Auth, etc.)
    │   └── widgets/       # Reusable widgets
    ├── scripts/           # Python utilities for seeding, testing
    ├── n8n/               # n8n workflow definitions
    │   ├── workflows/     # JSON workflow exports
    │   ├── tests/         # Workflow test scripts
    │   └── docs/          # n8n reference docs
    ├── elevenlabs/        # Voice agent configuration
    │   ├── agent_config.json
    │   ├── pull_agent.sh
    │   └── push_agent.sh
    └── specs/             # Technical documentation
```
