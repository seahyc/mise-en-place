import os
import psycopg2
from dotenv import load_dotenv
from urllib.parse import urlparse

# Load environment variables
load_dotenv()

# Database connection parameters
DB_CONNECTION_STRING = os.getenv('DB_CONNECTION_STRING')

# --- SQL STATEMENTS ---
DROP_TABLES_SQL = """
-- CookingSession tables (runtime)
DROP TABLE IF EXISTS session_modifications CASCADE;
DROP TABLE IF EXISTS session_step_ingredients CASCADE;
DROP TABLE IF EXISTS session_step_equipment CASCADE;
DROP TABLE IF EXISTS session_steps CASCADE;
DROP TABLE IF EXISTS cooking_sessions CASCADE;

-- Recipe tables (template)
DROP TABLE IF EXISTS step_ingredients CASCADE;
DROP TABLE IF EXISTS step_equipment CASCADE;
DROP TABLE IF EXISTS recipe_ingredients CASCADE;
DROP TABLE IF EXISTS recipe_equipment CASCADE;
DROP TABLE IF EXISTS instruction_steps CASCADE;
DROP TABLE IF EXISTS recipes CASCADE;

-- Master tables
DROP TABLE IF EXISTS ingredient_master CASCADE;
DROP TABLE IF EXISTS equipment_master CASCADE;
DROP TABLE IF EXISTS unit_master CASCADE;

-- User tables
DROP TABLE IF EXISTS user_pantry CASCADE;
DROP TABLE IF EXISTS user_equipment CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS reorder_session_steps(UUID) CASCADE;
DROP FUNCTION IF EXISTS trigger_reorder_session_steps() CASCADE;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS after_session_step_insert ON session_steps;
DROP TYPE IF EXISTS cuisine_enum;
DROP TYPE IF EXISTS session_status_enum;
"""

CREATE_TABLES_SQL = """
-- Enums
CREATE TYPE cuisine_enum AS ENUM ('thai', 'mexican', 'vegan', 'italian', 'western', 'asian', 'other');
CREATE TYPE session_status_enum AS ENUM ('setup', 'in_progress', 'paused', 'completed', 'abandoned');

-- Profiles linked to Supabase Auth
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- MASTER TABLES (shared lookups)
-- ============================================
CREATE TABLE ingredient_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    default_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE equipment_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    icon_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE unit_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    abbreviation TEXT,
    unit_type TEXT CHECK (unit_type IN ('mass', 'volume', 'count', 'misc'))
);

-- ============================================
-- RECIPE TABLES (immutable templates)
-- ============================================
CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    main_image_url TEXT,
    source_link TEXT,
    prep_time_minutes INTEGER DEFAULT 0,
    cook_time_minutes INTEGER DEFAULT 0,
    base_pax INTEGER DEFAULT 4,
    cuisine cuisine_enum DEFAULT 'other',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Recipe-level ingredients (full list for shopping/display)
CREATE TABLE recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    ingredient_id UUID NOT NULL REFERENCES ingredient_master(id),
    amount NUMERIC,
    unit_id UUID REFERENCES unit_master(id),
    display_string TEXT,
    comment TEXT,
    UNIQUE(recipe_id, ingredient_id)
);

-- Recipe-level equipment (full list)
CREATE TABLE recipe_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES equipment_master(id),
    UNIQUE(recipe_id, equipment_id)
);

-- Instruction steps with template text containing placeholders
-- e.g. "Bruise {{ing:lemongrass:amount}} {{ing:lemongrass:unit}} of {{ing:lemongrass}} and boil in {{eq:pot}}"
CREATE TABLE instruction_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    short_text TEXT,
    detailed_description TEXT,  -- Template with {{placeholders}}
    media_url TEXT,
    estimated_duration_sec INTEGER
);

-- Step-level ingredients (what THIS step uses)
CREATE TABLE step_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES instruction_steps(id) ON DELETE CASCADE,
    ingredient_id UUID NOT NULL REFERENCES ingredient_master(id),
    amount NUMERIC,
    unit_id UUID REFERENCES unit_master(id),
    placeholder_key TEXT,  -- e.g. "lemongrass" for {{ing:lemongrass}}
    UNIQUE(step_id, ingredient_id)
);

-- Step-level equipment (what THIS step uses)
CREATE TABLE step_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    step_id UUID NOT NULL REFERENCES instruction_steps(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES equipment_master(id),
    placeholder_key TEXT,  -- e.g. "pot" for {{eq:pot}}
    UNIQUE(step_id, equipment_id)
);

-- ============================================
-- COOKING SESSION TABLES (mutable runtime instances)
-- ============================================
CREATE TABLE cooking_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    status session_status_enum DEFAULT 'setup',
    pax_multiplier NUMERIC DEFAULT 1.0,  -- Global serving size multiplier
    current_step_index INTEGER DEFAULT 0,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    -- Store source recipe IDs for reference (can be multiple for merged sessions)
    source_recipe_ids UUID[] DEFAULT '{}'
);

-- Session steps (copied from recipe, can be modified by agent)
CREATE TABLE session_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    source_step_id UUID REFERENCES instruction_steps(id),  -- NULL if agent-created
    order_index INTEGER NOT NULL,
    short_text TEXT,
    detailed_description TEXT,  -- Can be modified from template
    media_url TEXT,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    is_skipped BOOLEAN DEFAULT FALSE,
    agent_notes TEXT  -- Notes added by agent during session
);

-- Session step ingredients (copied, can be modified - e.g. substitutions)
CREATE TABLE session_step_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_step_id UUID NOT NULL REFERENCES session_steps(id) ON DELETE CASCADE,
    ingredient_id UUID NOT NULL REFERENCES ingredient_master(id),
    original_amount NUMERIC,  -- From recipe (scaled by pax)
    adjusted_amount NUMERIC,  -- After agent modifications
    unit_id UUID REFERENCES unit_master(id),
    placeholder_key TEXT,
    is_substitution BOOLEAN DEFAULT FALSE,
    substitution_note TEXT,  -- e.g. "Using butter instead of ghee"
    UNIQUE(session_step_id, placeholder_key)
);

-- Session step equipment (copied, can be modified)
CREATE TABLE session_step_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_step_id UUID NOT NULL REFERENCES session_steps(id) ON DELETE CASCADE,
    equipment_id UUID NOT NULL REFERENCES equipment_master(id),
    placeholder_key TEXT,
    is_substitution BOOLEAN DEFAULT FALSE,
    substitution_note TEXT,
    UNIQUE(session_step_id, placeholder_key)
);

-- Session modifications (logs agent changes to instructions)
CREATE TABLE session_modifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    step_index INTEGER,  -- Which step was modified (NULL if session-level)
    modification_type TEXT NOT NULL,  -- 'substitute', 'skip', 'add_step', 'adjust_amount', etc.
    request_details JSONB,  -- User's original issue (e.g., {"issue": "burnt onions"})
    changes_made JSONB,  -- What was changed (e.g., {"action": "added step", "step_text": "..."})
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- USER INVENTORY TABLES
-- ============================================
CREATE TABLE user_pantry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    ingredient_id UUID REFERENCES ingredient_master(id),
    amount NUMERIC,
    unit_id UUID REFERENCES unit_master(id),
    expiry_date DATE
);

CREATE TABLE user_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    equipment_id UUID REFERENCES equipment_master(id),
    has_item BOOLEAN DEFAULT TRUE
);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE user_pantry ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE cooking_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_step_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_step_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_modifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_pantry_owner ON user_pantry
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY user_equipment_owner ON user_equipment
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY cooking_sessions_owner ON cooking_sessions
FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Session tables inherit access from parent session
CREATE POLICY session_steps_owner ON session_steps
FOR ALL USING (
    EXISTS (SELECT 1 FROM cooking_sessions cs WHERE cs.id = session_steps.session_id AND cs.user_id = auth.uid())
);

CREATE POLICY session_step_ingredients_owner ON session_step_ingredients
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM session_steps ss
        JOIN cooking_sessions cs ON cs.id = ss.session_id
        WHERE ss.id = session_step_ingredients.session_step_id AND cs.user_id = auth.uid()
    )
);

CREATE POLICY session_step_equipment_owner ON session_step_equipment
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM session_steps ss
        JOIN cooking_sessions cs ON cs.id = ss.session_id
        WHERE ss.id = session_step_equipment.session_step_id AND cs.user_id = auth.uid()
    )
);

CREATE POLICY session_modifications_owner ON session_modifications
FOR ALL USING (
    EXISTS (SELECT 1 FROM cooking_sessions cs WHERE cs.id = session_modifications.session_id AND cs.user_id = auth.uid())
);

-- Auto-create profile rows on signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id) VALUES (NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE PROCEDURE handle_new_user();

-- Reorder session steps after insert (fixes order_index gaps/duplicates)
CREATE OR REPLACE FUNCTION reorder_session_steps(p_session_id UUID)
RETURNS void AS $$
BEGIN
  WITH numbered AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY order_index, id) - 1 AS new_index
    FROM session_steps
    WHERE session_id = p_session_id
  )
  UPDATE session_steps ss
  SET order_index = n.new_index
  FROM numbered n
  WHERE ss.id = n.id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trigger_reorder_session_steps()
RETURNS TRIGGER AS $$
BEGIN
  -- First, shift all existing steps at or after the new step's position down by 1
  UPDATE session_steps
  SET order_index = order_index + 1
  WHERE session_id = NEW.session_id
    AND order_index >= NEW.order_index
    AND id != NEW.id;

  -- Then normalize to remove gaps
  PERFORM reorder_session_steps(NEW.session_id);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER after_session_step_insert
AFTER INSERT ON session_steps
FOR EACH ROW
EXECUTE FUNCTION trigger_reorder_session_steps();
"""

# --- DATA SEEDING ---
#
# ============================================================================
# INSTRUCTION TEMPLATE GRAMMAR (for n8n agent to generate)
# ============================================================================
#
# PLACEHOLDER SYNTAX:
#   {i:key}       → Ingredient name only (e.g., "onion")
#   {i:key:qty}   → Amount + unit + name (e.g., "2 tbsp olive oil")
#   {e:key}       → Equipment name (e.g., "wok")
#
# RULES FOR READABLE SENTENCES:
#   1. Use {i:key:qty} when introducing an ingredient for the first time in a step
#   2. Use {i:key} for subsequent references to the same ingredient
#   3. Always use {e:key} for equipment (no quantity needed)
#   4. Placeholder keys are lowercase with underscores (e.g., "olive_oil", "dutch_oven")
#
# GRAMMAR PATTERNS (agent should follow these):
#
#   Pattern 1: Add quantity to equipment
#     "Heat {i:oil:qty} in the {e:pan}"
#     → "Heat 2 tbsp olive oil in the pan"
#
#   Pattern 2: Simple action on ingredient
#     "Dice {i:onion} finely"
#     → "Dice onion finely"
#
#   Pattern 3: Multiple ingredients
#     "Add {i:garlic:qty} and {i:ginger:qty}"
#     → "Add 3 cloves garlic and 1 tbsp ginger"
#
#   Pattern 4: Reference previously introduced ingredient
#     "...until {i:onion} is translucent"
#     → "...until onion is translucent"
#
#   Pattern 5: Equipment-only action
#     "Bring the {e:pot} to a boil"
#     → "Bring the pot to a boil"
#
#   Pattern 6: Combining ingredients with equipment
#     "Toss {i:noodles} in the {e:wok} with {i:sauce:qty}"
#     → "Toss noodles in the wok with 3 tbsp sauce"
#
# STEP DATA STRUCTURE:
#   step_ingredients: list of (placeholder_key, ingredient_name, amount, unit)
#   step_equipment: list of (placeholder_key, equipment_name)
#
# ============================================================================

RECIPES_DATA = [
    {
        "title": "Vegan Chili",
        "description": "Hearty, spicy, and packed with beans",
        "main_image_url": "https://images.unsplash.com/photo-1550936831-46af2497cf61?q=80&w=1000&auto=format&fit=crop",
        "prep_time": 20, "cook_time": 90, "base_pax": 6, "cuisine": "mexican",
        "ingredients": [
            ("Olive Oil", 2, "tbsp"), ("Onion", 1, "large"), ("Garlic", 6, "clove"),
            ("Jalapeño", 2, "whole"), ("Tomato Paste", 2, "tbsp"), ("Chili Powder", 3, "tbsp"),
            ("Cumin", 1, "tbsp"), ("Smoked Paprika", 1.5, "tsp"), ("Kidney Beans", 2, "can"),
            ("Pinto Beans", 2, "can"), ("Crushed Tomatoes", 28, "oz"), ("Vegetable Broth", 2, "cup")
        ],
        "equipment": ["Dutch Oven", "Knife", "Cutting Board", "Wooden Spoon"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Dice {i:onion} (medium). Mince {i:garlic} and {i:jalapeno}. Measure spices ({i:chili_powder:qty}, {i:cumin:qty}, {i:paprika:qty}) into a small bowl. Open cans of {i:kidney_beans} and {i:tomatoes}. Rinse beans.",
                "step_ingredients": [
                    ("onion", "Onion", 1, "large"),
                    ("garlic", "Garlic", 6, "clove"),
                    ("jalapeno", "Jalapeño", 2, "whole"),
                    ("chili_powder", "Chili Powder", 3, "tbsp"),
                    ("cumin", "Cumin", 1, "tbsp"),
                    ("paprika", "Smoked Paprika", 1.5, "tsp"),
                    ("kidney_beans", "Kidney Beans", 2, "can"),
                    ("tomatoes", "Crushed Tomatoes", 28, "oz"),
                ],
                "step_equipment": [("knife", "Knife"), ("cutting_board", "Cutting Board")]
            },
            {
                "short": "Sauté Aromatics",
                "detail": "Heat {i:oil:qty} in the {e:dutch_oven} over medium heat. Sauté diced {i:onion} until translucent (5-7 mins). Add minced {i:garlic} and {i:jalapeno}, cook 1 min until fragrant.",
                "step_ingredients": [
                    ("oil", "Olive Oil", 2, "tbsp"),
                    ("onion", "Onion", 1, "large"),
                    ("garlic", "Garlic", 6, "clove"),
                    ("jalapeno", "Jalapeño", 2, "whole"),
                ],
                "step_equipment": [("dutch_oven", "Dutch Oven"), ("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Bloom Spices",
                "detail": "Stir in {i:tomato_paste:qty} and the spice mixture. Cook stirring constantly with {e:wooden_spoon} for 2 mins until spices darken.",
                "step_ingredients": [
                    ("tomato_paste", "Tomato Paste", 2, "tbsp"),
                ],
                "step_equipment": [("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Simmer",
                "detail": "Deglaze with a splash of {i:broth}. Add {i:tomatoes:qty}, rinsed {i:kidney_beans} and {i:pinto_beans}, and remaining {i:broth}. Stir well to combine.",
                "step_ingredients": [
                    ("broth", "Vegetable Broth", 2, "cup"),
                    ("tomatoes", "Crushed Tomatoes", 28, "oz"),
                    ("kidney_beans", "Kidney Beans", 2, "can"),
                    ("pinto_beans", "Pinto Beans", 2, "can"),
                ],
                "step_equipment": []
            },
            {
                "short": "Cook",
                "detail": "Bring to a boil in the {e:dutch_oven}, then reduce heat to low. Simmer uncovered for 45-60 mins until thickened.",
                "step_ingredients": [],
                "step_equipment": [("dutch_oven", "Dutch Oven")]
            },
            {
                "short": "Finish",
                "detail": "Season with salt to taste. Serve hot.",
                "step_ingredients": [],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Pad Thai",
        "description": "Classic stir-fried rice noodle dish",
        "main_image_url": "https://images.unsplash.com/photo-1559314809-0d155014e29e?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 30, "cook_time": 15, "base_pax": 4, "cuisine": "thai",
        "ingredients": [
            ("Rice Noodles", 8, "oz"), ("Shrimp or Tofu", 1, "lb"), ("Eggs", 2, "large"), 
            ("Bean Sprouts", 1.5, "cup"), ("Green Onions", 3, "stalk"), ("Peanuts", 0.25, "cup"),
            ("Fish Sauce", 3, "tbsp"), ("Brown Sugar", 3, "tbsp"), ("Rice Vinegar", 2, "tbsp"), 
            ("Tamarind Paste", 1, "tbsp")
        ],
        "equipment": ["Wok", "Bowl", "Whisk", "Knife"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Soak {i:noodles} in warm water for 30-40 mins until pliable. Whisk sauce ({i:fish_sauce:qty}, {i:tamarind:qty}, {i:brown_sugar:qty}, {i:rice_vinegar:qty}) in the {e:bowl}. Slice {i:green_onions} (whites/greens) with the {e:knife}. Roughly chop {i:peanuts}.",
                "step_ingredients": [
                    ("noodles", "Rice Noodles", 8, "oz"),
                    ("fish_sauce", "Fish Sauce", 3, "tbsp"),
                    ("tamarind", "Tamarind Paste", 1, "tbsp"),
                    ("brown_sugar", "Brown Sugar", 3, "tbsp"),
                    ("rice_vinegar", "Rice Vinegar", 2, "tbsp"),
                    ("green_onions", "Green Onions", 3, "stalk"),
                    ("peanuts", "Peanuts", 0.25, "cup")
                ],
                "step_equipment": [("bowl", "Bowl"), ("whisk", "Whisk"), ("knife", "Knife")]
            },
            {
                "short": "Sear Protein",
                "detail": "Heat a little oil in the {e:wok} over high heat. Sear {i:protein} 2 mins per side until browned, then remove.",
                "step_ingredients": [("protein", "Shrimp or Tofu", 1, "lb")],
                "step_equipment": [("wok", "Wok")]
            },
            {
                "short": "Aromatics",
                "detail": "Reduce heat to medium. Stir-fry the white parts of {i:green_onions} for 30 secs until fragrant.",
                "step_ingredients": [("green_onions", "Green Onions", 3, "stalk")],
                "step_equipment": [("wok", "Wok")]
            },
            {
                "short": "Cook Noodles",
                "detail": "Add drained {i:noodles} with a splash of water. Stir-fry until nearly dry, then pour in the sauce and cook until noodles are chewy and coated.",
                "step_ingredients": [
                    ("noodles", "Rice Noodles", 8, "oz"),
                    ("fish_sauce", "Fish Sauce", 3, "tbsp"),
                    ("tamarind", "Tamarind Paste", 1, "tbsp"),
                    ("brown_sugar", "Brown Sugar", 3, "tbsp"),
                    ("rice_vinegar", "Rice Vinegar", 2, "tbsp")
                ],
                "step_equipment": [("wok", "Wok")]
            },
            {
                "short": "Egg & Fillings",
                "detail": "Push noodles to one side. Crack {i:eggs} into the open space and scramble, then mix through the noodles. Add {i:bean_sprouts} and return {i:protein} to the pan; toss 1 min.",
                "step_ingredients": [
                    ("eggs", "Eggs", 2, "large"),
                    ("bean_sprouts", "Bean Sprouts", 1.5, "cup"),
                    ("protein", "Shrimp or Tofu", 1, "lb")
                ],
                "step_equipment": [("wok", "Wok")]
            },
            {
                "short": "Finish",
                "detail": "Plate noodles. Top with {i:peanuts} and green onion greens; serve with chili flakes or lime if desired.",
                "step_ingredients": [
                    ("peanuts", "Peanuts", 0.25, "cup"),
                    ("green_onions", "Green Onions", 3, "stalk")
                ],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Creamy Mushroom Risotto",
        "description": "Rich, creamy, and vegan italian classic.",
        "main_image_url": "https://images.unsplash.com/photo-1476124369491-e7addf5db371?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 15, "cook_time": 40, "base_pax": 4, "cuisine": "italian",
        "ingredients": [
            ("Vegetable Stock", 6, "cup"), ("Olive Oil", 2, "tbsp"), ("Butter", 4, "tbsp"),
            ("Mushrooms", 1, "lb"), ("Shallot", 1, "medium"), ("Arborio Rice", 1.5, "cup"),
            ("White Wine", 0.5, "cup"), ("Parmesan Cheese", 0.5, "cup"), ("Thyme", 1, "tsp")
        ],
        "equipment": ["Large Pot", "Saucepan", "Ladle", "Wooden Spoon"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Warm {i:vegetable_stock:qty} in a simmer in the {e:saucepan}. Slice {i:mushrooms}, mince {i:shallot}, and grate {i:parmesan_cheese}. Measure {i:arborio_rice:qty} and {i:white_wine:qty}.",
                "step_ingredients": [
                    ("vegetable_stock", "Vegetable Stock", 6, "cup"),
                    ("mushrooms", "Mushrooms", 1, "lb"),
                    ("shallot", "Shallot", 1, "medium"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup"),
                    ("arborio_rice", "Arborio Rice", 1.5, "cup"),
                    ("white_wine", "White Wine", 0.5, "cup")
                ],
                "step_equipment": [("saucepan", "Saucepan"), ("ladle", "Ladle"), ("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Sauté Mushrooms",
                "detail": "Heat {i:olive_oil:qty} and half the {i:butter:qty} in the {e:large_pot} over medium-high. Brown {i:mushrooms} in batches without crowding; season and set aside.",
                "step_ingredients": [
                    ("olive_oil", "Olive Oil", 2, "tbsp"),
                    ("butter", "Butter", 4, "tbsp"),
                    ("mushrooms", "Mushrooms", 1, "lb")
                ],
                "step_equipment": [("large_pot", "Large Pot"), ("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Toast Rice",
                "detail": "Lower heat to medium. Add remaining {i:butter} and {i:shallot}; cook 2 mins. Stir in {i:arborio_rice} and toast until edges turn translucent (about 2 mins).",
                "step_ingredients": [
                    ("butter", "Butter", 4, "tbsp"),
                    ("shallot", "Shallot", 1, "medium"),
                    ("arborio_rice", "Arborio Rice", 1.5, "cup")
                ],
                "step_equipment": [("large_pot", "Large Pot"), ("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Deglaze",
                "detail": "Pour in {i:white_wine:qty}; stir constantly until the wine is fully absorbed.",
                "step_ingredients": [("white_wine", "White Wine", 0.5, "cup")],
                "step_equipment": [("large_pot", "Large Pot"), ("wooden_spoon", "Wooden Spoon")]
            },
            {
                "short": "Risotto Method",
                "detail": "Add hot {i:vegetable_stock} one ladle at a time, stirring with the {e:wooden_spoon}. Wait until each ladle is nearly absorbed before adding the next (20-25 mins) until creamy with a slight bite.",
                "step_ingredients": [
                    ("vegetable_stock", "Vegetable Stock", 6, "cup"),
                    ("arborio_rice", "Arborio Rice", 1.5, "cup")
                ],
                "step_equipment": [("ladle", "Ladle"), ("wooden_spoon", "Wooden Spoon"), ("large_pot", "Large Pot")]
            },
            {
                "short": "Mantecatura",
                "detail": "Off heat, fold in browned {i:mushrooms}, {i:parmesan_cheese:qty}, and a pinch of {i:thyme}. Adjust seasoning.",
                "step_ingredients": [
                    ("mushrooms", "Mushrooms", 1, "lb"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup"),
                    ("thyme", "Thyme", 1, "tsp")
                ],
                "step_equipment": [("wooden_spoon", "Wooden Spoon")]
            }
        ]
    },
    {
        "title": "Quinoa Power Salad",
        "description": "Nutrient-packed salad with roasted sweet potato.",
        "main_image_url": "https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 15, "cook_time": 25, "base_pax": 2, "cuisine": "vegan",
        "ingredients": [
            ("Quinoa", 1, "cup"), ("Water", 2, "cup"), ("Sweet Potato", 1, "large"),
            ("Black Beans", 1, "can"), ("Avocado", 1, "whole"), ("Spinach", 2, "cup"),
            ("Lemon Juice", 2, "tbsp"), ("Olive Oil", 2, "tbsp")
        ],
        "equipment": ["Saucepan", "Baking Sheet", "Large Bowl", "Whisk"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Rinse {i:quinoa}. Cube {i:sweet_potato} (1cm). Rinse {i:black_beans}. Slice {i:avocado}. Whisk dressing ({i:lemon_juice:qty} + {i:olive_oil:qty} + salt) with the {e:whisk}.",
                "step_ingredients": [
                    ("quinoa", "Quinoa", 1, "cup"),
                    ("sweet_potato", "Sweet Potato", 1, "large"),
                    ("black_beans", "Black Beans", 1, "can"),
                    ("avocado", "Avocado", 1, "whole"),
                    ("lemon_juice", "Lemon Juice", 2, "tbsp"),
                    ("olive_oil", "Olive Oil", 2, "tbsp")
                ],
                "step_equipment": [("whisk", "Whisk")]
            },
            {
                "short": "Cook Quinoa",
                "detail": "Combine {i:quinoa:qty} and {i:water:qty} in the {e:saucepan}. Bring to a boil, cover, and simmer low for 15 mins. Rest 5 mins, then fluff.",
                "step_ingredients": [
                    ("quinoa", "Quinoa", 1, "cup"),
                    ("water", "Water", 2, "cup")
                ],
                "step_equipment": [("saucepan", "Saucepan")]
            },
            {
                "short": "Roast Potato",
                "detail": "Toss {i:sweet_potato} with a drizzle of {i:olive_oil} and salt on the {e:baking_sheet}. Roast at {temp:400F} for 25 mins until browned.",
                "step_ingredients": [
                    ("sweet_potato", "Sweet Potato", 1, "large"),
                    ("olive_oil", "Olive Oil", 2, "tbsp")
                ],
                "step_equipment": [("baking_sheet", "Baking Sheet")]
            },
            {
                "short": "Assemble",
                "detail": "In the {e:large_bowl}, combine fluffed {i:quinoa}, roasted {i:sweet_potato}, {i:black_beans}, {i:spinach}, and {i:avocado}.",
                "step_ingredients": [
                    ("quinoa", "Quinoa", 1, "cup"),
                    ("sweet_potato", "Sweet Potato", 1, "large"),
                    ("black_beans", "Black Beans", 1, "can"),
                    ("spinach", "Spinach", 2, "cup"),
                    ("avocado", "Avocado", 1, "whole")
                ],
                "step_equipment": [("large_bowl", "Large Bowl")]
            },
            {
                "short": "Toss",
                "detail": "Drizzle dressing over the salad and toss gently to coat.",
                "step_ingredients": [
                    ("lemon_juice", "Lemon Juice", 2, "tbsp"),
                    ("olive_oil", "Olive Oil", 2, "tbsp")
                ],
                "step_equipment": [("large_bowl", "Large Bowl"), ("whisk", "Whisk")]
            }
        ]
    },
    {
        "title": "Thai Green Curry",
        "description": "Spicy and aromatic coconut curry.",
        "main_image_url": "https://images.unsplash.com/photo-1668665772043-bdd32e348998?q=80&w=1000&auto=format&fit=crop",
        "prep_time": 20, "cook_time": 20, "base_pax": 4, "cuisine": "thai",
        "ingredients": [
            ("Coconut Milk", 1.75, "cup"), ("Green Curry Paste", 4, "tbsp"), ("Chicken Thighs", 1, "lb"),
            ("Bamboo Shoots", 1, "cup"), ("Red Bell Pepper", 1, "whole"), ("Thai Basil", 1, "cup"),
            ("Fish Sauce", 2, "tbsp"), ("Sugar", 1, "tbsp"), ("Lime Leaves", 4, "leaf")
        ],
        "equipment": ["Large Pot", "Knife", "Cutting Board"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Cut {i:chicken_thighs} into bite-sized pieces on the {e:cutting_board}. Slice {i:bamboo_shoots} and {i:red_bell_pepper}. Pick {i:thai_basil} leaves. Measure {i:green_curry_paste:qty} and {i:coconut_milk:qty}.",
                "step_ingredients": [
                    ("chicken_thighs", "Chicken Thighs", 1, "lb"),
                    ("bamboo_shoots", "Bamboo Shoots", 1, "cup"),
                    ("red_bell_pepper", "Red Bell Pepper", 1, "whole"),
                    ("thai_basil", "Thai Basil", 1, "cup"),
                    ("green_curry_paste", "Green Curry Paste", 4, "tbsp"),
                    ("coconut_milk", "Coconut Milk", 1.75, "cup")
                ],
                "step_equipment": [("knife", "Knife"), ("cutting_board", "Cutting Board")]
            },
            {
                "short": "Crack Coconut",
                "detail": "In the {e:large_pot}, boil about 3/4 cup of {i:coconut_milk} over medium until the oil separates (5-8 mins).",
                "step_ingredients": [("coconut_milk", "Coconut Milk", 1.75, "cup")],
                "step_equipment": [("large_pot", "Large Pot")]
            },
            {
                "short": "Fry Paste",
                "detail": "Stir in {i:green_curry_paste:qty}; fry for 2 mins until fragrant.",
                "step_ingredients": [("green_curry_paste", "Green Curry Paste", 4, "tbsp")],
                "step_equipment": [("large_pot", "Large Pot")]
            },
            {
                "short": "Cook Chicken",
                "detail": "Add {i:chicken_thighs}; stir to coat in the curry oil and cook until opaque.",
                "step_ingredients": [("chicken_thighs", "Chicken Thighs", 1, "lb")],
                "step_equipment": [("large_pot", "Large Pot")]
            },
            {
                "short": "Simmer",
                "detail": "Pour in remaining {i:coconut_milk}, {i:bamboo_shoots}, {i:lime_leaves}, and {i:sugar:qty}. Simmer gently for 10 mins.",
                "step_ingredients": [
                    ("coconut_milk", "Coconut Milk", 1.75, "cup"),
                    ("bamboo_shoots", "Bamboo Shoots", 1, "cup"),
                    ("lime_leaves", "Lime Leaves", 4, "leaf"),
                    ("sugar", "Sugar", 1, "tbsp")
                ],
                "step_equipment": [("large_pot", "Large Pot")]
            },
            {
                "short": "Season & Finish",
                "detail": "Stir in {i:fish_sauce:qty} and {i:red_bell_pepper}. Cook 1 min, then turn off heat and fold in {i:thai_basil}.",
                "step_ingredients": [
                    ("fish_sauce", "Fish Sauce", 2, "tbsp"),
                    ("red_bell_pepper", "Red Bell Pepper", 1, "whole"),
                    ("thai_basil", "Thai Basil", 1, "cup")
                ],
                "step_equipment": [("large_pot", "Large Pot")]
            }
        ]
    },
    {
        "title": "Tacos al Pastor",
        "description": "Marinated pork tacos with pineapple.",
        "main_image_url": "https://images.unsplash.com/photo-1551504734-5ee1c4a1479b?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 30, "cook_time": 20, "base_pax": 6, "cuisine": "mexican",
        "ingredients": [
            ("Pork Shoulder", 2, "lb"), ("Guajillo Chiles", 5, "whole"), ("Pineapple Juice", 1, "cup"),
            ("Achiote Paste", 2, "oz"), ("Garlic", 4, "clove"), ("Corn Tortillas", 12, "whole"),
            ("Fresh Pineapple", 1, "cup"), ("Onion", 1, "medium"), ("Cilantro", 1, "bunch")
        ],
        "equipment": ["Blender", "Skillet", "Knife", "Bowl"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Slice {i:pork_shoulder} thin. Stem and soak {i:guajillo_chiles} in hot water. Dice {i:fresh_pineapple} and {i:onion}; chop {i:cilantro} with the {e:knife}. Measure {i:pineapple_juice:qty} and {i:achiote_paste:qty}.",
                "step_ingredients": [
                    ("pork_shoulder", "Pork Shoulder", 2, "lb"),
                    ("guajillo_chiles", "Guajillo Chiles", 5, "whole"),
                    ("fresh_pineapple", "Fresh Pineapple", 1, "cup"),
                    ("onion", "Onion", 1, "medium"),
                    ("cilantro", "Cilantro", 1, "bunch"),
                    ("pineapple_juice", "Pineapple Juice", 1, "cup"),
                    ("achiote_paste", "Achiote Paste", 2, "oz")
                ],
                "step_equipment": [("knife", "Knife"), ("bowl", "Bowl")]
            },
            {
                "short": "Marinate",
                "detail": "Blend soaked {i:guajillo_chiles}, {i:pineapple_juice:qty}, {i:achiote_paste:qty}, and {i:garlic} in the {e:blender} until smooth. Toss {i:pork_shoulder} in marinade in the {e:bowl}; refrigerate 4+ hours.",
                "step_ingredients": [
                    ("guajillo_chiles", "Guajillo Chiles", 5, "whole"),
                    ("pineapple_juice", "Pineapple Juice", 1, "cup"),
                    ("achiote_paste", "Achiote Paste", 2, "oz"),
                    ("garlic", "Garlic", 4, "clove"),
                    ("pork_shoulder", "Pork Shoulder", 2, "lb")
                ],
                "step_equipment": [("blender", "Blender"), ("bowl", "Bowl")]
            },
            {
                "short": "Cook Pork",
                "detail": "Heat the {e:skillet} (or grill) on high. Sear marinated {i:pork_shoulder} in batches for 3-4 mins until charred; chop into bite-sized pieces.",
                "step_ingredients": [("pork_shoulder", "Pork Shoulder", 2, "lb")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Grill Pineapple",
                "detail": "Sear {i:fresh_pineapple} rings or chunks in the {e:skillet} until caramelized; chop.",
                "step_ingredients": [("fresh_pineapple", "Fresh Pineapple", 1, "cup")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Assemble",
                "detail": "Warm {i:corn_tortillas}. Fill with {i:pork_shoulder}, charred {i:fresh_pineapple}, diced {i:onion}, and {i:cilantro}.",
                "step_ingredients": [
                    ("corn_tortillas", "Corn Tortillas", 12, "whole"),
                    ("pork_shoulder", "Pork Shoulder", 2, "lb"),
                    ("fresh_pineapple", "Fresh Pineapple", 1, "cup"),
                    ("onion", "Onion", 1, "medium"),
                    ("cilantro", "Cilantro", 1, "bunch")
                ],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Spaghetti Carbonara",
        "description": "Authentic Roman pasta with egg and cheese sauce.",
        "main_image_url": "https://images.unsplash.com/photo-1612874742237-6526221588e3?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 10, "cook_time": 15, "base_pax": 4, "cuisine": "italian",
        "ingredients": [
            ("Spaghetti", 1, "lb"), ("Guanciale or Bacon", 4, "oz"), ("Eggs", 3, "large"),
            ("Pecorino Romano", 1, "cup"), ("Black Pepper", 1, "tbsp"), ("Salt", 1, "tsp")
        ],
        "equipment": ["Large Pot", "Skillet", "Bowl", "Whisk"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Finely grate {i:pecorino_romano:qty}. Whisk {i:eggs} with cheese and most of {i:black_pepper:qty} in the {e:bowl} until a thick paste forms. Slice {i:guanciale_or_bacon} into strips.",
                "step_ingredients": [
                    ("pecorino_romano", "Pecorino Romano", 1, "cup"),
                    ("eggs", "Eggs", 3, "large"),
                    ("black_pepper", "Black Pepper", 1, "tbsp"),
                    ("guanciale_or_bacon", "Guanciale or Bacon", 4, "oz")
                ],
                "step_equipment": [("bowl", "Bowl"), ("whisk", "Whisk")]
            },
            {
                "short": "Boil Water",
                "detail": "Boil salted water in the {e:large_pot}. Cook {i:spaghetti} until al dente; reserve 1 cup pasta water.",
                "step_ingredients": [
                    ("salt", "Salt", 1, "tsp"),
                    ("spaghetti", "Spaghetti", 1, "lb")
                ],
                "step_equipment": [("large_pot", "Large Pot")]
            },
            {
                "short": "Crisp Guanciale",
                "detail": "Cold-start {i:guanciale_or_bacon} in the {e:skillet}. Cook on medium until fat renders and pieces are crisp. Remove skillet from heat.",
                "step_ingredients": [("guanciale_or_bacon", "Guanciale or Bacon", 4, "oz")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Combine",
                "detail": "Transfer hot {i:spaghetti} to the {e:skillet} with rendered fat. Toss to coat.",
                "step_ingredients": [("spaghetti", "Spaghetti", 1, "lb")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Emulsify",
                "detail": "Off heat, add the egg-cheese paste and a splash of reserved water. Toss vigorously until creamy (add water as needed) and finish with remaining {i:black_pepper}. Do not scramble.",
                "step_ingredients": [
                    ("eggs", "Eggs", 3, "large"),
                    ("pecorino_romano", "Pecorino Romano", 1, "cup"),
                    ("black_pepper", "Black Pepper", 1, "tbsp")
                ],
                "step_equipment": [("skillet", "Skillet")]
            }
        ]
    },
    {
        "title": "Chicken Tikka Masala",
        "description": "Grilled chicken in a spicy tomato cream sauce.",
        "main_image_url": "https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 30, "cook_time": 40, "base_pax": 4, "cuisine": "asian",
        "ingredients": [
            ("Chicken Thighs", 1.5, "lb"), ("Yogurt", 1, "cup"), ("Garlic", 4, "clove"), ("Ginger", 1, "tbsp"),
            ("Tomato Puree", 1, "can"), ("Heavy Cream", 0.5, "cup"), ("Garam Masala", 2, "tbsp"),
            ("Cumin", 1, "tsp"), ("Coriander", 1, "tsp"), ("Turmeric", 1, "tsp"), ("Onion", 1, "medium")
        ],
        "equipment": ["Bowl", "Skillet", "Blender"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Cube {i:chicken_thighs}. Mince {i:garlic} and {i:ginger}. Slice {i:onion} thin. Measure spices ({i:garam_masala:qty}, {i:cumin:qty}, {i:coriander:qty}, {i:turmeric:qty}).",
                "step_ingredients": [
                    ("chicken_thighs", "Chicken Thighs", 1.5, "lb"),
                    ("garlic", "Garlic", 4, "clove"),
                    ("ginger", "Ginger", 1, "tbsp"),
                    ("onion", "Onion", 1, "medium"),
                    ("garam_masala", "Garam Masala", 2, "tbsp"),
                    ("cumin", "Cumin", 1, "tsp"),
                    ("coriander", "Coriander", 1, "tsp"),
                    ("turmeric", "Turmeric", 1, "tsp")
                ],
                "step_equipment": []
            },
            {
                "short": "Marinate",
                "detail": "In the {e:bowl}, mix {i:yogurt:qty} with half the spices. Coat {i:chicken_thighs} and rest 30 mins.",
                "step_ingredients": [
                    ("yogurt", "Yogurt", 1, "cup"),
                    ("garam_masala", "Garam Masala", 2, "tbsp"),
                    ("cumin", "Cumin", 1, "tsp"),
                    ("coriander", "Coriander", 1, "tsp"),
                    ("turmeric", "Turmeric", 1, "tsp"),
                    ("chicken_thighs", "Chicken Thighs", 1.5, "lb")
                ],
                "step_equipment": [("bowl", "Bowl")]
            },
            {
                "short": "Sear Chicken",
                "detail": "Heat oil in the {e:skillet}. Sear marinated {i:chicken_thighs} until browned (not cooked through). Remove.",
                "step_ingredients": [("chicken_thighs", "Chicken Thighs", 1.5, "lb")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Build Sauce",
                "detail": "In the same {e:skillet}, sauté {i:onion} until golden. Add remaining {i:garlic} and {i:ginger}; cook 1 min. Stir in leftover spices and {i:tomato_puree:qty}; simmer 10 mins.",
                "step_ingredients": [
                    ("onion", "Onion", 1, "medium"),
                    ("garlic", "Garlic", 4, "clove"),
                    ("ginger", "Ginger", 1, "tbsp"),
                    ("garam_masala", "Garam Masala", 2, "tbsp"),
                    ("cumin", "Cumin", 1, "tsp"),
                    ("coriander", "Coriander", 1, "tsp"),
                    ("turmeric", "Turmeric", 1, "tsp"),
                    ("tomato_puree", "Tomato Puree", 1, "can")
                ],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Simmer",
                "detail": "Stir in {i:heavy_cream:qty} and the browned {i:chicken_thighs}. Simmer 15 mins until tender; blend the sauce briefly with the {e:blender} if you want it smoother.",
                "step_ingredients": [
                    ("heavy_cream", "Heavy Cream", 0.5, "cup"),
                    ("chicken_thighs", "Chicken Thighs", 1.5, "lb")
                ],
                "step_equipment": [("skillet", "Skillet"), ("blender", "Blender")]
            }
        ]
    },
    {
        "title": "Classic Beef Burger",
        "description": "Juicy homemade beef patties with fresh toppings.",
        "main_image_url": "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 15, "cook_time": 10, "base_pax": 4, "cuisine": "western",
        "ingredients": [
            ("Beef Mince", 1, "lb"), ("Burger Buns", 4, "whole"), ("Lettuce", 4, "leaf"),
            ("Tomato", 1, "sliced"), ("Cheese", 4, "slice"), ("Onion", 1, "sliced"),
            ("Salt", 1, "tsp"), ("Pepper", 1, "tsp")
        ],
        "equipment": ["Grill or Skillet", "Spatula"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Slice {i:tomato} and {i:onion}. Wash {i:lettuce}. Form {i:beef_mince} into 4 patties with a thumbprint divot; season with {i:salt:qty} and {i:pepper:qty}.",
                "step_ingredients": [
                    ("tomato", "Tomato", 1, "sliced"),
                    ("onion", "Onion", 1, "sliced"),
                    ("lettuce", "Lettuce", 4, "leaf"),
                    ("beef_mince", "Beef Mince", 1, "lb"),
                    ("salt", "Salt", 1, "tsp"),
                    ("pepper", "Pepper", 1, "tsp")
                ],
                "step_equipment": []
            },
            {
                "short": "Toast Buns",
                "detail": "Toast cut sides of {i:burger_buns} on the {e:grill_or_skillet} until golden.",
                "step_ingredients": [("burger_buns", "Burger Buns", 4, "whole")],
                "step_equipment": [("grill_or_skillet", "Grill or Skillet")]
            },
            {
                "short": "Cook Patties",
                "detail": "Cook patties on the {e:grill_or_skillet} over high heat for about 3 mins per side. Melt {i:cheese} on top at the end.",
                "step_ingredients": [
                    ("beef_mince", "Beef Mince", 1, "lb"),
                    ("cheese", "Cheese", 4, "slice")
                ],
                "step_equipment": [("grill_or_skillet", "Grill or Skillet")]
            },
            {
                "short": "Assemble",
                "detail": "Layer {i:burger_buns}, sauce, {i:lettuce}, {i:tomato}, patty, {i:onion}, and top bun.",
                "step_ingredients": [
                    ("burger_buns", "Burger Buns", 4, "whole"),
                    ("lettuce", "Lettuce", 4, "leaf"),
                    ("tomato", "Tomato", 1, "sliced"),
                    ("onion", "Onion", 1, "sliced")
                ],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Chicken Caesar Salad",
        "description": "Crispy romaine, grilled chicken, and homemade dressing.",
        "main_image_url": "https://images.unsplash.com/photo-1550304943-4f24f54ddde9?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 20, "cook_time": 10, "base_pax": 4, "cuisine": "western",
        "ingredients": [
            ("Romaine Lettuce", 2, "head"), ("Chicken Breast", 2, "whole"), ("Parmesan Cheese", 0.5, "cup"),
            ("Croutons", 1, "cup"), ("Lemon Juice", 2, "tbsp"), ("Olive Oil", 0.5, "cup"),
            ("Garlic", 1, "clove"), ("Anchovy Paste", 1, "tsp"), ("Egg Yolk", 1, "large")
        ],
        "equipment": ["Bowl", "Whisk", "Grill Pan"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Mince {i:garlic} and mash with {i:anchovy_paste}. Tear and wash {i:romaine_lettuce}. Grate {i:parmesan_cheese}. Measure {i:croutons}.",
                "step_ingredients": [
                    ("garlic", "Garlic", 1, "clove"),
                    ("anchovy_paste", "Anchovy Paste", 1, "tsp"),
                    ("romaine_lettuce", "Romaine Lettuce", 2, "head"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup"),
                    ("croutons", "Croutons", 1, "cup")
                ],
                "step_equipment": []
            },
            {
                "short": "Make Dressing",
                "detail": "In the {e:bowl}, whisk {i:egg_yolk}, {i:lemon_juice:qty}, minced {i:garlic}, {i:anchovy_paste}, and a slow stream of {i:olive_oil:qty} until thick. Season.",
                "step_ingredients": [
                    ("egg_yolk", "Egg Yolk", 1, "large"),
                    ("lemon_juice", "Lemon Juice", 2, "tbsp"),
                    ("garlic", "Garlic", 1, "clove"),
                    ("anchovy_paste", "Anchovy Paste", 1, "tsp"),
                    ("olive_oil", "Olive Oil", 0.5, "cup")
                ],
                "step_equipment": [("bowl", "Bowl"), ("whisk", "Whisk")]
            },
            {
                "short": "Grill Chicken",
                "detail": "Season {i:chicken_breast}. Grill on the {e:grill_pan} for about 6 mins per side until cooked through. Rest, then slice.",
                "step_ingredients": [("chicken_breast", "Chicken Breast", 2, "whole")],
                "step_equipment": [("grill_pan", "Grill Pan")]
            },
            {
                "short": "Assemble",
                "detail": "Toss {i:romaine_lettuce} with dressing in the {e:bowl}. Top with sliced {i:chicken_breast}, {i:croutons}, and {i:parmesan_cheese}.",
                "step_ingredients": [
                    ("romaine_lettuce", "Romaine Lettuce", 2, "head"),
                    ("chicken_breast", "Chicken Breast", 2, "whole"),
                    ("croutons", "Croutons", 1, "cup"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup")
                ],
                "step_equipment": [("bowl", "Bowl")]
            }
        ]
    },
    {
        "title": "Japanese Ramen",
        "description": "Rich pork broth with noodles and soft egg.",
        "main_image_url": "https://images.unsplash.com/photo-1552611052-33e04de081de?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 20, "cook_time": 120, "base_pax": 2, "cuisine": "asian",
        "ingredients": [
            ("Ramen Noodles", 2, "pack"), ("Pork Belly", 0.5, "lb"), ("Chicken Stock", 4, "cup"),
            ("Soy Sauce", 2, "tbsp"), ("Miso Paste", 1, "tbsp"), ("Egg", 2, "whole"),
            ("Green Onions", 2, "stalk"), ("Nori", 1, "sheet")
        ],
        "equipment": ["Pot", "Pan"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Slice {i:pork_belly}. Slice {i:green_onions}. Soft boil {i:egg} for 6.5 mins, then peel. Cut {i:nori} into strips.",
                "step_ingredients": [
                    ("pork_belly", "Pork Belly", 0.5, "lb"),
                    ("green_onions", "Green Onions", 2, "stalk"),
                    ("egg", "Egg", 2, "whole"),
                    ("nori", "Nori", 1, "sheet")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Make Broth",
                "detail": "Simmer {i:chicken_stock:qty} in the {e:pot}. Season with {i:soy_sauce:qty} and whisk in {i:miso_paste:qty} until dissolved.",
                "step_ingredients": [
                    ("chicken_stock", "Chicken Stock", 4, "cup"),
                    ("soy_sauce", "Soy Sauce", 2, "tbsp"),
                    ("miso_paste", "Miso Paste", 1, "tbsp")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Crisp Pork",
                "detail": "Sear {i:pork_belly} in the {e:pan} until edges are crispy.",
                "step_ingredients": [("pork_belly", "Pork Belly", 0.5, "lb")],
                "step_equipment": [("pan", "Pan")]
            },
            {
                "short": "Cook Noodles",
                "detail": "Boil {i:ramen_noodles} in a separate {e:pot} until springy; drain well.",
                "step_ingredients": [("ramen_noodles", "Ramen Noodles", 2, "pack")],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Assemble",
                "detail": "Divide noodles into bowls. Ladle hot broth over. Top with {i:pork_belly}, halved {i:egg}, {i:green_onions}, and {i:nori}.",
                "step_ingredients": [
                    ("ramen_noodles", "Ramen Noodles", 2, "pack"),
                    ("pork_belly", "Pork Belly", 0.5, "lb"),
                    ("egg", "Egg", 2, "whole"),
                    ("green_onions", "Green Onions", 2, "stalk"),
                    ("nori", "Nori", 1, "sheet")
                ],
                "step_equipment": [("pot", "Pot")]
            }
        ]
    },
    {
        "title": "Chicken Enchiladas",
        "description": "Tortillas stuffed with chicken and cheese in red sauce.",
        "main_image_url": "https://images.unsplash.com/photo-1730878423239-0fd430bbac37?q=80&w=1000&auto=format&fit=crop",
        "prep_time": 20, "cook_time": 20, "base_pax": 4, "cuisine": "mexican",
        "ingredients": [
            ("Tortillas", 8, "whole"), ("Chicken Breast", 2, "cup"), ("Enchilada Sauce", 1, "can"),
            ("Cheese", 2, "cup"), ("Onion", 1, "small"), ("Cilantro", 0.25, "cup")
        ],
        "equipment": ["Baking Dish", "Oven"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Shred cooked {i:chicken_breast}. Dice {i:onion}. Grate {i:cheese}. Chop {i:cilantro}. Warm {i:enchilada_sauce}.",
                "step_ingredients": [
                    ("chicken_breast", "Chicken Breast", 2, "cup"),
                    ("onion", "Onion", 1, "small"),
                    ("cheese", "Cheese", 2, "cup"),
                    ("cilantro", "Cilantro", 0.25, "cup"),
                    ("enchilada_sauce", "Enchilada Sauce", 1, "can")
                ],
                "step_equipment": []
            },
            {
                "short": "Prep Filling",
                "detail": "Mix shredded {i:chicken_breast} with diced {i:onion} and 1 cup of {i:cheese}.",
                "step_ingredients": [
                    ("chicken_breast", "Chicken Breast", 2, "cup"),
                    ("onion", "Onion", 1, "small"),
                    ("cheese", "Cheese", 2, "cup")
                ],
                "step_equipment": []
            },
            {
                "short": "Roll",
                "detail": "Fill {i:tortillas} with the mixture, roll tightly, and place seam-down in the {e:baking_dish}.",
                "step_ingredients": [
                    ("tortillas", "Tortillas", 8, "whole"),
                    ("chicken_breast", "Chicken Breast", 2, "cup"),
                    ("cheese", "Cheese", 2, "cup"),
                    ("onion", "Onion", 1, "small")
                ],
                "step_equipment": [("baking_dish", "Baking Dish")]
            },
            {
                "short": "Bake",
                "detail": "Top with {i:enchilada_sauce:qty} and remaining {i:cheese}. Bake at {temp:375F} in the {e:oven} for 20 mins, then garnish with {i:cilantro}.",
                "step_ingredients": [
                    ("enchilada_sauce", "Enchilada Sauce", 1, "can"),
                    ("cheese", "Cheese", 2, "cup"),
                    ("cilantro", "Cilantro", 0.25, "cup")
                ],
                "step_equipment": [("oven", "Oven"), ("baking_dish", "Baking Dish")]
            }
        ]
    },
    {
        "title": "Vegetable Stir Fry",
        "description": "Quick, healthy mix of veggies in soy ginger sauce.",
        "main_image_url": "https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 15, "cook_time": 10, "base_pax": 4, "cuisine": "asian",
        "ingredients": [
            ("Broccoli", 1, "head"), ("Carrots", 2, "sliced"), ("Snap Peas", 1, "cup"),
            ("Bell Pepper", 1, "sliced"), ("Soy Sauce", 3, "tbsp"), ("Sesame Oil", 1, "tsp"),
            ("Ginger", 1, "tsp"), ("Garlic", 2, "clove")
        ],
        "equipment": ["Wok", "Knife"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Cut {i:broccoli} into florets and slice {i:carrots} and {i:bell_pepper} with the {e:knife}. Trim {i:snap_peas}. Mince {i:ginger} and {i:garlic}. Whisk sauce ({i:soy_sauce:qty} + {i:sesame_oil:qty}) together.",
                "step_ingredients": [
                    ("broccoli", "Broccoli", 1, "head"),
                    ("carrots", "Carrots", 2, "sliced"),
                    ("bell_pepper", "Bell Pepper", 1, "sliced"),
                    ("snap_peas", "Snap Peas", 1, "cup"),
                    ("ginger", "Ginger", 1, "tsp"),
                    ("garlic", "Garlic", 2, "clove"),
                    ("soy_sauce", "Soy Sauce", 3, "tbsp"),
                    ("sesame_oil", "Sesame Oil", 1, "tsp")
                ],
                "step_equipment": [("knife", "Knife")]
            },
            {
                "short": "Blanch",
                "detail": "Blanch {i:broccoli} and {i:carrots} in boiling water for 2 mins; drain well.",
                "step_ingredients": [
                    ("broccoli", "Broccoli", 1, "head"),
                    ("carrots", "Carrots", 2, "sliced")
                ],
                "step_equipment": []
            },
            {
                "short": "Wok Fry",
                "detail": "Heat oil in the {e:wok} on high. Stir-fry {i:bell_pepper} and {i:garlic} until fragrant, then add blanched veggies and {i:snap_peas}; toss 2 mins.",
                "step_ingredients": [
                    ("bell_pepper", "Bell Pepper", 1, "sliced"),
                    ("garlic", "Garlic", 2, "clove"),
                    ("broccoli", "Broccoli", 1, "head"),
                    ("carrots", "Carrots", 2, "sliced"),
                    ("snap_peas", "Snap Peas", 1, "cup")
                ],
                "step_equipment": [("wok", "Wok")]
            },
            {
                "short": "Sauce",
                "detail": "Pour in the sauce ({i:soy_sauce:qty} + {i:sesame_oil:qty} + minced {i:ginger}) and toss vigorously to glaze everything.",
                "step_ingredients": [
                    ("soy_sauce", "Soy Sauce", 3, "tbsp"),
                    ("sesame_oil", "Sesame Oil", 1, "tsp"),
                    ("ginger", "Ginger", 1, "tsp")
                ],
                "step_equipment": [("wok", "Wok")]
            }
        ]
    },
    {
        "title": "French Toast",
        "description": "Golden, custard-soaked brioche slices.",
        "main_image_url": "https://images.unsplash.com/photo-1484723091739-30a097e8f929?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 10, "cook_time": 10, "base_pax": 2, "cuisine": "western",
        "ingredients": [
            ("Brioche Bread", 4, "slice"), ("Eggs", 2, "large"), ("Milk", 0.5, "cup"),
            ("Cinnamon", 1, "tsp"), ("Vanilla Extract", 1, "tsp"), ("Butter", 1, "tbsp"),
            ("Maple Syrup", 2, "tbsp")
        ],
        "equipment": ["Skillet", "Whisk", "Bowl"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Whisk custard ({i:eggs}, {i:milk:qty}, {i:cinnamon:qty}, {i:vanilla_extract:qty}) in the {e:bowl}. Slice {i:brioche_bread} thick if needed.",
                "step_ingredients": [
                    ("eggs", "Eggs", 2, "large"),
                    ("milk", "Milk", 0.5, "cup"),
                    ("cinnamon", "Cinnamon", 1, "tsp"),
                    ("vanilla_extract", "Vanilla Extract", 1, "tsp"),
                    ("brioche_bread", "Brioche Bread", 4, "slice")
                ],
                "step_equipment": [("whisk", "Whisk"), ("bowl", "Bowl")]
            },
            {
                "short": "Dip",
                "detail": "Soak each slice for about 20 secs per side in the custard; let excess drip off.",
                "step_ingredients": [("brioche_bread", "Brioche Bread", 4, "slice")],
                "step_equipment": [("bowl", "Bowl")]
            },
            {
                "short": "Cook",
                "detail": "Melt {i:butter:qty} in the {e:skillet} over medium. Fry soaked bread 3-4 mins per side until golden brown.",
                "step_ingredients": [
                    ("butter", "Butter", 1, "tbsp"),
                    ("brioche_bread", "Brioche Bread", 4, "slice")
                ],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Serve",
                "detail": "Plate and drizzle with {i:maple_syrup:qty}.",
                "step_ingredients": [("maple_syrup", "Maple Syrup", 2, "tbsp")],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Margherita Pizza",
        "description": "Classic Neapolitan pizza with basil and mozzarella.",
        "main_image_url": "https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 60, "cook_time": 10, "base_pax": 2, "cuisine": "italian",
        "ingredients": [
            ("Pizza Dough", 1, "ball"), ("Tomato Sauce", 0.5, "cup"), ("Mozzarella", 4, "oz"),
            ("Basil", 0.25, "cup"), ("Olive Oil", 1, "tbsp")
        ],
        "equipment": ["Oven", "Pizza Stone"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Preheat the {e:oven} with {e:pizza_stone} to {temp:500F} for 45 mins. Tear {i:mozzarella}. Stretch {i:pizza_dough} on a floured peel.",
                "step_ingredients": [
                    ("mozzarella", "Mozzarella", 4, "oz"),
                    ("pizza_dough", "Pizza Dough", 1, "ball")
                ],
                "step_equipment": [("oven", "Oven"), ("pizza_stone", "Pizza Stone")]
            },
            {
                "short": "Top",
                "detail": "Spread a light layer of {i:tomato_sauce:qty} over the dough and scatter {i:mozzarella}.",
                "step_ingredients": [
                    ("tomato_sauce", "Tomato Sauce", 0.5, "cup"),
                    ("mozzarella", "Mozzarella", 4, "oz")
                ],
                "step_equipment": []
            },
            {
                "short": "Bake",
                "detail": "Slide onto the hot {e:pizza_stone}. Bake 7-9 mins until puffed and browned.",
                "step_ingredients": [],
                "step_equipment": [("pizza_stone", "Pizza Stone"), ("oven", "Oven")]
            },
            {
                "short": "Finish",
                "detail": "Top with {i:basil} and drizzle {i:olive_oil:qty} before slicing.",
                "step_ingredients": [
                    ("basil", "Basil", 0.25, "cup"),
                    ("olive_oil", "Olive Oil", 1, "tbsp")
                ],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Greek Salad",
        "description": "Fresh cucumber, tomato, and feta salad.",
        "main_image_url": "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 15, "cook_time": 0, "base_pax": 4, "cuisine": "western",
        "ingredients": [
            ("Cucumber", 1, "large"), ("Tomato", 2, "large"), ("Red Onion", 0.5, "medium"),
            ("Feta Cheese", 4, "oz"), ("Kalamata Olives", 0.5, "cup"), ("Olive Oil", 2, "tbsp"),
            ("Oregano", 1, "tsp")
        ],
        "equipment": ["Bowl", "Knife"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Dice {i:cucumber} and {i:tomato}. Thinly slice {i:red_onion} with the {e:knife}. Cube {i:feta_cheese}. Pit {i:kalamata_olives} if needed.",
                "step_ingredients": [
                    ("cucumber", "Cucumber", 1, "large"),
                    ("tomato", "Tomato", 2, "large"),
                    ("red_onion", "Red Onion", 0.5, "medium"),
                    ("feta_cheese", "Feta Cheese", 4, "oz"),
                    ("kalamata_olives", "Kalamata Olives", 0.5, "cup")
                ],
                "step_equipment": [("knife", "Knife")]
            },
            {
                "short": "Combine",
                "detail": "In the {e:bowl}, mix chopped veggies and {i:kalamata_olives}.",
                "step_ingredients": [
                    ("cucumber", "Cucumber", 1, "large"),
                    ("tomato", "Tomato", 2, "large"),
                    ("red_onion", "Red Onion", 0.5, "medium"),
                    ("kalamata_olives", "Kalamata Olives", 0.5, "cup")
                ],
                "step_equipment": [("bowl", "Bowl")]
            },
            {
                "short": "Dress",
                "detail": "Toss with {i:olive_oil:qty} and a pinch of salt. Sprinkle {i:oregano:qty}.",
                "step_ingredients": [
                    ("olive_oil", "Olive Oil", 2, "tbsp"),
                    ("oregano", "Oregano", 1, "tsp")
                ],
                "step_equipment": [("bowl", "Bowl")]
            },
            {
                "short": "Finish",
                "detail": "Top with {i:feta_cheese} chunks.",
                "step_ingredients": [("feta_cheese", "Feta Cheese", 4, "oz")],
                "step_equipment": [("bowl", "Bowl")]
            }
        ]
    },
    {
        "title": "Beef Stroganoff",
        "description": "Tender beef in creamy mushroom sauce over noodles.",
        "main_image_url": "https://images.unsplash.com/photo-1534939561126-855b8675edd7?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 20, "cook_time": 30, "base_pax": 4, "cuisine": "western",
        "ingredients": [
            ("Beef Steak", 1, "lb"), ("Mushrooms", 8, "oz"), ("Onion", 1, "chopped"),
            ("Beef Broth", 1, "cup"), ("Sour Cream", 0.5, "cup"), ("Egg Noodles", 8, "oz"),
            ("Flour", 1, "tbsp"), ("Butter", 2, "tbsp")
        ],
        "equipment": ["Skillet", "Pot"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Slice {i:beef_steak} into strips and pat dry. Slice {i:mushrooms} and dice {i:onion}. Measure {i:beef_broth:qty} and {i:sour_cream:qty}. Bring water for {i:egg_noodles} to a boil in the {e:pot}.",
                "step_ingredients": [
                    ("beef_steak", "Beef Steak", 1, "lb"),
                    ("mushrooms", "Mushrooms", 8, "oz"),
                    ("onion", "Onion", 1, "chopped"),
                    ("beef_broth", "Beef Broth", 1, "cup"),
                    ("sour_cream", "Sour Cream", 0.5, "cup"),
                    ("egg_noodles", "Egg Noodles", 8, "oz")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Sear Beef",
                "detail": "Sear {i:beef_steak} quickly in the {e:skillet} with half the {i:butter:qty} until rare; remove.",
                "step_ingredients": [
                    ("beef_steak", "Beef Steak", 1, "lb"),
                    ("butter", "Butter", 2, "tbsp")
                ],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Sauté Veg",
                "detail": "Add remaining {i:butter} to the {e:skillet}; cook {i:onion} and {i:mushrooms} until browned.",
                "step_ingredients": [
                    ("butter", "Butter", 2, "tbsp"),
                    ("onion", "Onion", 1, "chopped"),
                    ("mushrooms", "Mushrooms", 8, "oz")
                ],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Simmer",
                "detail": "Sprinkle in {i:flour:qty} and stir 30 secs. Pour in {i:beef_broth:qty}; simmer until thickened.",
                "step_ingredients": [
                    ("flour", "Flour", 1, "tbsp"),
                    ("beef_broth", "Beef Broth", 1, "cup")
                ],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Finish",
                "detail": "Turn heat low; stir in {i:sour_cream:qty} and the seared {i:beef_steak}. Serve over cooked {i:egg_noodles}.",
                "step_ingredients": [
                    ("sour_cream", "Sour Cream", 0.5, "cup"),
                    ("beef_steak", "Beef Steak", 1, "lb"),
                    ("egg_noodles", "Egg Noodles", 8, "oz")
                ],
                "step_equipment": [("skillet", "Skillet"), ("pot", "Pot")]
            }
        ]
    },
    {
        "title": "Tom Yum Soup",
        "description": "Hot and sour Thai soup with shrimp.",
        "main_image_url": "https://images.unsplash.com/photo-1628430043175-0e8820df47c3?q=80&w=1000&auto=format&fit=crop",
        "prep_time": 15, "cook_time": 15, "base_pax": 4, "cuisine": "thai",
        "ingredients": [
            ("Shrimp", 8, "oz"), ("Lemongrass", 2, "stalk"), ("Galangal", 1, "inch"),
            ("Kaffir Lime Leaves", 3, "leaf"), ("Mushrooms", 1, "cup"), ("Lime Juice", 2, "tbsp"),
            ("Fish Sauce", 2, "tbsp"), ("Thai Chili", 2, "whole")
        ],
        "equipment": ["Pot", "Knife"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Smash {i:lemongrass}, slice {i:galangal} and {i:thai_chili} with the {e:knife}. Tear {i:kaffir_lime_leaves}. Quarter {i:mushrooms}. Peel {i:shrimp}.",
                "step_ingredients": [
                    ("lemongrass", "Lemongrass", 2, "stalk"),
                    ("galangal", "Galangal", 1, "inch"),
                    ("thai_chili", "Thai Chili", 2, "whole"),
                    ("kaffir_lime_leaves", "Kaffir Lime Leaves", 3, "leaf"),
                    ("mushrooms", "Mushrooms", 1, "cup"),
                    ("shrimp", "Shrimp", 8, "oz")
                ],
                "step_equipment": [("knife", "Knife")]
            },
            {
                "short": "Broth",
                "detail": "Simmer aromatics ({i:lemongrass}, {i:galangal}, {i:kaffir_lime_leaves}) in the {e:pot} with water or stock for 5 mins.",
                "step_ingredients": [
                    ("lemongrass", "Lemongrass", 2, "stalk"),
                    ("galangal", "Galangal", 1, "inch"),
                    ("kaffir_lime_leaves", "Kaffir Lime Leaves", 3, "leaf")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Soup",
                "detail": "Add {i:mushrooms} and {i:fish_sauce:qty}; boil 2 mins.",
                "step_ingredients": [
                    ("mushrooms", "Mushrooms", 1, "cup"),
                    ("fish_sauce", "Fish Sauce", 2, "tbsp")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Finish",
                "detail": "Add {i:shrimp} and {i:thai_chili}; cook 2 mins until pink. Off heat, stir in {i:lime_juice:qty}.",
                "step_ingredients": [
                    ("shrimp", "Shrimp", 8, "oz"),
                    ("thai_chili", "Thai Chili", 2, "whole"),
                    ("lime_juice", "Lime Juice", 2, "tbsp")
                ],
                "step_equipment": [("pot", "Pot")]
            }
        ]
    },
    {
        "title": "Fish Tacos",
        "description": "Crispy fish with slaw in corn tortillas.",
        "main_image_url": "https://images.unsplash.com/photo-1604467715878-83e57e8bc129?q=80&w=1000&auto=format&fit=crop",
        "prep_time": 20, "cook_time": 10, "base_pax": 4, "cuisine": "mexican",
        "ingredients": [
            ("White Fish", 1, "lb"), ("Tortillas", 8, "whole"), ("Cabbage", 2, "cup"),
            ("Lime", 2, "whole"), ("Mayonnaise", 0.25, "cup"), ("Hot Sauce", 1, "tsp")
        ],
        "equipment": ["Skillet", "Bowl"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Cut {i:white_fish} into strips. Shred {i:cabbage}. Zest and juice {i:lime}. Mix slaw with {i:mayonnaise:qty} and half the lime juice in the {e:bowl}.",
                "step_ingredients": [
                    ("white_fish", "White Fish", 1, "lb"),
                    ("cabbage", "Cabbage", 2, "cup"),
                    ("lime", "Lime", 2, "whole"),
                    ("mayonnaise", "Mayonnaise", 0.25, "cup")
                ],
                "step_equipment": [("bowl", "Bowl")]
            },
            {
                "short": "Cook Fish",
                "detail": "Coat {i:white_fish} with spices and sear in the {e:skillet} for about 3 mins per side until flaky.",
                "step_ingredients": [("white_fish", "White Fish", 1, "lb")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Tortillas",
                "detail": "Warm or char {i:tortillas} in the dry {e:skillet}.",
                "step_ingredients": [("tortillas", "Tortillas", 8, "whole")],
                "step_equipment": [("skillet", "Skillet")]
            },
            {
                "short": "Assemble",
                "detail": "Fill tortillas with fish and slaw. Add a squeeze of remaining {i:lime} and {i:hot_sauce:qty}.",
                "step_ingredients": [
                    ("white_fish", "White Fish", 1, "lb"),
                    ("tortillas", "Tortillas", 8, "whole"),
                    ("lime", "Lime", 2, "whole"),
                    ("hot_sauce", "Hot Sauce", 1, "tsp"),
                    ("cabbage", "Cabbage", 2, "cup")
                ],
                "step_equipment": []
            }
        ]
    },
    {
        "title": "Pesto Pasta",
        "description": "Simple pasta tossed in fresh basil pesto.",
        "main_image_url": "https://images.unsplash.com/photo-1473093295043-cdd812d0e601?auto=format&fit=crop&w=1000&q=80",
        "prep_time": 10, "cook_time": 10, "base_pax": 4, "cuisine": "italian",
        "ingredients": [
            ("Pasta", 1, "lb"), ("Basil", 2, "cup"), ("Pine Nuts", 0.25, "cup"),
            ("Parmesan Cheese", 0.5, "cup"), ("Garlic", 2, "clove"), ("Olive Oil", 0.5, "cup")
        ],
        "equipment": ["Food Processor", "Pot"],
        "steps": [
            {
                "short": "Mise en Place",
                "detail": "Strip {i:basil} leaves. Toast {i:pine_nuts}. Grate {i:parmesan_cheese}. Peel {i:garlic}. Boil water in the {e:pot}.",
                "step_ingredients": [
                    ("basil", "Basil", 2, "cup"),
                    ("pine_nuts", "Pine Nuts", 0.25, "cup"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup"),
                    ("garlic", "Garlic", 2, "clove")
                ],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Blend Pesto",
                "detail": "Pulse {i:basil}, {i:pine_nuts}, {i:garlic}, and half the {i:olive_oil:qty} in the {e:food_processor}. Stir in {i:parmesan_cheese:qty}; season to taste.",
                "step_ingredients": [
                    ("basil", "Basil", 2, "cup"),
                    ("pine_nuts", "Pine Nuts", 0.25, "cup"),
                    ("garlic", "Garlic", 2, "clove"),
                    ("olive_oil", "Olive Oil", 0.5, "cup"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup")
                ],
                "step_equipment": [("food_processor", "Food Processor")]
            },
            {
                "short": "Cook Pasta",
                "detail": "Boil {i:pasta:qty} until al dente; reserve a cup of cooking water and drain.",
                "step_ingredients": [("pasta", "Pasta", 1, "lb")],
                "step_equipment": [("pot", "Pot")]
            },
            {
                "short": "Combine",
                "detail": "Toss hot {i:pasta} with pesto, remaining {i:olive_oil}, and splashes of pasta water until glossy and creamy.",
                "step_ingredients": [
                    ("pasta", "Pasta", 1, "lb"),
                    ("olive_oil", "Olive Oil", 0.5, "cup"),
                    ("parmesan_cheese", "Parmesan Cheese", 0.5, "cup")
                ],
                "step_equipment": [("pot", "Pot")]
            }
        ]
    }
]

def seed_database():
    if not DB_CONNECTION_STRING:
        print("❌ DB_CONNECTION_STRING not set in .env")
        return

    result = urlparse(DB_CONNECTION_STRING)
    # Prefer the port from the connection string; fall back to Supabase default (5432)
    port = result.port or 5432
    host = result.hostname

    print(f"Connecting to Supabase at {host}:{port}...")
    try:
        conn = psycopg2.connect(
            dbname=result.path[1:],
            user=result.username,
            password=result.password,
            host=host,
            port=port,
            connect_timeout=20,
            sslmode='require'
        )
        conn.autocommit = True
        cursor = conn.cursor()
        print("✅ Connected to database.")

        print("Creating Schema...")
        cursor.execute(DROP_TABLES_SQL)
        
        # Modify CREATE_TABLES_SQL to include image_url
        MODIFIED_CREATE_TABLES_SQL = CREATE_TABLES_SQL.replace(
            "default_image_url TEXT,", 
            "default_image_url TEXT,\n    image_url TEXT,"
        ).replace(
            "icon_url TEXT,", 
            "icon_url TEXT,\n    image_url TEXT,"
        )
        
        cursor.execute(MODIFIED_CREATE_TABLES_SQL)
        print("✅ Schema Created.")

        def get_icon_url(name):
            n = name.lower()
            base_url = "https://img.icons8.com/fluency/48"
            
            # IMPORTANT: Order matters! More specific matches first, then general ones
            mapping = {
                # Equipment - MUST come before ingredients to avoid conflicts
                'saucepan': 'frying-pan',  # Must be before 'sauce'
                'dutch oven': 'cooking-pot',
                'food processor': 'food-processor',
                'cutting board': 'cutting-board',
                'baking sheet': 'baking-tray',
                'baking dish': 'baking-tray',
                'pizza stone': 'pizza',
                'wok': 'frying-pan',
                'pan': 'frying-pan',
                'skillet': 'frying-pan',
                'pot': 'cooking-pot',
                'oven': 'oven',
                'stove': 'stove',
                'knife': 'kitchen-knife',
                'spoon': 'spoon',
                'ladle': 'soup-ladle',
                'spatula': 'spatula',
                'blender': 'blender',
                'bowl': 'salad-bowl',
                'whisk': 'whisk',
                'tongs': 'tongs',
                'grill': 'barbecue',
                
                # Ingredients
                'chicken': 'chicken',
                'pork': 'steak',
                'beef': 'steak',
                'meat': 'steak',
                'onion': 'onion',
                'garlic': 'garlic',
                'ginger': 'ginger',
                'pepper': 'paprika',
                'chili': 'chili-pepper',
                'jalapeño': 'chili-pepper',
                'rice': 'rice-bowl',
                'quinoa': 'rice-bowl',
                'noodles': 'noodles',
                'pasta': 'spaghetti',
                'oil': 'olive-oil',
                'sauce': 'soy-sauce',  # Now after 'saucepan'
                'milk': 'milk-bottle',
                'wine': 'wine-bottle',
                'egg': 'egg',
                'eggs': 'eggs',
                'flour': 'flour',
                'sugar': 'sugar',
                'salt': 'salt-shaker',
                'bean': 'beans',
                'beans': 'beans',
                'lentil': 'beans',
                'lemon': 'citrus',
                'lime': 'citrus',
                'orange': 'citrus',
                'pineapple': 'pineapple',
                'tomato': 'tomato',
                'potato': 'potato',
                'avocado': 'avocado',
                'mushroom': 'mushroom',
                'spinach': 'spinach',
                'basil': 'basil',
                'cilantro': 'parsley',
                'parsley': 'parsley',
                'tortilla': 'taco',
                'cheese': 'cheese',
                'butter': 'butter',
                'shrimp': 'prawn',
                'fish': 'whole-fish',
                'tamarind': 'tamarind',
            }
            
            # 1. Exact or partial match from mapping (order matters!)
            for key, val in mapping.items():
                if key in n:
                    return f"{base_url}/{val}.png"
            
            # 2. General Fallbacks
            if 'leaf' in n or 'leaves' in n: return f"{base_url}/spinach.png"
            if 'bread' in n: return f"{base_url}/bread.png"
            if 'nut' in n or 'peanut' in n: return f"{base_url}/peanuts.png"
            
            return f"{base_url}/ingredients.png" # Generic Fallback

        def get_real_image_url(name, is_equipment=False):
            n = name.lower()
            
            # High quality Unsplash images
            if is_equipment:
                mapping = {
                    'wok': 'https://images.unsplash.com/photo-1515543237350-b3eea1ec8082?auto=format&fit=crop&w=500&q=80',
                    'pan': 'https://images.unsplash.com/photo-1595257841889-cb256b9c9519?auto=format&fit=crop&w=500&q=80',
                    'skillet': 'https://images.unsplash.com/photo-1595257841889-cb256b9c9519?auto=format&fit=crop&w=500&q=80',
                    'pot': 'https://images.unsplash.com/photo-1544030288-e6e6108867f6?auto=format&fit=crop&w=500&q=80',
                    'oven': 'https://images.unsplash.com/photo-1584622050111-993a426fbf0a?auto=format&fit=crop&w=500&q=80',
                    'knife': 'https://images.unsplash.com/photo-1593618998160-e34014e67546?auto=format&fit=crop&w=500&q=80',
                    'spoon': 'https://images.unsplash.com/photo-1619360142632-468dd57ec419?auto=format&fit=crop&w=500&q=80',
                    'ladle': 'https://images.unsplash.com/photo-1619360142632-468dd57ec419?auto=format&fit=crop&w=500&q=80',
                    'spatula': 'https://images.unsplash.com/photo-1599818816480-1588647acae0?auto=format&fit=crop&w=500&q=80',
                    'blender': 'https://images.unsplash.com/photo-1570222094114-28a9d88a27e6?auto=format&fit=crop&w=500&q=80',
                    'bowl': 'https://images.unsplash.com/photo-1567160352520-222bf6829707?auto=format&fit=crop&w=500&q=80',
                    'whisk': 'https://images.unsplash.com/photo-1599818816480-1588647acae0?auto=format&fit=crop&w=500&q=80',
                    'cutting board': 'https://images.unsplash.com/photo-1576489922094-2cfe89fb1733?auto=format&fit=crop&w=500&q=80',
                    'baking sheet': 'https://images.unsplash.com/photo-1565538810643-b5bdb714032a?auto=format&fit=crop&w=500&q=80',
                    'baking dish': 'https://images.unsplash.com/photo-1565538810643-b5bdb714032a?auto=format&fit=crop&w=500&q=80',
                    'food processor': 'https://images.unsplash.com/photo-1570222094114-28a9d88a27e6?auto=format&fit=crop&w=500&q=80',
                    'pizza stone': 'https://images.unsplash.com/photo-1593504049359-74330189a345?auto=format&fit=crop&w=500&q=80',
                    'grill': 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=500&q=80',
                }
            else:
                 mapping = {
                    # Proteins
                    'chicken': 'https://images.unsplash.com/photo-1587593810167-a84920ea0781?auto=format&fit=crop&w=500&q=80',
                    'pork': 'https://images.unsplash.com/photo-1602498456745-e9503b30470b?auto=format&fit=crop&w=500&q=80',
                    'beef': 'https://images.unsplash.com/photo-1603048297172-c92544798d5e?auto=format&fit=crop&w=500&q=80',
                    'shrimp': 'https://images.unsplash.com/photo-1565680018434-b51fae1b3b12?auto=format&fit=crop&w=500&q=80',
                    'fish': 'https://images.unsplash.com/photo-1535035048206-8178d8a7bc7d?auto=format&fit=crop&w=500&q=80',
                    'guanciale': 'https://images.unsplash.com/photo-1602498456745-e9503b30470b?auto=format&fit=crop&w=500&q=80',
                    'bacon': 'https://images.unsplash.com/photo-1528607929212-2636ec44253e?auto=format&fit=crop&w=500&q=80',
                    
                    # Vegetables
                    'onion': 'https://images.unsplash.com/photo-1508747703725-719777637510?auto=format&fit=crop&w=500&q=80',
                    'garlic': 'https://images.unsplash.com/photo-1615477969851-4f811559196b?auto=format&fit=crop&w=500&q=80',
                    'ginger': 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=500&q=80',
                    'shallot': 'https://images.unsplash.com/photo-1580201092675-a0a6a6cafbb1?auto=format&fit=crop&w=500&q=80',
                    'tomato': 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=500&q=80',
                    'potato': 'https://images.unsplash.com/photo-1518977676601-b53f82aba655?auto=format&fit=crop&w=500&q=80',
                    'mushroom': 'https://images.unsplash.com/photo-1504442656360-ec18c7ea017b?auto=format&fit=crop&w=500&q=80',
                    'cucumber': 'https://images.unsplash.com/photo-1449300079323-02e209d9d3a6?auto=format&fit=crop&w=500&q=80',
                    'broccoli': 'https://images.unsplash.com/photo-1583663848850-46af132dc08e?auto=format&fit=crop&w=500&q=80',
                    'carrot': 'https://images.unsplash.com/photo-1598170845058-32b9d6a5da37?auto=format&fit=crop&w=500&q=80',
                    'cabbage': 'https://images.unsplash.com/photo-1594282486552-05b4d80fbb9f?auto=format&fit=crop&w=500&q=80',
                    'lettuce': 'https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?auto=format&fit=crop&w=500&q=80',
                    'romaine': 'https://images.unsplash.com/photo-1622206151226-18ca2c9ab4a1?auto=format&fit=crop&w=500&q=80',
                    'bamboo': 'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?auto=format&fit=crop&w=500&q=80',
                    
                    # Peppers & Spices
                    'pepper': 'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=500&q=80',
                    'chili': 'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=500&q=80',
                    'jalapeño': 'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=500&q=80',
                    'jalapeno': 'https://images.unsplash.com/photo-1563729784474-d77dbb933a9e?auto=format&fit=crop&w=500&q=80',
                    'guajillo': 'https://images.unsplash.com/photo-1583663848850-46af132dc08e?auto=format&fit=crop&w=500&q=80',
                    'cumin': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'coriander': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'turmeric': 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=500&q=80',
                    'paprika': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'cinnamon': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'garam masala': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'oregano': 'https://images.unsplash.com/photo-1628104889506-c875150d8a56?auto=format&fit=crop&w=500&q=80',
                    'thyme': 'https://images.unsplash.com/photo-1628104889506-c875150d8a56?auto=format&fit=crop&w=500&q=80',
                    'galangal': 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=500&q=80',
                    
                    # Grains & Pasta
                    'rice': 'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=500&q=80',
                    'quinoa': 'https://images.unsplash.com/photo-1586201375761-83865001e31c?auto=format&fit=crop&w=500&q=80',
                    'noodles': 'https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=500&q=80',
                    'pasta': 'https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=500&q=80',
                    'spaghetti': 'https://images.unsplash.com/photo-1612929633738-8fe44f7ec841?auto=format&fit=crop&w=500&q=80',
                    
                    # Oils & Liquids
                    'oil': 'https://images.unsplash.com/photo-1474979266404-7cadd259c308?auto=format&fit=crop&w=500&q=80',
                    'sauce': 'https://images.unsplash.com/photo-1472476443507-c7a392dd12c7?auto=format&fit=crop&w=500&q=80',
                    'milk': 'https://images.unsplash.com/photo-1563636619-e91b29a27c0f?auto=format&fit=crop&w=500&q=80',
                    'cream': 'https://images.unsplash.com/photo-1563636619-e91b29a27c0f?auto=format&fit=crop&w=500&q=80',
                    'yogurt': 'https://images.unsplash.com/photo-1563636619-e91b29a27c0f?auto=format&fit=crop&w=500&q=80',
                    'broth': 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=500&q=80',
                    'stock': 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=500&q=80',
                    'wine': 'https://images.unsplash.com/photo-1510812431401-41d2bd2722f3?auto=format&fit=crop&w=500&q=80',
                    'water': 'https://images.unsplash.com/photo-1548839140-29a749e1cf4d?auto=format&fit=crop&w=500&q=80',
                    'juice': 'https://images.unsplash.com/photo-1600271886742-f049cd451bba?auto=format&fit=crop&w=500&q=80',
                    'syrup': 'https://images.unsplash.com/photo-1571684342734-3ba8e5c5e6e3?auto=format&fit=crop&w=500&q=80',
                    'vanilla': 'https://images.unsplash.com/photo-1596040033229-a0b4e27c7d0d?auto=format&fit=crop&w=500&q=80',
                    'mayonnaise': 'https://images.unsplash.com/photo-1615485290382-441e4d049cb5?auto=format&fit=crop&w=500&q=80',
                    
                    # Dairy & Eggs
                    'egg': 'https://images.unsplash.com/photo-1506976785307-8732e854ad03?auto=format&fit=crop&w=500&q=80',
                    'cheese': 'https://images.unsplash.com/photo-1614279532889-13ae53f86e33?auto=format&fit=crop&w=500&q=80',
                    'mozzarella': 'https://images.unsplash.com/photo-1614279532889-13ae53f86e33?auto=format&fit=crop&w=500&q=80',
                    'pecorino': 'https://images.unsplash.com/photo-1614279532889-13ae53f86e33?auto=format&fit=crop&w=500&q=80',
                    'butter': 'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?auto=format&fit=crop&w=500&q=80',
                    
                    # Baking & Basics
                    'flour': 'https://images.unsplash.com/photo-1597653241551-789f2134db3e?auto=format&fit=crop&w=500&q=80',
                    'sugar': 'https://images.unsplash.com/photo-1612056250785-5b8d217983ea?auto=format&fit=crop&w=500&q=80',
                    'salt': 'https://images.unsplash.com/photo-1612056250785-5b8d217983ea?auto=format&fit=crop&w=500&q=80',
                    'dough': 'https://images.unsplash.com/photo-1555507036-ab1f4038808a?auto=format&fit=crop&w=500&q=80',
                    
                    # Beans & Legumes
                    'bean': 'https://images.unsplash.com/photo-1551462147-37885acc25f1?auto=format&fit=crop&w=500&q=80',
                    'snap pea': 'https://images.unsplash.com/photo-1567375698509-ac363013b631?auto=format&fit=crop&w=500&q=80',
                    
                    # Fruits
                    'avocado': 'https://images.unsplash.com/photo-1523049673856-42868ac69dc2?auto=format&fit=crop&w=500&q=80',
                    'lemon': 'https://images.unsplash.com/photo-1590502593747-42a996133562?auto=format&fit=crop&w=500&q=80',
                    'lime': 'https://images.unsplash.com/photo-1594315264875-c9a595cb6089?auto=format&fit=crop&w=500&q=80',
                    'pineapple': 'https://images.unsplash.com/photo-1550258987-190a2d41a8ba?auto=format&fit=crop&w=500&q=80',
                    
                    # Herbs & Greens
                    'spinach': 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=500&q=80',
                    'basil': 'https://images.unsplash.com/photo-1628104889506-c875150d8a56?auto=format&fit=crop&w=500&q=80',
                    'cilantro': 'https://images.unsplash.com/photo-1628104889506-c875150d8a56?auto=format&fit=crop&w=500&q=80',
                    
                    # Breads & Tortillas
                    'tortilla': 'https://images.unsplash.com/photo-1564923630403-2284b87c0041?auto=format&fit=crop&w=500&q=80',
                    'bun': 'https://images.unsplash.com/photo-1584988582570-3d7124976450?auto=format&fit=crop&w=500&q=80',
                    
                    # Nuts & Toppings
                    'peanut': 'https://images.unsplash.com/photo-1582169296194-e4d644c48063?auto=format&fit=crop&w=500&q=80',
                    'pine nut': 'https://images.unsplash.com/photo-1582169296194-e4d644c48063?auto=format&fit=crop&w=500&q=80',
                    'crouton': 'https://images.unsplash.com/photo-1584988582570-3d7124976450?auto=format&fit=crop&w=500&q=80',
                    
                    # Olives & Pickled
                    'olive': 'https://images.unsplash.com/photo-1474979266404-7cadd259c308?auto=format&fit=crop&w=500&q=80',
                    'nori': 'https://images.unsplash.com/photo-1617093727343-374698b1b08d?auto=format&fit=crop&w=500&q=80',
                 }

            for key, val in mapping.items():
                if key in n:
                    return val
            
            # Detailed Fallback attempts
            if 'bread' in n: return 'https://images.unsplash.com/photo-1584988582570-3d7124976450?auto=format&fit=crop&w=500&q=80'
            if 'leaf' in n: return 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=500&q=80'
            if 'paste' in n: return 'https://images.unsplash.com/photo-1621932952528-98e98348d2ca?auto=format&fit=crop&w=500&q=80'
            
            return None # No image available
            

        # Pre-seed unit_master with common units
        units_data = [
            ('tbsp', 'tbsp', 'volume'), ('tsp', 'tsp', 'volume'), ('cup', 'cup', 'volume'),
            ('ml', 'ml', 'volume'), ('L', 'L', 'volume'), ('fl oz', 'fl oz', 'volume'),
            ('g', 'g', 'mass'), ('kg', 'kg', 'mass'), ('oz', 'oz', 'mass'), ('lb', 'lb', 'mass'),
            ('whole', 'whole', 'count'), ('large', 'large', 'count'), ('medium', 'medium', 'count'),
            ('small', 'small', 'count'), ('clove', 'clove', 'count'), ('stalk', 'stalk', 'count'),
            ('slice', 'slice', 'count'), ('can', 'can', 'count'), ('pack', 'pack', 'count'),
            ('bunch', 'bunch', 'count'), ('head', 'head', 'count'), ('leaf', 'leaf', 'count'),
            ('inch', 'inch', 'misc'), ('sliced', 'sliced', 'misc'), ('chopped', 'chopped', 'misc'),
            ('sheet', 'sheet', 'count'), ('ball', 'ball', 'count')
        ]
        unit_cache = {}
        for name, abbrev, utype in units_data:
            cursor.execute(
                "INSERT INTO unit_master (name, abbreviation, unit_type) VALUES (%s, %s, %s) ON CONFLICT (name) DO NOTHING RETURNING id",
                (name, abbrev, utype)
            )
            row = cursor.fetchone()
            if row:
                unit_cache[name] = row[0]
            else:
                cursor.execute("SELECT id FROM unit_master WHERE name = %s", (name,))
                unit_cache[name] = cursor.fetchone()[0]

        # Caches for ingredient and equipment master tables
        ingredient_cache = {}
        equipment_cache = {}

        for r in RECIPES_DATA:
            cursor.execute(
                "INSERT INTO recipes (title, description, main_image_url, prep_time_minutes, cook_time_minutes, base_pax, cuisine) VALUES (%s, %s, %s, %s, %s, %s, %s::cuisine_enum) RETURNING id",
                (r['title'], r['description'], r['main_image_url'], r['prep_time'], r['cook_time'], r.get('base_pax', 4), r['cuisine'])
            )
            recipe_id = cursor.fetchone()[0]

            for name, amount, unit in r['ingredients']:
                # Upsert ingredient_master
                if name not in ingredient_cache:
                    icon_url = get_icon_url(name)
                    image_url = get_real_image_url(name, is_equipment=False)
                    cursor.execute(
                        "INSERT INTO ingredient_master (name, default_image_url, image_url) VALUES (%s, %s, %s) ON CONFLICT (name) DO UPDATE SET default_image_url = EXCLUDED.default_image_url, image_url = EXCLUDED.image_url RETURNING id",
                        (name, icon_url, image_url)
                    )
                    ingredient_cache[name] = cursor.fetchone()[0]
                ing_id = ingredient_cache[name]

                # Get unit_id (may be None for unknown units)
                unit_id = unit_cache.get(unit)

                cursor.execute(
                    "INSERT INTO recipe_ingredients (recipe_id, ingredient_id, amount, unit_id, display_string) VALUES (%s, %s, %s, %s, %s) ON CONFLICT (recipe_id, ingredient_id) DO NOTHING",
                    (recipe_id, ing_id, amount, unit_id, f"{amount} {unit} {name}")
                )

            for name in r['equipment']:
                # Upsert equipment_master
                if name not in equipment_cache:
                    icon_url = get_icon_url(name)
                    image_url = get_real_image_url(name, is_equipment=True)
                    cursor.execute(
                        "INSERT INTO equipment_master (name, icon_url, image_url) VALUES (%s, %s, %s) ON CONFLICT (name) DO UPDATE SET icon_url = EXCLUDED.icon_url, image_url = EXCLUDED.image_url RETURNING id",
                        (name, icon_url, image_url)
                    )
                    equipment_cache[name] = cursor.fetchone()[0]
                eq_id = equipment_cache[name]

                cursor.execute(
                    "INSERT INTO recipe_equipment (recipe_id, equipment_id) VALUES (%s, %s) ON CONFLICT (recipe_id, equipment_id) DO NOTHING",
                    (recipe_id, eq_id)
                )

            for idx, step in enumerate(r['steps']):
                # Handle both old format (tuple) and new format (dict)
                if isinstance(step, tuple):
                    short, detail = step
                    step_ingredients = []
                    step_equipment = []
                else:
                    short = step['short']
                    detail = step['detail']
                    step_ingredients = step.get('step_ingredients', [])
                    step_equipment = step.get('step_equipment', [])

                cursor.execute(
                    "INSERT INTO instruction_steps (recipe_id, order_index, short_text, detailed_description) VALUES (%s, %s, %s, %s) RETURNING id",
                    (recipe_id, idx, short, detail)
                )
                step_id = cursor.fetchone()[0]

                # Insert step-level ingredients
                for placeholder_key, ing_name, amount, unit in step_ingredients:
                    # Ensure ingredient exists in master table
                    if ing_name not in ingredient_cache:
                        icon_url = get_icon_url(ing_name)
                        image_url = get_real_image_url(ing_name, is_equipment=False)
                        cursor.execute(
                            "INSERT INTO ingredient_master (name, default_image_url, image_url) VALUES (%s, %s, %s) ON CONFLICT (name) DO UPDATE SET default_image_url = EXCLUDED.default_image_url, image_url = EXCLUDED.image_url RETURNING id",
                            (ing_name, icon_url, image_url)
                        )
                        ingredient_cache[ing_name] = cursor.fetchone()[0]
                    ing_id = ingredient_cache[ing_name]
                    unit_id = unit_cache.get(unit)

                    cursor.execute(
                        "INSERT INTO step_ingredients (step_id, ingredient_id, amount, unit_id, placeholder_key) VALUES (%s, %s, %s, %s, %s) ON CONFLICT (step_id, ingredient_id) DO NOTHING",
                        (step_id, ing_id, amount, unit_id, placeholder_key)
                    )

                # Insert step-level equipment
                for placeholder_key, eq_name in step_equipment:
                    # Ensure equipment exists in master table
                    if eq_name not in equipment_cache:
                        icon_url = get_icon_url(eq_name)
                        image_url = get_real_image_url(eq_name, is_equipment=True)
                        cursor.execute(
                            "INSERT INTO equipment_master (name, icon_url, image_url) VALUES (%s, %s, %s) ON CONFLICT (name) DO UPDATE SET icon_url = EXCLUDED.icon_url, image_url = EXCLUDED.image_url RETURNING id",
                            (eq_name, icon_url, image_url)
                        )
                        equipment_cache[eq_name] = cursor.fetchone()[0]
                    eq_id = equipment_cache[eq_name]

                    cursor.execute(
                        "INSERT INTO step_equipment (step_id, equipment_id, placeholder_key) VALUES (%s, %s, %s) ON CONFLICT (step_id, equipment_id) DO NOTHING",
                        (step_id, eq_id, placeholder_key)
                    )

        print(f"✅ Seeding Complete. Added {len(RECIPES_DATA)} recipes.")
        
        # Final Permissions Grant
        cursor.execute("GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;")
        cursor.execute("GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;")
        cursor.execute("NOTIFY pgrst, 'reload config';")
        
        cursor.close()
        conn.close()

    except Exception as e:
        print(f"❌ Error: {e}")

if __name__ == "__main__":
    seed_database()
