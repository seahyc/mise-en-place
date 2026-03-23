import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';

import '../../providers/recipe_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive_layout.dart';
import 'empty_state.dart';
import 'filter_chips.dart';
import 'recipe_card.dart';

class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  int _activeFilter = 0;
  int _currentTab = 0;

  static const _defaultFilters = [
    FilterChipData(label: 'All', isActive: true),
    FilterChipData(label: 'Thai', emoji: '\u{1F1F9}\u{1F1ED}'),
    FilterChipData(label: 'Mexican', emoji: '\u{1F1F2}\u{1F1FD}'),
    FilterChipData(label: 'Italian', emoji: '\u{1F1EE}\u{1F1F9}'),
    FilterChipData(label: 'Vegan', emoji: '\u{1F96C}'),
    FilterChipData(label: 'Favorites', emoji: '\u2B50'),
    FilterChipData(label: 'Imported', emoji: '\u{1F4F1}'),
  ];

  List<FilterChipData> get _filters {
    return _defaultFilters.asMap().entries.map((e) {
      return FilterChipData(
        label: e.value.label,
        emoji: e.value.emoji,
        isActive: e.key == _activeFilter,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final recipesAsync = ref.watch(recipesProvider);
    final deviceType = getDeviceType(context);
    final isPhone = deviceType == DeviceType.phone;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            const SizedBox(height: 12),
            FilterChipsRow(
              chips: _filters,
              onChipTapped: (index) => setState(() => _activeFilter = index),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: recipesAsync.when(
                data: (recipes) => _buildBody(context, recipes),
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.amber),
                ),
                error: (err, _) => Center(
                  child: Text(
                    'Failed to load recipes',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/import'),
        backgroundColor: AppColors.amber,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      floatingActionButtonLocation: isPhone
          ? FloatingActionButtonLocation.endFloat
          : FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: isPhone
          ? BottomNavigationBar(
              currentIndex: _currentTab,
              onTap: (index) => setState(() => _currentTab = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: AppColors.darkBackground,
              selectedItemColor: AppColors.amber,
              unselectedItemColor: AppColors.darkTextTertiary,
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book),
                  label: 'Browse',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.star_outline),
                  label: 'Favorites',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.restaurant),
                  label: 'Cook',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // Logo
          RichText(
            text: const TextSpan(
              style: TextStyle(fontSize: 20, fontFamily: '.SF Pro Text'),
              children: [
                TextSpan(
                  text: 'mise',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: ' en ',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: 'place',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Search field
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                decoration: InputDecoration(
                  hintText: '\u{1F50D} Search recipes...',
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  filled: true,
                  fillColor: AppColors.darkSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(19),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(fontSize: 14, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Avatar
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.amber, Color(0xFFFF6B0A)],
              ),
            ),
            child: const Icon(Icons.person, size: 16, color: Colors.black),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, List recipes) {
    if (recipes.length < 4) {
      return EmptyState(
        recipes: recipes.cast(),
        onImportTap: () => context.push('/import'),
        onCreateTap: () {
          // TODO: navigate to create recipe
        },
        onRecipeTap: (r) => context.push('/recipes/${r.id}'),
      );
    }

    final deviceType = getDeviceType(context);
    final crossAxisCount = switch (deviceType) {
      DeviceType.largeTablet => 4,
      DeviceType.tablet => 3,
      DeviceType.phone => 2,
    };

    return MasonryGridView.count(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: const EdgeInsets.all(16),
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return RecipeCard(
          recipe: recipe,
          onTap: () => context.push('/recipes/${recipe.id}'),
        );
      },
    );
  }
}
