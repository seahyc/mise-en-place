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
FLUTTER_WEB_PORT=50000 fvm flutter run -d chrome --web-port=50000
```

### Database Seeding

```bash
cd prototype
source venv/bin/activate  # or create venv first
python scripts/seed_supabase.py
```

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
    ├── elevenlabs/        # Voice agent configuration
    └── specs/             # Technical documentation
```
