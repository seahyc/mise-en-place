# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product Vision

**Mise en Place** is an iPad Flutter app for voice-driven recipe guidance. Users browse recipes, select one or more to cook simultaneously, and enter a hands-free cooking mode powered by an ElevenLabs voice agent. The agent guides users step-by-step, provides tips, adapts to real-time feedback (ingredient substitutions, equipment issues, serving adjustments), and controls the UI via tool calls.

### Core User Flow
1. **Recipe List** → Browse available recipes in a grid
2. **Recipe Detail** → View full recipe with ingredients, equipment, instructions
3. **Start Cooking** → "Add more recipes?" prompt for simultaneous cooking
4. **Cooking Session Setup** → Serving size adjustment, pantry/equipment stock check
5. **n8n Workflow** → Merges multi-recipe instructions using mise en place best practices, generates optimized instruction set
6. **Voice Agent Begins** → ElevenLabs agent loads knowledge base, briefs each step, waits for user confirmation, adapts dynamically

## Tech Stack

- **Frontend**: Flutter (Dart SDK ^3.5.4, iOS/iPad)
- **Backend/DB**: Supabase (PostgreSQL)
- **Workflow Orchestration**: n8n (HTTP webhooks for recipe merging, instruction optimization)
- **Voice AI**: ElevenLabs Conversational Agent (dynamic variables, tool calls)
- **State Management**: Provider

## Common Commands

```bash
flutter run                              # Run the app
flutter run -d "iPad Pro"                # Run on specific device
flutter pub get                          # Get dependencies
flutter analyze                          # Analyze code
flutter test                             # Run all tests
flutter test test/widget_test.dart       # Run single test

# Database seeding
source venv/bin/activate && python scripts/seed_supabase.py
```

## Development Workflow

User runs the app with live logs piped to a file:
```bash
FLUTTER_WEB_PORT=50000 FLUTTER_WEB_HOST=0.0.0.0 \
  fvm flutter run -d chrome --web-port=50000 \
  2>&1 | tee /tmp/prototype-web.log
```

**Live logs location**: `/tmp/prototype-web.log` - Claude can read this file to see real-time Flutter console output, errors, and debug prints.

## Architecture

### Data Models

**Recipe** (template, immutable):
- Metadata: id, title, description, main_image_url, source_link, base_pax (number of people), prep/cook times, cuisine
- `List<RecipeIngredient>`: Links to master ingredients with amount, unit, display_string, comment
- `List<EquipmentMaster>`: Links to master equipment
- `List<InstructionStep>`: Ordered steps, each with own ingredients/equipment subset

**IngredientMaster / EquipmentMaster**: Lookup tables with id, name, icon/image. User inventory tracks what they have.

**InstructionStep**:
- order_index, short_text (title), detailed_description (voice script base)
- media_url (image/video), estimated_duration
- step_ingredients, step_equipment (what's used in THIS step)

**CookingSession** (runtime, mutable):
- Generated from one or more recipes after n8n merging
- Independent instruction set that can be modified mid-session
- Tracks current step, completed steps, dynamic adjustments
- Pax multiplier (can change per-dish or globally)

**Unit System**:
- UnitType enum: mass (g, kg, oz, lb), volume (ml, L, tsp, tbsp, cup, fl oz), count (piece, clove, slice), misc (pinch, handful)
- Imperial ↔ metric conversion support

### Screen Flow
```
RecipeListScreen → RecipeDetailScreen → [Multi-recipe selection] →
CookingSessionSetup (pax, stock check) → CookingModeScreen (voice-driven)
```

### n8n Integration
- **Trigger**: HTTP webhook when user starts cooking (sends selected recipes, pax counts, user profile)
- **Process**: LLM chain merges instructions with mise en place principles—prep grouped, efficient ordering, parallel tasks
- **Output**: Optimized instruction set JSON loaded into ElevenLabs knowledge base via API

### ElevenLabs Voice Agent
- **Dynamic variables**: Recipe data, instruction set, user name, experience level
- **Agent tool calls**:
  - `getCurrentStep()`, `getStep(index)`, `getFullInstructionSet()`
  - `navigateToStep(index)` - UI control
  - `nextStep()`, `previousStep()` - UI control
  - `modifyInstructions(changes)` - Add/remove/adjust remaining steps
  - `adjustPax(multiplier, scope)` - Global, per-dish, or per-ingredient
- **Behavior**: Brief step, provide tips beyond displayed text, wait for user confirmation, adapt to feedback (burnt ingredient → add recovery steps, missing ingredient → substitute or reduce pax)

### Database Schema (Supabase)
```
ingredient_master (id, name, default_image_url)
equipment_master (id, name, icon_url)
recipes (id, title, description, main_image_url, source_link, base_pax, prep_time_minutes, cook_time_minutes, cuisine)
recipe_ingredients (recipe_id, ingredient_id, amount, unit, display_string, comment)
recipe_equipment (recipe_id, equipment_id)
instruction_steps (id, recipe_id, order_index, short_text, detailed_description, media_url, estimated_duration_sec)
user_pantry (user_id, ingredient_id, amount, unit)
user_equipment (user_id, equipment_id, has_item)
```

### Key Implementation Patterns
- `RecipeService._mapJsonToRecipe()` handles nested Supabase joins
- Instructions sorted by `order_index` on fetch
- `RecipeIngredient.scaled(factor)` for pax adjustments (needs smarter logic for non-linear scaling)
- Cuisine enum with fallback to `other`

## Environment Variables (.env)
```
SUPABASE_URL=
SUPABASE_ANON_KEY=
ELEVENLABS_AGENT_ID=
N8N_WEBHOOK_URL=  # (planned)
```

## Current Status (see specs/task_list.md)

**Completed**: Project setup, data models, Supabase integration, RecipeListScreen, RecipeDetailScreen, basic CookingModeScreen scaffold

**In Progress**: ElevenLabs SDK integration, CookingModeScreen voice interaction

**Upcoming**: Multi-recipe selection, n8n workflow integration, dynamic instruction modification, pantry/equipment inventory UI, intelligent pax scaling
