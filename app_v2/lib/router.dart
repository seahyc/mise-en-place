import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/recipes',
    redirect: (BuildContext context, GoRouterState state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      if (!isLoggedIn && !isAuthRoute) {
        return '/auth/login';
      }
      if (isLoggedIn && isAuthRoute) {
        return '/recipes';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/recipes',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Recipes')),
        ),
      ),
      GoRoute(
        path: '/recipes/:id',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('Recipe ${state.pathParameters['id']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/recipes/:id/edit',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('Edit Recipe ${state.pathParameters['id']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/cook/:sessionId',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Text('Cooking ${state.pathParameters['sessionId']}'),
          ),
        ),
      ),
      GoRoute(
        path: '/import',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Import')),
        ),
      ),
    ],
  );
});
