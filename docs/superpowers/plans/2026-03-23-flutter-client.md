# Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Mise en Place Flutter client — an Apple TV-inspired, dark-first cooking app with cinematic cooking mode, Pinterest masonry browsing, voice AI integration, and video-to-recipe import.

**Architecture:** Riverpod for state management, Freezed for models, dio for HTTP, web_socket_channel for voice/session WebSockets, go_router for navigation. Design system as a shared theme with reusable widgets. Responsive: iPad landscape (full), iPad portrait (adapted), phone (compact).

**Tech Stack:** Flutter 3.x, Riverpod, Freezed, dio, web_socket_channel, go_router, golden_toolkit, flutter_secure_storage, google_sign_in

**Spec:** `docs/superpowers/specs/2026-03-23-flutter-ui-design.md` + `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md`

**Dependency:** Backend (Plans 1-4) must be complete. Backend runs at configurable BASE_URL.

---

## File Structure

```
app_v2/
├─ lib/
│   ├─ main.dart
│   ├─ theme/
│   │   ├─ app_theme.dart              ← dark + light ThemeData, colors, text styles
│   │   ├─ app_colors.dart             ← color constants (dark/light)
│   │   └─ frosted_glass.dart          ← reusable frosted glass container widget
│   ├─ models/
│   │   ├─ user.dart                   ← User, TokenPair (Freezed)
│   │   ├─ recipe.dart                 ← Recipe, RecipeStep, ingredient w/ emoji (Freezed)
│   │   ├─ session.dart                ← CookingSession, SessionStep (Freezed)
│   │   └─ job.dart                    ← Job status (Freezed)
│   ├─ services/
│   │   ├─ api_client.dart             ← dio HTTP client + auth interceptor
│   │   ├─ auth_service.dart           ← login, register, google, refresh, token storage
│   │   ├─ voice_client.dart           ← WebSocket voice pipeline client
│   │   └─ session_ws_client.dart      ← WebSocket session updates client
│   ├─ providers/
│   │   ├─ auth_provider.dart          ← auth state, current user
│   │   ├─ recipe_provider.dart        ← recipe list, CRUD operations
│   │   ├─ session_provider.dart       ← session lifecycle
│   │   └─ voice_provider.dart         ← voice connection state
│   ├─ router.dart                     ← go_router with auth guard
│   ├─ screens/
│   │   ├─ auth/
│   │   │   ├─ login_screen.dart
│   │   │   └─ register_screen.dart
│   │   ├─ browse/
│   │   │   ├─ browse_screen.dart      ← responsive masonry (iPad 4-col, phone 2-col)
│   │   │   ├─ recipe_card.dart        ← masonry card widget
│   │   │   ├─ empty_state.dart        ← "Your kitchen awaits" + sparse state
│   │   │   └─ filter_chips.dart       ← cuisine filter row
│   │   ├─ recipe/
│   │   │   ├─ recipe_detail_screen.dart
│   │   │   ├─ recipe_edit_screen.dart
│   │   │   ├─ changelog_sheet.dart
│   │   │   └─ ingredient_row.dart     ← emoji + amount + name row
│   │   ├─ cook/
│   │   │   ├─ session_setup_sheet.dart
│   │   │   ├─ cooking_mode_screen.dart    ← iPad hybrid layout
│   │   │   ├─ cooking_mode_phone.dart     ← phone full-screen layout
│   │   │   ├─ step_panel.dart             ← right panel (step text, dots, timer, voice bar)
│   │   │   ├─ ingredient_panel.dart       ← frosted panel on image
│   │   │   ├─ voice_bar.dart              ← listening/speaking states
│   │   │   ├─ timer_chip.dart             ← pulsing timer pill with expand/cancel
│   │   │   └─ agent_bubble.dart           ← agent response text bubble
│   │   └─ import/
│   │       └─ import_screen.dart
│   └─ widgets/
│       ├─ cuisine_tag.dart            ← small colored tag pill
│       ├─ source_badge.dart           ← platform icon + @creator
│       └─ responsive_layout.dart      ← breakpoint helper
├─ test/
│   ├─ unit/
│   │   ├─ models_test.dart
│   │   ├─ auth_service_test.dart
│   │   └─ voice_client_test.dart
│   ├─ widget/
│   │   ├─ cooking_mode_golden_test.dart
│   │   ├─ browse_golden_test.dart
│   │   ├─ recipe_detail_golden_test.dart
│   │   └─ login_golden_test.dart
│   └─ integration_test/
│       └─ cooking_flow_test.dart
├─ pubspec.yaml
├─ analysis_options.yaml
└─ AGENTS.md
```

---

### Task 1: Project Scaffold + Design System

**Files:**
- Create: `app_v2/` (new Flutter project)
- Create: `app_v2/lib/theme/app_colors.dart`
- Create: `app_v2/lib/theme/app_theme.dart`
- Create: `app_v2/lib/theme/frosted_glass.dart`
- Create: `app_v2/lib/widgets/responsive_layout.dart`
- Create: `app_v2/lib/main.dart`
- Create: `app_v2/analysis_options.yaml`
- Create: `app_v2/AGENTS.md`

- [ ] **Step 1: Create Flutter project**
```bash
cd /Users/yingcong/Code/mise-en-place
flutter create --org com.seahyingcong --project-name mise_en_place app_v2
```

- [ ] **Step 2: Add dependencies to pubspec.yaml**
```yaml
dependencies:
  flutter_riverpod: ^2.5.0
  riverpod_annotation: ^2.3.0
  dio: ^5.4.0
  web_socket_channel: ^2.4.0
  flutter_secure_storage: ^9.0.0
  go_router: ^13.0.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0
  google_sign_in: ^6.2.0
  flutter_staggered_grid_view: ^0.7.0
  cached_network_image: ^3.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
  golden_toolkit: ^0.15.0
  lints: ^3.0.0
```

- [ ] **Step 3: Configure strict analysis_options.yaml**
```yaml
include: package:lints/recommended.yaml
analyzer:
  strict-casts: true
  strict-raw-types: true
linter:
  rules:
    - avoid_dynamic_calls
    - prefer_const_constructors
    - always_declare_return_types
    - prefer_final_locals
    - avoid_print
    - unawaited_futures
    - prefer_single_quotes
```

- [ ] **Step 4: Implement AppColors**
```dart
// app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  // Dark mode
  static const darkBackground = Color(0xFF0A0A0A);
  static const darkSurface = Color(0xFF141414);
  static const darkBorder = Color(0x14FFFFFF); // 0.08 opacity

  // Light mode
  static const lightBackground = Color(0xFFFAF7F2);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightBorder = Color(0x1A000000); // 0.10 opacity

  // Accent
  static const amber = Color(0xFFFF9F0A);
  static const green = Color(0xFF30D158);
  static const blue = Color(0xFF6382FF);
  static const purple = Color(0xFFBF5AF2);

  // Dish tag colors (cycle for 5+ dishes)
  static const dishTags = [green, amber, blue, purple];

  // Text (dark mode)
  static const darkTextPrimary = Color(0xFFFFFFFF);
  static const darkTextSecondary = Color(0x73FFFFFF); // 0.45
  static const darkTextTertiary = Color(0x40FFFFFF); // 0.25

  // Text (light mode)
  static const lightTextPrimary = Color(0xFF1A1A1A);
  static const lightTextSecondary = Color(0x80000000); // 0.50
  static const lightTextTertiary = Color(0x4D000000); // 0.30
}
```

- [ ] **Step 5: Implement AppTheme**
Build dark and light ThemeData using AppColors. Define text styles matching the spec: stepText (32px semibold -0.6 tracking), detailText (15px), cardTitle (14px semibold), sectionHeader (11px uppercase 1.2 tracking), metadata (12px).

- [ ] **Step 6: Implement FrostedGlass widget**
```dart
// frosted_glass.dart
class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsets padding;

  // Uses ClipRRect + BackdropFilter + Container
  // Dark: rgba(0,0,0,0.5) bg, blur 24, white 0.07 border
  // Light: rgba(255,255,255,0.7) bg, blur 24, black 0.06 border
  // Adapts based on Theme.of(context).brightness
}
```

- [ ] **Step 7: Implement ResponsiveLayout**
```dart
// responsive_layout.dart
enum DeviceType { phone, tablet, largeTablet }

class ResponsiveLayout extends StatelessWidget {
  final Widget phone;
  final Widget? tablet;
  final Widget? largeTablet;
  // Breakpoints: <600 phone, 600-1024 tablet, >1024 largeTablet
  // Returns appropriate child based on MediaQuery width
}

DeviceType getDeviceType(BuildContext context) { ... }
```

- [ ] **Step 8: Write minimal main.dart with Riverpod + theme**
```dart
void main() {
  runApp(const ProviderScope(child: MiseApp()));
}
class MiseApp extends ConsumerWidget {
  // MaterialApp.router with AppTheme.dark as theme, AppTheme.light as light theme
  // ThemeMode.dark as default
}
```

- [ ] **Step 9: Write AGENTS.md**
- [ ] **Step 10: Verify build + analyze**
```bash
cd app_v2 && flutter pub get && flutter analyze
```
- [ ] **Step 11: Commit**

---

### Task 2: Models (Freezed)

**Files:**
- Create: `app_v2/lib/models/user.dart`
- Create: `app_v2/lib/models/recipe.dart`
- Create: `app_v2/lib/models/session.dart`
- Create: `app_v2/lib/models/job.dart`
- Create: `app_v2/test/unit/models_test.dart`

- [ ] **Step 1: Write models with Freezed + JsonSerializable**

`user.dart`: User (id, email, displayName), TokenPair (accessToken, refreshToken, expiresIn)

`recipe.dart`: Recipe (id, title, description, sourceUrl, sourceType, cuisine, imageUrl, ingredients List<RecipeIngredient>, steps List<RecipeStep>, createdAt, updatedAt). RecipeIngredient (text, emoji). RecipeStep (orderIndex, text, imageUrl).

`session.dart`: CookingSession (id, userId, status, recipeIds, steps List<SessionStep>, createdAt, startedAt, completedAt). SessionStep (id, orderIndex, text, sourceDishTag, isCompleted, completedAt, agentNotes). SessionStatus enum.

`job.dart`: Job (id, type, status, payload, result, createdAt, updatedAt). JobStatus enum.

- [ ] **Step 2: Run build_runner**
```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 3: Write model test — JSON round-trip**
Create a Recipe from JSON map, serialize back, verify fields match.

- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 3: API Client + Auth Service

**Files:**
- Create: `app_v2/lib/services/api_client.dart`
- Create: `app_v2/lib/services/auth_service.dart`
- Create: `app_v2/lib/providers/auth_provider.dart`
- Create: `app_v2/test/unit/auth_service_test.dart`

- [ ] **Step 1: Implement ApiClient**

dio HTTP client wrapping all backend endpoints. Constructor takes baseUrl. AuthInterceptor handles:
- Attaches `Authorization: Bearer <token>` to all requests
- On 401: attempts token refresh, retries original request
- Token storage via FlutterSecureStorage

Methods: register, login, loginWithGoogle, refresh, getMe, getRecipes, getRecipe, createRecipe, updateRecipe, deleteRecipe, createSession, getSession, startSession, pauseSession, resumeSession, completeStep, listSessions, ingestUrl, getJob.

- [ ] **Step 2: Implement AuthService**

Wraps ApiClient auth methods + token lifecycle. Methods: login, register, loginWithGoogle, logout, isLoggedIn, getCurrentUser. Stores/retrieves tokens from FlutterSecureStorage. Exposes authStateStream.

- [ ] **Step 3: Implement auth_provider.dart**

```dart
final authServiceProvider = Provider<AuthService>((ref) => ...);
final authStateProvider = StreamProvider<User?>((ref) => ...);
final apiClientProvider = Provider<ApiClient>((ref) => ...);
```

- [ ] **Step 4: Write auth test with mock dio**
Test: login stores tokens, subsequent requests have auth header, 401 triggers refresh.

- [ ] **Step 5: Run tests**
- [ ] **Step 6: Commit**

---

### Task 4: Router + Auth Screens

**Files:**
- Create: `app_v2/lib/router.dart`
- Create: `app_v2/lib/screens/auth/login_screen.dart`
- Create: `app_v2/lib/screens/auth/register_screen.dart`
- Create: `app_v2/test/widget/login_golden_test.dart`

- [ ] **Step 1: Implement GoRouter with auth redirect**

Routes: /auth/login, /auth/register, /recipes (browse), /recipes/:id (detail), /recipes/:id/edit, /cook/:sessionId, /import. Auth guard redirects to /auth/login if not logged in.

- [ ] **Step 2: Implement LoginScreen**

Dark background. Centered card with: app logo ("mise **en** place"), email field, password field, amber "Sign In" button, "Sign in with Google" button (white, Google icon), "Create account" link to register. Follows spec design system.

- [ ] **Step 3: Implement RegisterScreen**

Same layout as login but: email, password, display name fields, "Create Account" button, "Already have an account?" link.

- [ ] **Step 4: Write golden test for login screen**
Render at iPad (1024x1366) and phone (390x844) sizes. Compare against golden PNG files.

- [ ] **Step 5: Update main.dart to use router**
- [ ] **Step 6: Run flutter analyze + tests**
- [ ] **Step 7: Commit**

---

### Task 5: Shared Widgets

**Files:**
- Create: `app_v2/lib/widgets/cuisine_tag.dart`
- Create: `app_v2/lib/widgets/source_badge.dart`

- [ ] **Step 1: Implement CuisineTag**
Small pill: flag emoji + cuisine name. Background: rgba amber 0.1, text: amber, border: rgba amber 0.12. Size: 10-11px text, 2px 7px padding, 5px radius.

- [ ] **Step 2: Implement SourceBadge**
Platform icon (small square, 12px) + @creator text. Dimmed colors.

- [ ] **Step 3: Commit**

---

### Task 6: Recipe Browsing Screen

**Files:**
- Create: `app_v2/lib/screens/browse/browse_screen.dart`
- Create: `app_v2/lib/screens/browse/recipe_card.dart`
- Create: `app_v2/lib/screens/browse/empty_state.dart`
- Create: `app_v2/lib/screens/browse/filter_chips.dart`
- Create: `app_v2/lib/providers/recipe_provider.dart`
- Create: `app_v2/test/widget/browse_golden_test.dart`

- [ ] **Step 1: Implement recipe_provider.dart**
```dart
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final api = ref.watch(apiClientProvider);
  return api.getRecipes();
});
```

- [ ] **Step 2: Implement RecipeCard**
Variable-height card: CachedNetworkImage at top (fills width, aspect ratio from image), card body below with title (13px semibold) + meta row (CuisineTag + cook time or SourceBadge). Dark surface background, subtle border, 14px radius.

- [ ] **Step 3: Implement FilterChips**
Horizontal scrollable row. Active chip: amber bg, black text. Inactive: dark surface bg, dimmed text, subtle border. Chips: All, cuisine flags, Vegan, Favorites, Imported.

- [ ] **Step 4: Implement EmptyState**
Three modes based on recipe count:
- 0 recipes: centered "Your kitchen awaits" with 🍳 emoji, amber CTA button
- 2-3 recipes: horizontal card row + dashed "Import" card + Quick Start actions
- 4+: switch to masonry grid

- [ ] **Step 5: Implement BrowseScreen**
ResponsiveLayout: iPad landscape 4-col masonry (flutter_staggered_grid_view), iPad portrait 3-col, phone 2-col. Top bar: logo + search + avatar. Filter chips below. FAB bottom-right (amber, "+"). Phone adds bottom tab bar.

Uses recipe_provider. Shows EmptyState when few recipes, masonry grid when 4+.

- [ ] **Step 6: Write golden test**
Render BrowseScreen with mock data (12 recipes) at iPad size. Update goldens.

- [ ] **Step 7: Commit**

---

### Task 7: Recipe Detail Screen

**Files:**
- Create: `app_v2/lib/screens/recipe/recipe_detail_screen.dart`
- Create: `app_v2/lib/screens/recipe/ingredient_row.dart`
- Create: `app_v2/test/widget/recipe_detail_golden_test.dart`

- [ ] **Step 1: Implement IngredientRow**
Row: emoji (18px, 24px width) + amount (14px, amber, semibold, 60px min-width) + name (14px, dimmed). Bottom border separator.

- [ ] **Step 2: Implement RecipeDetailScreen**
- Hero image (40% height, parallax via SliverAppBar or CustomScrollView)
- Frosted back button (top-left) + edit button (top-right)
- Gradient overlay fading into content
- Title (30px bold, overlaps hero), tags row (CuisineTag + time + serves + changelog pill "📝 N edits")
- Source row if imported
- Description
- "INGREDIENTS" section header + IngredientRow list
- "STEPS" section header + numbered step rows
- Fixed "🍳 Start Cooking" button at bottom (amber, full-width, 14px radius, shadow)

- [ ] **Step 3: Write golden test at iPad + phone sizes**
- [ ] **Step 4: Commit**

---

### Task 8: Recipe Edit + Changelog

**Files:**
- Create: `app_v2/lib/screens/recipe/recipe_edit_screen.dart`
- Create: `app_v2/lib/screens/recipe/changelog_sheet.dart`

- [ ] **Step 1: Implement RecipeEditScreen**
Full-screen route. "Cancel" left, "Save" right (amber). Editable title, description, ingredient rows (with emoji auto-suggest placeholder — just show text input for now, emoji enrichment is backend-side), steps with drag-to-reorder (ReorderableListView). Add ingredient/step buttons. On save: call API update, auto-diff for changelog, optional note sheet.

- [ ] **Step 2: Implement ChangelogSheet**
showModalBottomSheet. Header "Edit History" + close. Vertical timeline: amber dots, connecting line, date + diff text + user note in italics. Max height 70%.

- [ ] **Step 3: Commit**

---

### Task 9: Voice Client

**Files:**
- Create: `app_v2/lib/services/voice_client.dart`
- Create: `app_v2/lib/providers/voice_provider.dart`
- Create: `app_v2/test/unit/voice_client_test.dart`

- [ ] **Step 1: Implement VoiceClient**

WebSocket client connecting to `ws://BASE_URL/ws/voice`.

```dart
class VoiceClient {
  WebSocketChannel? _channel;
  final _events = StreamController<VoiceEvent>.broadcast();
  Stream<VoiceEvent> get events => _events.stream;

  Future<void> connect(String sessionId, String token, String baseUrl);
  void sendAudio(Uint8List frame);  // binary frame
  void disconnect();
}

sealed class VoiceEvent {}
class TranscriptEvent extends VoiceEvent { final String text; final bool isFinal; }
class AgentResponseEvent extends VoiceEvent { final String text; }
class ToolCallEvent extends VoiceEvent { final String tool; final Map<String, dynamic> args; }
class TTSStartEvent extends VoiceEvent {}
class TTSEndEvent extends VoiceEvent {}
class AudioEvent extends VoiceEvent { final Uint8List data; }
class ErrorEvent extends VoiceEvent { final String code, message; }
```

Binary frames → AudioEvent. Text frames → parse JSON → typed event.

- [ ] **Step 2: Implement voice_provider.dart**
```dart
final voiceClientProvider = Provider<VoiceClient>((ref) => VoiceClient());
final voiceEventsProvider = StreamProvider<VoiceEvent>((ref) {
  return ref.watch(voiceClientProvider).events;
});
```

- [ ] **Step 3: Write test — connect, receive tool_call JSON, parse correctly**
- [ ] **Step 4: Commit**

---

### Task 10: Cooking Mode — Shared Widgets

**Files:**
- Create: `app_v2/lib/screens/cook/voice_bar.dart`
- Create: `app_v2/lib/screens/cook/timer_chip.dart`
- Create: `app_v2/lib/screens/cook/agent_bubble.dart`
- Create: `app_v2/lib/screens/cook/ingredient_panel.dart`
- Create: `app_v2/lib/screens/cook/step_panel.dart`

- [ ] **Step 1: Implement VoiceBar**

Four states: listening (green orb breathing, waveform, "Listening..."), userSpeaking (waveform reacts), agentSpeaking (amber orb, amber waveform, "Speaking..."), idle (dim orb, static). Frosted strip background. Animated waveform bars (5-7 bars, wave animation).

- [ ] **Step 2: Implement TimerChip**

Frosted pill: pulsing amber dot + time (tabular nums) + label. Tap to expand: shows pause/resume + cancel buttons. Long-press to cancel with confirmation.

- [ ] **Step 3: Implement AgentBubble**

Agent avatar (amber gradient, 28px rounded square) + response text (14px, 0.7 opacity). Frosted background. Appears above voice bar with slide-up animation.

- [ ] **Step 4: Implement IngredientPanel**

Frosted glass panel, no title. Vertical list: emoji (16px) + amount (13px amber) + name (13px dimmed). Anchored bottom-left, max-width 200px. Grows vertically with content.

- [ ] **Step 5: Implement StepPanel**

Right-side content panel for cooking mode. Contains: top bar (recipe name + step dots), centered step area (STEP N label + step text 32px + detail + timer chips), voice bar at bottom. Step dots: 26px circles, scrollable if 10+, done=green✓, active=amber, upcoming=dimmed.

Multi-recipe variant: dish tag pills at top instead of recipe name, colored dot + dish label on current step.

- [ ] **Step 6: Commit**

---

### Task 11: Cooking Mode Screen (iPad)

**Files:**
- Create: `app_v2/lib/screens/cook/cooking_mode_screen.dart`
- Create: `app_v2/lib/providers/session_provider.dart`
- Create: `app_v2/lib/services/session_ws_client.dart`
- Create: `app_v2/test/widget/cooking_mode_golden_test.dart`

- [ ] **Step 1: Implement session_provider.dart**
```dart
final sessionProvider = StateNotifierProvider.family<SessionNotifier, CookingSession?, String>(...);
// Manages: create session, start, pause, resume, complete step, get state
// Listens to session WebSocket for real-time updates
```

- [ ] **Step 2: Implement session_ws_client.dart**
WebSocket to `ws://BASE_URL/ws/session/{id}`. Receives SessionEvent JSON (step_completed, session_started, etc.). Exposes event stream.

- [ ] **Step 3: Implement CookingModeScreen (iPad)**

ResponsiveLayout wrapper. iPad layout:
- Row: left 45% = CachedNetworkImage (step image, crossfade between steps) + IngredientPanel overlay. Right 55% = StepPanel.
- Image side: gradient overlay blending into right panel.
- Listens to voice events via voiceEventsProvider. Handles tool calls: navigate_step → update currentStepIndex, set_timer → add timer, mark_step_complete → mark step done.
- Agent speaking: shows AgentBubble above voice bar.

Phone layout: delegates to CookingModePhone (Task 12).

- [ ] **Step 4: Write golden test — iPad cooking mode with mock session data**
Render at 1024x1366 with a 4-step session at step 2, one timer active.

- [ ] **Step 5: Commit**

---

### Task 12: Cooking Mode (Phone)

**Files:**
- Create: `app_v2/lib/screens/cook/cooking_mode_phone.dart`

- [ ] **Step 1: Implement CookingModePhone**

Full-screen, dark. Stacked vertically:
- Collapsible ingredient row at top (collapsed: horizontal emoji circles 28px, tap to expand full list, pushes content down)
- Centered step text (large)
- Timer chips below
- Voice bar fixed at bottom
- Swipe left/right for manual step navigation (PageView)

- [ ] **Step 2: Commit**

---

### Task 13: Cook Session Setup + Import

**Files:**
- Create: `app_v2/lib/screens/cook/session_setup_sheet.dart`
- Create: `app_v2/lib/screens/import/import_screen.dart`

- [ ] **Step 1: Implement SessionSetupSheet**

Bottom sheet from "Start Cooking" button. Shows selected recipe card. "Add another recipe" opens picker modal. Selected recipes as horizontal scroll with ×. Servings stepper. Amber "🍳 Cook N recipes" button. Multi-recipe shows loading overlay with spinner + "Merging your recipes..." during 3-5s API call.

- [ ] **Step 2: Implement ImportScreen**

URL field (auto-focused, pre-filled from share). Platform detection (shows TikTok/YouTube icon). Amber "Import Recipe" button. Vertical step progress list (⏳→✅ for each stage). Auto-navigates to edit screen on completion.

- [ ] **Step 3: Commit**

---

### Task 14: Wire Everything + Final Polish

**Files:**
- Modify: `app_v2/lib/main.dart`
- Modify: `app_v2/lib/router.dart`

- [ ] **Step 1: Wire all screens into router**

Ensure all routes work: /auth/login, /auth/register, /recipes, /recipes/:id, /recipes/:id/edit, /cook/:sessionId, /import. Bottom tab bar on phone for browse.

- [ ] **Step 2: Add app icon and splash screen**
Configure with amber accent. Dark splash.

- [ ] **Step 3: Run full flutter analyze + flutter test**
- [ ] **Step 4: Verify on iPad simulator + iPhone simulator**
- [ ] **Step 5: Commit**

---

### Task 15: Rename app_v2 → app

**Files:**
- Rename: `app_v2/` → `app/`
- Modify: `.github/workflows/ci.yml` (update paths)

- [ ] **Step 1: Remove old app, rename**
```bash
rm -rf app/
mv app_v2/ app/
```
- [ ] **Step 2: Update CI paths**
- [ ] **Step 3: Run tests to verify**
- [ ] **Step 4: Commit**

---

## Dependency Graph

```
Task 1 (scaffold+theme) → Task 2 (models) → Task 3 (API+auth) → Task 4 (router+auth screens)
                                                                → Task 5 (shared widgets)
Task 5 → Task 6 (browse) → Task 7 (detail) → Task 8 (edit+changelog)
Task 9 (voice client) → Task 10 (cooking widgets) → Task 11 (cooking iPad) → Task 12 (cooking phone)
Task 11 also needs Task 3 (session provider uses API)
Task 13 (setup+import) needs Tasks 3, 5
Task 14 (wire up) needs all above
Task 15 (rename) is last
```

**Parallelizable after Task 3:**
- Tasks 5+6+7+8 (browse/detail/edit flow) can run in parallel with Tasks 9+10+11+12 (voice/cooking flow)
- Task 13 can run in parallel with either stream
