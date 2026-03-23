import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'router.dart';
import 'theme/app_theme.dart';

void main() {
  MarionetteBinding.ensureInitialized();
  runApp(const ProviderScope(child: MiseEnPlaceApp()));
}

class MiseEnPlaceApp extends ConsumerWidget {
  const MiseEnPlaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Mise en Place',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
