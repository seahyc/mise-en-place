-- Migration: 001_initial_schema
-- Down: Drop all tables in reverse dependency order

DROP TABLE IF EXISTS jobs;
DROP TABLE IF EXISTS conversation_turns;
DROP TABLE IF EXISTS session_steps;
DROP TABLE IF EXISTS session_recipes;
DROP TABLE IF EXISTS cooking_sessions;
DROP TABLE IF EXISTS recipe_steps;
DROP TABLE IF EXISTS recipe_ingredients;
DROP TABLE IF EXISTS recipes;
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS users;
