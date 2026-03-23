import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/recipe.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/frosted_glass.dart';
import '../../widgets/cuisine_tag.dart';
import '../cook/session_setup_sheet.dart';
import 'changelog_sheet.dart';
import 'ingredient_row.dart';

final recipeDetailProvider =
    FutureProvider.family<Recipe, String>((ref, id) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getRecipe(id);
});

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipeAsync = ref.watch(recipeDetailProvider(recipeId));
    final screenHeight = MediaQuery.sizeOf(context).height;

    return recipeAsync.when(
      data: (recipe) => _buildContent(context, recipe, screenHeight),
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.amber),
        ),
      ),
      error: (err, _) => Scaffold(
        body: Center(
          child: Text(
            'Failed to load recipe',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Recipe recipe,
    double screenHeight,
  ) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: screenHeight * 0.4,
            pinned: true,
            backgroundColor: AppColors.darkBackground,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: FrostedGlass(
                borderRadius: 20,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () => context.pop(),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: FrostedGlass(
                  borderRadius: 20,
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () =>
                        context.push('/recipes/${recipe.id}/edit'),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (recipe.imageUrl != null)
                    CachedNetworkImage(
                      imageUrl: recipe.imageUrl!,
                      fit: BoxFit.cover,
                    )
                  else
                    Container(
                      color: AppColors.darkSurface,
                      child: const Icon(
                        Icons.restaurant,
                        size: 64,
                        color: AppColors.darkTextTertiary,
                      ),
                    ),
                  // Gradient overlay
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AppColors.darkBackground,
                        ],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -20),
              child: _buildDetails(context, recipe),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => showSessionSetupSheet(context, recipe),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
              ),
              child: const Text(
                '\u{1F373} Start Cooking',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetails(BuildContext context, Recipe recipe) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            recipe.title,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // Tags row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (recipe.cuisine != null)
                CuisineTag(cuisine: recipe.cuisine!),
              _buildInfoPill('\u{23F1} 25 min'),
              _buildInfoPill('Serves 2'),
              GestureDetector(
                onTap: () => showChangelogSheet(context),
                child: _buildInfoPill('\u{1F4DD} 0 edits'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Source row
          if (recipe.sourceUrl != null) ...[
            Text(
              'Imported from ${recipe.sourceType}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Description
          if (recipe.description.isNotEmpty) ...[
            Text(
              recipe.description,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Ingredients
          Text(
            'INGREDIENTS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(height: 8),
          ...recipe.ingredients.asMap().entries.map((entry) {
            final parsed = _parseIngredient(entry.value);
            return IngredientRow(
              emoji: parsed.emoji,
              amount: parsed.amount,
              name: parsed.name,
              showDivider: entry.key < recipe.ingredients.length - 1,
            );
          }),

          const SizedBox(height: 24),

          // Steps
          Text(
            'STEPS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: Colors.white.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(height: 8),
          ...recipe.steps.asMap().entries.map((entry) {
            final step = entry.value;
            return _buildStepRow(entry.key + 1, step.text,
                isLast: entry.key == recipe.steps.length - 1);
          }),

          const SizedBox(height: 80), // space for bottom button
        ],
      ),
    );
  }

  Widget _buildInfoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildStepRow(int number, String text, {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.04),
          ),
      ],
    );
  }
}

// Simple parser: tries to extract emoji, amount, name from ingredient string.
class _ParsedIngredient {
  const _ParsedIngredient({
    required this.emoji,
    required this.amount,
    required this.name,
  });
  final String emoji;
  final String amount;
  final String name;
}

_ParsedIngredient _parseIngredient(String raw) {
  // Pattern: optional emoji at start, then amount, then name
  final emojiRegex = RegExp(r'^(\p{Emoji_Presentation}|\p{Emoji}\uFE0F)\s*',
      unicode: true);
  var remaining = raw;
  var emoji = '\u{1F952}'; // default: cucumber
  final emojiMatch = emojiRegex.firstMatch(remaining);
  if (emojiMatch != null) {
    emoji = emojiMatch.group(0)!.trim();
    remaining = remaining.substring(emojiMatch.end);
  }

  // Try to extract amount (e.g., "2 tbsp", "1/2 cup", "3")
  final amountRegex = RegExp(
    r'^([\d½¼¾⅓⅔/.\s]+(?:tbsp|tsp|cup|cups|oz|lb|lbs|g|kg|ml|L|pinch|cloves?|bunch|can|slices?|pieces?|medium|large|small)?)\s+',
    caseSensitive: false,
  );
  var amount = '';
  final amountMatch = amountRegex.firstMatch(remaining);
  if (amountMatch != null) {
    amount = amountMatch.group(1)!.trim();
    remaining = remaining.substring(amountMatch.end);
  }

  return _ParsedIngredient(
    emoji: emoji,
    amount: amount,
    name: remaining.trim().isEmpty ? raw : remaining.trim(),
  );
}
