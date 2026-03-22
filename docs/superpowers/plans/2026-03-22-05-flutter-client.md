# Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the new Flutter client from scratch with Riverpod state management, connecting to the Go backend for auth, recipes, cooking sessions, video ingestion, and the voice pipeline. Cross-platform: iPad (cooking), phone (browsing), web (management).

**Architecture:** Riverpod for state management. Dedicated service classes for HTTP API and WebSocket connections. CookingModeController pattern retained from prototype. Golden image tests for visual regression. Patrol for native interaction testing.

**Tech Stack:** Flutter 3.x, Riverpod, dio (HTTP), web_socket_channel, flutter_secure_storage, drift (local SQLite cache), golden_toolkit, patrol

**Spec:** `docs/superpowers/specs/2026-03-22-mise-v2-architecture-design.md` (section 6)

**Dependency:** Plan 1 (backend running for integration). Plans 2-4 provide the API endpoints.

---

### Task 1: Flutter Project Scaffold + Riverpod Setup

**Files:**
- Create: `app_v2/` (new Flutter project — clean start, old app stays as reference)
- Create: `app_v2/lib/main.dart`
- Create: `app_v2/lib/providers.dart`
- Create: `app_v2/analysis_options.yaml`
- Create: `app_v2/AGENTS.md`

- [ ] **Step 1: Create new Flutter project**

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
  drift: ^2.15.0
  sqlite3_flutter_libs: ^0.5.0
  golden_toolkit: ^0.15.0
  go_router: ^13.0.0
  freezed_annotation: ^2.4.0
  json_annotation: ^4.8.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  riverpod_generator: ^2.4.0
  build_runner: ^2.4.0
  freezed: ^2.4.0
  json_serializable: ^6.7.0
  patrol: ^3.5.0
  custom_lint: ^0.6.0
```

- [ ] **Step 3: Configure strict analysis_options.yaml**

```yaml
include: package:flutter_lints/flutter.yaml

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

- [ ] **Step 4: Write AGENTS.md**

```markdown
# Mise en Place — Flutter Client

## Build & Test
- `flutter analyze` — lint
- `flutter test` — unit + golden tests
- `flutter test test/widget/` — golden image tests only
- `patrol test` — native integration tests

## Architecture
Riverpod for state management. Services as providers.
Screens → Controllers (StateNotifier) → Services → API/WebSocket.

## Conventions
- Freezed for immutable models
- All API calls through ApiClient service
- Golden tests for every screen at iPad + phone sizes
- No business logic in widgets
```

- [ ] **Step 5: Write minimal main.dart with Riverpod**

```dart
void main() {
  runApp(const ProviderScope(child: MiseApp()));
}

class MiseApp extends ConsumerWidget {
  const MiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Mise en Place',
      routerConfig: ref.watch(routerProvider),
    );
  }
}
```

- [ ] **Step 6: Verify build + analyze**

```bash
cd app_v2 && flutter analyze && flutter test
```

- [ ] **Step 7: Commit**

---

### Task 2: Models (Freezed)

**Files:**
- Create: `app_v2/lib/models/user.dart`
- Create: `app_v2/lib/models/recipe.dart`
- Create: `app_v2/lib/models/session.dart`
- Create: `app_v2/lib/models/auth.dart`
- Create: `app_v2/test/unit/models_test.dart`

- [ ] **Step 1: Write failing model test**

Test JSON round-trip: create a Recipe from JSON, serialize back, compare.

- [ ] **Step 2: Implement models with Freezed**

```dart
@freezed
class Recipe with _$Recipe {
  const factory Recipe({
    required String id,
    required String title,
    required String description,
    String? sourceUrl,
    required String sourceType,
    String? cuisine,
    String? imageUrl,
    required List<String> ingredients,
    required List<RecipeStep> steps,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Recipe;

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);
}

@freezed
class RecipeStep with _$RecipeStep {
  const factory RecipeStep({
    required int orderIndex,
    required String text,
    String? imageUrl,
  }) = _RecipeStep;

  factory RecipeStep.fromJson(Map<String, dynamic> json) => _$RecipeStepFromJson(json);
}
```

Similarly for User, CookingSession, SessionStep, TokenPair.

- [ ] **Step 3: Run build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 3: Auth Service + API Client

**Files:**
- Create: `app_v2/lib/services/api_client.dart`
- Create: `app_v2/lib/services/auth_service.dart`
- Create: `app_v2/lib/providers/auth_provider.dart`
- Create: `app_v2/test/unit/auth_service_test.dart`

- [ ] **Step 1: Write failing auth test**

Test with mock Dio: login → stores tokens → subsequent requests have auth header → on 401, refreshes token.

- [ ] **Step 2: Implement ApiClient**

```dart
class ApiClient {
  final Dio _dio;
  final FlutterSecureStorage _storage;

  ApiClient({required String baseUrl})
    : _dio = Dio(BaseOptions(baseUrl: baseUrl)),
      _storage = const FlutterSecureStorage() {
    _dio.interceptors.add(AuthInterceptor(_dio, _storage));
  }

  // Auth
  Future<TokenPair> register(String email, String password, String name);
  Future<TokenPair> login(String email, String password);
  Future<TokenPair> refresh(String refreshToken);

  // Recipes
  Future<List<Recipe>> getRecipes({int page = 1, int pageSize = 20});
  Future<Recipe> getRecipe(String id);
  Future<Recipe> createRecipe(CreateRecipeRequest req);
  Future<void> deleteRecipe(String id);

  // Sessions
  Future<CookingSession> createSession(List<String> recipeIds);
  Future<CookingSession> getSession(String id);
  Future<void> startSession(String id);
  Future<void> completeStep(String sessionId, String stepId);

  // Ingestion
  Future<String> ingestUrl(String url); // returns job ID
  Future<Job> getJob(String id);
}
```

- [ ] **Step 3: Implement AuthInterceptor**

Intercepts 401 responses, attempts token refresh, retries original request.

- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 4: Recipe Screens

**Files:**
- Create: `app_v2/lib/screens/recipe_list_screen.dart`
- Create: `app_v2/lib/screens/recipe_detail_screen.dart`
- Create: `app_v2/lib/screens/recipe_edit_screen.dart`
- Create: `app_v2/lib/providers/recipe_provider.dart`
- Create: `app_v2/test/widget/recipe_list_golden_test.dart`
- Create: `app_v2/test/widget/recipe_detail_golden_test.dart`

- [ ] **Step 1: Write golden test for recipe list**

```dart
testGoldens('recipe list - iPad', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [recipesProvider.overrideWithValue(AsyncData(mockRecipes))],
      child: const MaterialApp(home: RecipeListScreen()),
    ),
  );
  await screenMatchesGolden(tester, 'recipe_list_ipad',
    customPump: (w) => w.pumpAndSettle(),
    device: Device(name: 'ipad', size: Size(1024, 1366)));
});

testGoldens('recipe list - phone', (tester) async {
  // same but with Size(390, 844)
});
```

- [ ] **Step 2: Run test to verify it fails**
- [ ] **Step 3: Implement RecipeListScreen**

Grid layout on iPad, list on phone. Each recipe card shows image, title, cuisine tag. Pull-to-refresh. FAB for adding recipe (URL or manual).

- [ ] **Step 4: Implement RecipeDetailScreen**

Full recipe view: image, title, description, ingredients list, steps with images. Edit button, delete button, "Start Cooking" button.

- [ ] **Step 5: Run golden tests, update goldens**

```bash
flutter test --update-goldens test/widget/
```

- [ ] **Step 6: Commit**

---

### Task 5: URL Share Extension + Ingestion UI

**Files:**
- Create: `app_v2/lib/screens/ingest_screen.dart`
- Create: `app_v2/lib/providers/ingestion_provider.dart`
- Create: `app_v2/test/unit/ingestion_test.dart`

- [ ] **Step 1: Write failing test**

Test: submit URL → provider calls apiClient.ingestUrl → polls job status → when done, navigates to recipe edit screen.

- [ ] **Step 2: Implement IngestScreen**

Simple screen: URL text field (pre-filled if shared from another app), "Import Recipe" button, progress indicator showing job status, transitions to recipe edit when done.

- [ ] **Step 3: Configure share extension**

For iOS: add share extension target that receives URLs, launches app with deep link.
For Android: intent-filter for shared text/URLs in AndroidManifest.xml.

This is platform-specific and may require manual testing.

- [ ] **Step 4: Run tests**
- [ ] **Step 5: Commit**

---

### Task 6: Voice Client (WebSocket Audio Streaming)

**Files:**
- Create: `app_v2/lib/services/voice_client.dart`
- Create: `app_v2/test/unit/voice_client_test.dart`

- [ ] **Step 1: Write failing test**

Test: connect WebSocket → send session_start → receive tool_call JSON → parse correctly.

- [ ] **Step 2: Implement VoiceClient**

```dart
class VoiceClient {
  WebSocketChannel? _channel;
  final StreamController<VoiceEvent> _events = StreamController.broadcast();

  Stream<VoiceEvent> get events => _events.stream;

  Future<void> connect(String sessionId, String token, String baseUrl);
  void sendAudio(Uint8List opusFrame);
  void disconnect();
}

sealed class VoiceEvent {}
class TranscriptEvent extends VoiceEvent { final String text; final bool isFinal; }
class AgentResponseEvent extends VoiceEvent { final String text; }
class ToolCallEvent extends VoiceEvent { final String tool; final Map<String, dynamic> args; }
class TTSStartEvent extends VoiceEvent {}
class TTSEndEvent extends VoiceEvent {}
class ErrorEvent extends VoiceEvent { final String code; final String message; }
class AudioEvent extends VoiceEvent { final Uint8List data; }
```

Handle binary vs text frames. Binary → AudioEvent. Text → parse JSON → appropriate event type.

- [ ] **Step 3: Add microphone capture**

Use `record` package or `flutter_sound` to capture mic audio, encode to Opus, send via `sendAudio`.

- [ ] **Step 4: Add audio playback**

Receive AudioEvents, decode Opus, play through speaker. Use `just_audio` or direct PCM playback.

- [ ] **Step 5: Run tests**
- [ ] **Step 6: Commit**

---

### Task 7: Cooking Mode Controller + Screen

**Files:**
- Create: `app_v2/lib/controllers/cooking_mode_controller.dart`
- Create: `app_v2/lib/screens/cooking_mode_screen.dart`
- Create: `app_v2/lib/widgets/step_display.dart`
- Create: `app_v2/lib/widgets/timer_widget.dart`
- Create: `app_v2/lib/widgets/voice_indicator.dart`
- Create: `app_v2/test/unit/cooking_mode_controller_test.dart`
- Create: `app_v2/test/widget/cooking_mode_golden_test.dart`

- [ ] **Step 1: Write failing controller test**

Test: given a ToolCallEvent(navigate_step, {step: 3}) → controller updates currentStepIndex to 3. Given ToolCallEvent(set_timer, {label: "garlic", seconds: 60}) → timer starts.

- [ ] **Step 2: Implement CookingModeController**

StateNotifier managing:
```dart
@freezed
class CookingModeState with _$CookingModeState {
  const factory CookingModeState({
    required CookingSession session,
    required int currentStepIndex,
    required List<CookingTimer> activeTimers,
    required bool isListening,
    required bool isAgentSpeaking,
    String? lastTranscript,
    String? lastAgentResponse,
    required ConnectionStatus voiceStatus,
  }) = _CookingModeState;
}
```

Listens to VoiceClient events, handles tool calls, manages timers.

- [ ] **Step 3: Write golden tests for cooking mode screen**

iPad and phone sizes. States: step display, timer running, agent speaking indicator.

- [ ] **Step 4: Implement CookingModeScreen**

Large step text display (readable from distance), timer overlay, voice activity indicator (pulsing circle), step progress bar, manual next/prev buttons (fallback when voice is down).

- [ ] **Step 5: Run golden tests, update goldens**
- [ ] **Step 6: Commit**

---

### Task 8: Auth Screens + Router

**Files:**
- Create: `app_v2/lib/screens/login_screen.dart`
- Create: `app_v2/lib/screens/register_screen.dart`
- Create: `app_v2/lib/router.dart`
- Create: `app_v2/test/widget/login_golden_test.dart`

- [ ] **Step 1: Implement GoRouter with auth guard**

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  return GoRouter(
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');
      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/recipes';
      return null;
    },
    routes: [
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/recipes', builder: (_, __) => const RecipeListScreen()),
      GoRoute(path: '/recipes/:id', builder: (_, state) => RecipeDetailScreen(id: state.pathParameters['id']!)),
      GoRoute(path: '/cook/:sessionId', builder: (_, state) => CookingModeScreen(sessionId: state.pathParameters['sessionId']!)),
      GoRoute(path: '/ingest', builder: (_, __) => const IngestScreen()),
    ],
  );
});
```

- [ ] **Step 2: Implement login/register screens**
- [ ] **Step 3: Write golden tests**
- [ ] **Step 4: Commit**

---

### Task 9: Offline Cache (Drift)

**Files:**
- Create: `app_v2/lib/data/local_db.dart`
- Create: `app_v2/lib/data/recipe_cache.dart`
- Create: `app_v2/test/unit/recipe_cache_test.dart`

- [ ] **Step 1: Write failing test**

Test: cache recipes locally → read back → same data. Test: when API unavailable, read from cache.

- [ ] **Step 2: Implement Drift database**

Single table mirroring the recipe list (id, title, description, ingredients JSON, steps JSON, synced_at). Recipe provider reads from cache first, fetches from API in background, updates cache.

- [ ] **Step 3: Run tests**
- [ ] **Step 4: Commit**

---

### Task 10: Patrol Integration Tests

**Files:**
- Create: `app_v2/integration_test/cooking_flow_test.dart`
- Create: `app_v2/integration_test/share_extension_test.dart`

- [ ] **Step 1: Write cooking flow test**

```dart
patrolTest('full cooking flow', ($) async {
  // Login
  await $.pumpAndSettle();
  await $.enterText(find.byKey(Key('email')), 'test@example.com');
  await $.enterText(find.byKey(Key('password')), 'password');
  await $.tap(find.text('Login'));
  await $.pumpAndSettle();

  // Select recipe
  await $.tap(find.text('Pad Thai'));
  await $.pumpAndSettle();

  // Start cooking
  await $.tap(find.text('Start Cooking'));
  await $.native.grantPermissionWhenInUse(); // mic permission
  await $.pumpAndSettle();

  // Verify cooking mode screen
  expect(find.byType(CookingModeScreen), findsOneWidget);
});
```

- [ ] **Step 2: Write share extension test** (if Patrol supports it on target platform)
- [ ] **Step 3: Run patrol tests on emulator**
- [ ] **Step 4: Commit**

---

## Dependency Graph

```
Task 1 (scaffold) → Task 2 (models) → Task 3 (auth + API) → Task 4 (recipe screens)
                                                             → Task 5 (ingestion)
                                                             → Task 8 (auth screens + router)
Task 6 (voice client) → Task 7 (cooking mode)
Task 9 (offline cache) can run after Task 2
Task 10 (patrol) requires Tasks 4, 7, 8
```

**Parallelizable**: Tasks 4, 5, 6, 8, 9 can run in parallel after Task 3.
