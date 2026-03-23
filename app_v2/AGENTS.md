# Mise en Place - Flutter App (v2)

## Build & Run

```bash
# Get dependencies
flutter pub get

# Code generation (freezed models)
dart run build_runner build --delete-conflicting-outputs

# Analyze
flutter analyze

# Run tests
flutter test

# Run app
flutter run
```

## Architecture

- **State management**: Riverpod (flutter_riverpod + riverpod_generator)
- **Routing**: GoRouter with auth redirect
- **Models**: Freezed + json_serializable for immutable data classes
- **API**: Dio-based ApiClient with auth interceptor
- **Auth**: FlutterSecureStorage for token persistence, Google Sign-In support

## Project Structure

```
lib/
  main.dart              # App entry point
  router.dart            # GoRouter configuration
  theme/                 # Design system
    app_colors.dart      # Color palette
    app_theme.dart       # ThemeData + text styles
    frosted_glass.dart   # Frosted glass widget
  widgets/               # Shared widgets
    responsive_layout.dart
  models/                # Freezed data models
    user.dart
    recipe.dart
    session.dart
    job.dart
  services/              # API and auth services
    api_client.dart
    auth_service.dart
  providers/             # Riverpod providers
    auth_provider.dart
  screens/               # Feature screens
    auth/
      login_screen.dart
      register_screen.dart
```

## Conventions

- All models use Freezed with `@JsonKey(name: 'snake_case')` for backend compatibility
- Use `const` constructors everywhere possible
- Strict analysis: strict-casts, strict-raw-types, avoid_dynamic_calls
- Dark theme is the default
