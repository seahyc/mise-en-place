import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_colors.dart';
import 'recipe_card.dart';

/// Returns null when recipe count >= 4 (caller should use masonry grid).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.recipes,
    required this.onImportTap,
    required this.onCreateTap,
    required this.onRecipeTap,
  });

  final List<Recipe> recipes;
  final VoidCallback onImportTap;
  final VoidCallback onCreateTap;
  final ValueChanged<Recipe> onRecipeTap;

  @override
  Widget build(BuildContext context) {
    if (recipes.length >= 4) {
      // Caller should use masonry grid instead.
      return const SizedBox.shrink();
    }

    if (recipes.isEmpty) {
      return _buildZeroState(context);
    }

    return _buildSparseState(context);
  }

  Widget _buildZeroState(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '\u{1F373}',
                    style: TextStyle(fontSize: 64),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Your kitchen awaits',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import a recipe from TikTok or YouTube,\nor create one from scratch.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onImportTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '\u{1F4F1} Import your first recipe',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: onCreateTap,
                    child: Text(
                      'or create one from scratch \u2192',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSparseState(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 260,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...recipes.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 200,
                      child: RecipeCard(
                        recipe: r,
                        onTap: () => onRecipeTap(r),
                      ),
                    ),
                  ),
                ),
                _buildDashedImportCard(),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'QUICK START',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.darkTextTertiary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickStartCard(
                  emoji: '\u{1F4F1}',
                  title: 'TikTok',
                  subtitle: 'Import a recipe',
                  onTap: onImportTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickStartCard(
                  emoji: '\u25B6\uFE0F',
                  title: 'YouTube',
                  subtitle: 'Import a recipe',
                  onTap: onImportTap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickStartCard(
                  emoji: '\u270D\uFE0F',
                  title: 'Write Your Own',
                  subtitle: 'Create from scratch',
                  onTap: onCreateTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashedImportCard() {
    return GestureDetector(
      onTap: onImportTap,
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            // Dashed border approximated with thin solid border
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add,
                size: 32,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 8),
              Text(
                'Import a recipe',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStartCard extends StatelessWidget {
  const _QuickStartCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
