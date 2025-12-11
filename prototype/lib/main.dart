import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logging/logging.dart';

import 'data/supabase_init.dart';
import 'services/recipe_service.dart';
import 'services/auth_service.dart';
import 'screens/recipe_list_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/recipe_detail_screen.dart';
import 'screens/cooking_mode_screen.dart';
import 'models/recipe.dart';
import 'utils/auth_redirect.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Allow Google Fonts runtime fetching (emojis will use system font fallback)
  GoogleFonts.config.allowRuntimeFetching = true;

  // Suppress noisy LiveKit/SDK warnings that don't affect functionality
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    final msg = record.message;
    // Skip noisy LiveKit warnings
    if (msg.contains('unnecessary dispose()') ||
        msg.contains('disposed emitter') ||
        msg.contains('disposed ChangeNotifier') ||
        msg.contains('could not get connected server address') ||
        msg.contains('setSpeakerphoneOn only support')) {
      return;
    }
    // Skip Noto font warnings
    if (msg.contains('Noto')) return;

    developer.log(
      record.message,
      name: record.loggerName,
      level: record.level.value,
    );
  });

  // Suppress Flutter framework errors for known issues
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.toString();
    if (message.contains('Noto')) return;
    FlutterError.presentError(details);
  };

  try {
    await loadEnvIfPresent();
    await initSupabase();
    await handleAuthRedirect();
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            'Configuration error: $e',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ));
    return;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => RecipeService()), 
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        // Key changes on auth state to force full rebuild
        return MaterialApp(
          key: ValueKey(auth.isAuthenticated),
          title: 'Mise en Place',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
            useMaterial3: true,
            fontFamily: 'Inter',
            scaffoldBackgroundColor: const Color(0xFFF5F5F7),
          ),
          initialRoute: '/',
          onGenerateRoute: (settings) {
            final isAuthed = auth.isAuthenticated;

            if (settings.name == '/' || settings.name == null) {
              return MaterialPageRoute(
                builder: (_) =>
                    isAuthed ? const RecipeListScreen() : const LoginScreen(),
                settings: settings,
              );
            }

            if (settings.name != null && settings.name!.startsWith('/cook/')) {
              final recipeId = settings.name!.substring('/cook/'.length);
              return MaterialPageRoute(
                settings: settings,
                builder: (context) {
                  if (!isAuthed) return const LoginScreen();

                  final recipeArg = settings.arguments;
                  if (recipeArg is Recipe) {
                    return CookingModeScreen(recipe: recipeArg);
                  }

                  final recipeService = Provider.of<RecipeService>(context, listen: false);
                  return FutureBuilder<Recipe?>(
                    future: recipeService.getRecipeById(recipeId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError || snapshot.data == null) {
                        return const Scaffold(
                          body: Center(child: Text('Recipe not found')),
                        );
                      }
                      return CookingModeScreen(recipe: snapshot.data!);
                    },
                  );
                },
              );
            }

            if (settings.name != null && settings.name!.startsWith('/recipe/')) {
              final recipeId = settings.name!.substring('/recipe/'.length);
              return MaterialPageRoute(
                builder: (_) => isAuthed
                    ? RecipeDetailScreen(recipeId: recipeId)
                    : const LoginScreen(),
                settings: settings,
              );
            }

            // Handle /cook without recipe ID - redirect to home
            if (settings.name == '/cook') {
              return MaterialPageRoute(
                builder: (_) => isAuthed ? const RecipeListScreen() : const LoginScreen(),
                settings: const RouteSettings(name: '/'),
              );
            }

            // Handle /recipe without recipe ID - redirect to home
            if (settings.name == '/recipe') {
              return MaterialPageRoute(
                builder: (_) => isAuthed ? const RecipeListScreen() : const LoginScreen(),
                settings: const RouteSettings(name: '/'),
              );
            }

            return MaterialPageRoute(
              builder: (_) => const Scaffold(
                body: Center(child: Text('Page not found')),
              ),
              settings: settings,
            );
          },
        );
      },
    );
  }
}
