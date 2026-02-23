-- SQL Dump for Manual Seeding
-- Copy and run this in the Supabase SQL Editor: https://supabase.com/dashboard/project/_/sql

-- 1. Reset Schema
DROP TABLE IF EXISTS recipe_ingredients CASCADE;
DROP TABLE IF EXISTS recipe_equipment CASCADE;
DROP TABLE IF EXISTS instruction_steps CASCADE;
DROP TABLE IF EXISTS recipes CASCADE;
DROP TABLE IF EXISTS ingredient_master CASCADE;
DROP TABLE IF EXISTS equipment_master CASCADE;
DROP TABLE IF EXISTS user_pantry CASCADE;
DROP TABLE IF EXISTS user_equipment CASCADE;

-- 2. Create Tables
CREATE TABLE ingredient_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    default_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE equipment_master (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    icon_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT,
    main_image_url TEXT,
    source_link TEXT,
    base_servings INTEGER DEFAULT 2,
    prep_time_minutes INTEGER DEFAULT 0,
    cook_time_minutes INTEGER DEFAULT 0,
    cuisine TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID REFERENCES recipes(id) ON DELETE CASCADE,
    ingredient_id UUID REFERENCES ingredient_master(id),
    amount NUMERIC,
    unit TEXT,
    display_string TEXT,
    comment TEXT
);

CREATE TABLE recipe_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID REFERENCES recipes(id) ON DELETE CASCADE,
    equipment_id UUID REFERENCES equipment_master(id)
);

CREATE TABLE instruction_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL,
    short_text TEXT,
    detailed_description TEXT,
    media_url TEXT
);

CREATE TABLE user_pantry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    ingredient_id UUID REFERENCES ingredient_master(id),
    amount NUMERIC,
    unit TEXT,
    expiry_date DATE
);

CREATE TABLE user_equipment (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    equipment_id UUID REFERENCES equipment_master(id)
);

-- 3. Grants
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;

-- 4. Sample Data
DO $$
DECLARE
    r_chili UUID; r_padthai UUID;
    i_bean1 UUID; i_bean2 UUID; i_onion UUID; i_pepper UUID; i_chili UUID; i_cumin UUID;
    i_noodle UUID; i_egg UUID; i_tofu UUID; i_peanut UUID; i_sprout UUID; i_sauce UUID;
    e_pot UUID; e_spoon UUID; e_knife UUID; e_wok UUID; e_tongs UUID;
BEGIN
    -- RECIPE 1: Vegan Chili
    INSERT INTO recipes (title, description, main_image_url, prep_time_minutes, cook_time_minutes, cuisine)
    VALUES ('Vegan Chili', 'Hearty, spicy, and packed with beans', 'https://images.unsplash.com/photo-1527477396000-64ca9c00173d?auto=format&fit=crop&w=1000&q=80', 15, 45, 'mexican')
    RETURNING id INTO r_chili;

    -- Ingredients (Chili)
    INSERT INTO ingredient_master (name) VALUES ('Black Beans') RETURNING id INTO i_bean1;
    INSERT INTO ingredient_master (name) VALUES ('Kidney Beans') RETURNING id INTO i_bean2;
    INSERT INTO ingredient_master (name) VALUES ('Onion') RETURNING id INTO i_onion;
    INSERT INTO ingredient_master (name) VALUES ('Bell Pepper') RETURNING id INTO i_pepper;
    INSERT INTO ingredient_master (name) VALUES ('Chili Powder') RETURNING id INTO i_chili;
    INSERT INTO ingredient_master (name) VALUES ('Cumin') RETURNING id INTO i_cumin;

    INSERT INTO recipe_ingredients (recipe_id, ingredient_id, amount, unit, display_string) VALUES
    (r_chili, i_bean1, 2, 'can', '2 can Black Beans'),
    (r_chili, i_bean2, 2, 'can', '2 can Kidney Beans'),
    (r_chili, i_onion, 1, 'medium', '1 medium Onion'),
    (r_chili, i_pepper, 2, 'sliced', '2 sliced Bell Pepper'),
    (r_chili, i_chili, 2, 'tbsp', '2 tbsp Chili Powder'),
    (r_chili, i_cumin, 1, 'tbsp', '1 tbsp Cumin');

    -- Equipment (Chili)
    INSERT INTO equipment_master (name) VALUES ('Large Pot') RETURNING id INTO e_pot;
    INSERT INTO equipment_master (name) VALUES ('Wooden Spoon') RETURNING id INTO e_spoon;
    INSERT INTO equipment_master (name) VALUES ('Knife') RETURNING id INTO e_knife;

    INSERT INTO recipe_equipment (recipe_id, equipment_id) VALUES 
    (r_chili, e_pot), (r_chili, e_spoon), (r_chili, e_knife);

    -- Steps (Chili)
    INSERT INTO instruction_steps (recipe_id, order_index, short_text, detailed_description) VALUES
    (r_chili, 0, 'Prep Veggies', 'Dice the onion and bell peppers into small cubes.'),
    (r_chili, 1, 'Sauté', 'Heat oil in pot, add onions and peppers. Cook until soft (5 min).'),
    (r_chili, 2, 'Simmer', 'Add beans, spices, and tomatoes. Simmer for 30 mins.');

    -- RECIPE 2: Pad Thai
    INSERT INTO recipes (title, description, main_image_url, prep_time_minutes, cook_time_minutes, cuisine)
    VALUES ('Pad Thai', 'Classic stir-fried rice noodle dish', 'https://images.unsplash.com/photo-1559314809-0d155014e29e?auto=format&fit=crop&w=1000&q=80', 20, 15, 'thai')
    RETURNING id INTO r_padthai;

    -- Ingredients (Pad Thai)
    INSERT INTO ingredient_master (name) VALUES ('Rice Noodles') RETURNING id INTO i_noodle;
    INSERT INTO ingredient_master (name) VALUES ('Eggs') RETURNING id INTO i_egg;
    INSERT INTO ingredient_master (name) VALUES ('Tofu') RETURNING id INTO i_tofu;
    INSERT INTO ingredient_master (name) VALUES ('Peanuts') RETURNING id INTO i_peanut;
    INSERT INTO ingredient_master (name) VALUES ('Bean Sprouts') RETURNING id INTO i_sprout;
    INSERT INTO ingredient_master (name) VALUES ('Pad Thai Sauce') RETURNING id INTO i_sauce;

    INSERT INTO recipe_ingredients (recipe_id, ingredient_id, amount, unit, display_string) VALUES
    (r_padthai, i_noodle, 200, 'g', '200 g Rice Noodles'),
    (r_padthai, i_egg, 2, 'whole', '2 whole Eggs'),
    (r_padthai, i_tofu, 150, 'g', '150 g Tofu'),
    (r_padthai, i_peanut, 50, 'g', '50 g Peanuts'),
    (r_padthai, i_sprout, 100, 'g', '100 g Bean Sprouts'),
    (r_padthai, i_sauce, 100, 'ml', '100 ml Pad Thai Sauce');

    -- Equipment (Pad Thai)
    INSERT INTO equipment_master (name) VALUES ('Wok') RETURNING id INTO e_wok;
    INSERT INTO equipment_master (name) VALUES ('Tongs') RETURNING id INTO e_tongs;

    INSERT INTO recipe_equipment (recipe_id, equipment_id) VALUES 
    (r_padthai, e_wok), (r_padthai, e_tongs);

    -- Steps (Pad Thai)
    INSERT INTO instruction_steps (recipe_id, order_index, short_text, detailed_description) VALUES
    (r_padthai, 0, 'Soak Noodles', 'Soak rice noodles in warm water for 30 mins until pliable.'),
    (r_padthai, 1, 'Stir Fry', 'Fry tofu and eggs in wok. Add noodles and sauce.'),
    (r_padthai, 2, 'Garnish', 'Toss in bean sprouts and peanuts just before serving.');

END $$;
