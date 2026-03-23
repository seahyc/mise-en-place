import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recipe.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';

void showSessionSetupSheet(BuildContext context, Recipe recipe) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SessionSetupSheet(initialRecipe: recipe),
  );
}

class SessionSetupSheet extends ConsumerStatefulWidget {
  const SessionSetupSheet({super.key, required this.initialRecipe});

  final Recipe initialRecipe;

  @override
  ConsumerState<SessionSetupSheet> createState() => _SessionSetupSheetState();
}

class _SessionSetupSheetState extends ConsumerState<SessionSetupSheet> {
  late List<Recipe> _selectedRecipes;
  int _servings = 2;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _selectedRecipes = [widget.initialRecipe];
  }

  Future<void> _startCooking() async {
    setState(() => _loading = true);

    // Show loading overlay for multi-recipe
    if (_selectedRecipes.length > 1) {
      // The overlay is shown via the _loading state in the build method
      await Future<void>.delayed(const Duration(seconds: 2));
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final session = await apiClient.createSession(
        _selectedRecipes.map((r) => r.id).toList(),
      );
      if (mounted) {
        Navigator.pop(context); // close sheet
        if (context.mounted) unawaited(context.push('/cook/${session.id}'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _selectedRecipes.length > 1) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.amber),
              const SizedBox(height: 20),
              Text(
                'Merging your recipes...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'What are you cooking?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Selected recipe card
          ..._selectedRecipes.map((recipe) => _buildCompactRecipeCard(recipe)),

          const SizedBox(height: 12),

          // Add another recipe (placeholder)
          OutlinedButton.icon(
            key: const ValueKey('session_add_recipe'),
            onPressed: () {
              // TODO: open recipe picker
            },
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add another recipe'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.5),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Servings stepper
          Row(
            children: [
              Text(
                'Servings',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              _buildStepperButton(Icons.remove, () {
                if (_servings > 1) setState(() => _servings--);
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '$_servings',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              _buildStepperButton(Icons.add, () {
                setState(() => _servings++);
              }),
            ],
          ),
          const SizedBox(height: 24),

          // Start cooking button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              key: const ValueKey('session_start_cooking'),
              onPressed: _loading ? null : _startCooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      '\u{1F373} Cook ${_selectedRecipes.length} ${_selectedRecipes.length == 1 ? "recipe" : "recipes"}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),

          SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
        ],
      ),
    );
  }

  Widget _buildCompactRecipeCard(Recipe recipe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.restaurant,
              color: AppColors.darkTextTertiary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recipe.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (recipe.cuisine != null)
                  Text(
                    recipe.cuisine!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.green, size: 22),
        ],
      ),
    );
  }

  Widget _buildStepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}
