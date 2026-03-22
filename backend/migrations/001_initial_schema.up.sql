-- Migration: 001_initial_schema
-- Up: Create all tables

-- Users & Auth

CREATE TABLE users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT        UNIQUE NOT NULL,
    display_name  TEXT        NOT NULL DEFAULT '',
    password_hash TEXT        NOT NULL DEFAULT '',
    google_id     TEXT        UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT        NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);

-- Recipes

CREATE TABLE recipes (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT        NOT NULL,
    description TEXT        NOT NULL DEFAULT '',
    source_url  TEXT,
    source_type TEXT        NOT NULL DEFAULT 'manual',
    cuisine     TEXT,
    image_url   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recipes_user ON recipes(user_id);

CREATE TABLE recipe_ingredients (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id   UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INT  NOT NULL DEFAULT 0,
    text        TEXT NOT NULL
);

CREATE INDEX idx_recipe_ingredients_recipe ON recipe_ingredients(recipe_id);

CREATE TABLE recipe_steps (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id   UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    order_index INT  NOT NULL,
    text        TEXT NOT NULL,
    image_url   TEXT
);

CREATE INDEX idx_recipe_steps_recipe ON recipe_steps(recipe_id);

-- Cooking Sessions

CREATE TABLE cooking_sessions (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status       TEXT        NOT NULL DEFAULT 'setup',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user ON cooking_sessions(user_id);

CREATE TABLE session_recipes (
    session_id UUID NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    recipe_id  UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    PRIMARY KEY (session_id, recipe_id)
);

CREATE TABLE session_steps (
    id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID    NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    order_index     INT     NOT NULL,
    text            TEXT    NOT NULL,
    source_dish_tag TEXT,
    is_completed    BOOLEAN NOT NULL DEFAULT false,
    completed_at    TIMESTAMPTZ,
    agent_notes     TEXT
);

CREATE INDEX idx_session_steps_session ON session_steps(session_id);

-- Voice

CREATE TABLE conversation_turns (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID        NOT NULL REFERENCES cooking_sessions(id) ON DELETE CASCADE,
    role       TEXT        NOT NULL,
    content    TEXT        NOT NULL,
    tool_calls JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_conversation_turns_session ON conversation_turns(session_id);

-- Jobs

CREATE TABLE jobs (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    type       TEXT        NOT NULL,
    status     TEXT        NOT NULL DEFAULT 'pending',
    payload    JSONB       NOT NULL DEFAULT '{}',
    result     JSONB,
    user_id    UUID        REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_user   ON jobs(user_id);
