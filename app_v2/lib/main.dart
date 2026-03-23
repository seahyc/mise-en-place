import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: MiseEnPlaceApp()));
}

class MiseEnPlaceApp extends StatelessWidget {
  const MiseEnPlaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mise en Place',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const Scaffold(
        body: Center(
          child: Text('Mise en Place'),
        ),
      ),
    );
  }
}
