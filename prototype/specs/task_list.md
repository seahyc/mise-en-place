# Project Status & Tasks

## Completed
- [x] **Project Setup**: Env, Supabase Client.
- [x] **Data Modeling**: `Recipe`, `Ingredient`, `Equipment`.
- [x] **Backend**:
    - [x] Schema Design (`public` tables).
    - [x] **Connectivity Issues Resolved** (User utilized Transaction Pooler).
    - [x] Initial Seeding (Partial).
- [x] **UI**: `RecipeList`, `RecipeDetail`, `CookingMode` (UI only).
- [x] **Data Finalization**:
    - [x] Restore all 6 recipes in seed script.
    - [x] Clarify Auth Schema (`auth.users` vs `public.users`).

## Roadmap (Priority Order)

1. [ ] **Fork ElevenLabs Flutter SDK with bug fix**
2. [ ] **Test live update of instruction text and assets**
3. [ ] **Add images and videos** (more complex media handling)
4. [ ] **Generate or recommend recipes** - Generate never-before-seen recipes or themed recipes (Harry Potter, Lord of the Rings, etc.)
5. [ ] **Choose chef** - Clone chef voices for different cooking personalities
6. [ ] **Start voice agent from recipe page** - Different agent for recipe detail page vs cooking mode
7. [ ] **Import recipe** - From notes, videos, HTML pages
8. [ ] **Visual polish** - Timers, animations, more cookbook aesthetic
9. [ ] **Combine recipes** - Multi-recipe cooking flow

## Backlog
- [ ] **Auth Integration**:
    - [ ] Enable Supabase Auth in App (Email/Password or Anon).
    - [ ] Link Inventory to `auth.users`.
- [ ] **Inventory Features**: Pantry UI.
