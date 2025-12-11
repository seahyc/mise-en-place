# Project Status & Tasks

## Completed
- [x] **Project Setup**: Env, Supabase Client.
- [x] **Data Modeling**: `Recipe`, `Ingredient`, `Equipment`.
- [x] **Backend**:
    - [x] Schema Design (`public` tables).
    - [x] **Connectivity Issues Resolved** (User utilized Transaction Pooler).
    - [x] Initial Seeding (Partial).
- [x] **UI**: `RecipeList`, `RecipeDetail`, `CookingMode` (UI only).

## In Progress
- [x] **Data Finalization**:
    - [x] Restore all 6 recipes in seed script.
    - [x] Clarify Auth Schema (`auth.users` vs `public.users`).
- [ ] **Auth Integration**:
    - [ ] Enable Supabase Auth in App (Email/Password or Anon).
    - [ ] Link Inventory to `auth.users`.

## Upcoming
- [ ] **ElevenLabs Integration**: Connect SDK logic.
- [ ] **Inventory Features**: Pantry UI.
