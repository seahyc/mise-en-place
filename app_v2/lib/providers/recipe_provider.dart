import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/recipe.dart';
import 'auth_provider.dart';

final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getRecipes();
});
