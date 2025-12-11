import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import '../services/auth_service.dart';
import 'settings_screen.dart';

class RecipeListScreen extends StatefulWidget {
  const RecipeListScreen({super.key});

  @override
  State<RecipeListScreen> createState() => _RecipeListScreenState();
}

class _RecipeListScreenState extends State<RecipeListScreen> {
  late Future<List<Recipe>> _recipesFuture;

  // Watercolor aesthetic colors
  final Color _paperColor = const Color(0xFFFAFAF5); // Warm paper white
  final Color _textCharcoal = const Color(0xFF2C2C2C); // Soft charcoal
  final Color _watercolorBlue = const Color(0xFFE3EFF3); // Gentle wash blue
  final Color _watercolorOrange = const Color(0xFFFBE4D5); // Gentle wash orange

  @override
  void initState() {
    super.initState();
    _recipesFuture = context.read<RecipeService>().getRecipes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paperColor, 
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: _paperColor,
            expandedHeight: 180.0,
            floating: false,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                'What do you want to cook?',
                style: GoogleFonts.playfairDisplay(
                  color: _textCharcoal,
                  fontSize: 28, // Slightly smaller to fit better
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              background: Container(
                color: _paperColor,
              ),
            ),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 20.0),
                child: _UserProfileButton(),
              ),
            ],
          ),
          
          FutureBuilder<List<Recipe>>(
            future: _recipesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
              } else if (snapshot.hasError) {
                 return SliverFillRemaining(child: Center(child: Text("Error: ${snapshot.error}")));
              } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                 return const SliverFillRemaining(child: Center(child: Text("No recipes found.")));
              }

              final recipes = snapshot.data!;
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400, // Responsive
                    childAspectRatio: 0.82, // Slightly taller for elegance
                    crossAxisSpacing: 24,
                    mainAxisSpacing: 32, // More vertical breathing room
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final recipe = recipes[index];
                      return _RecipeCard(
                        recipe: recipe, 
                        tagsColor: index % 2 == 0 ? _watercolorOrange : _watercolorBlue
                      );
                    },
                    childCount: recipes.length,
                  ),
                ),
              );
            },
          ),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 60)),
        ],
      ),
    );
  }
}

class _UserProfileButton extends StatelessWidget {
  const _UserProfileButton();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final initials = (user?.email?.isNotEmpty == true) 
        ? user!.email![0].toUpperCase() 
        : 'U';

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      shadowColor: Colors.black12, // Softer shadow
      color: const Color(0xFFFAFAF5),
      icon: Container(
        padding: const EdgeInsets.all(2), // Border gap
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Colors.grey.shade200,
          child: Text(
            initials,
            style: GoogleFonts.playfairDisplay(
              color: Colors.black87, 
              fontWeight: FontWeight.bold
            ),
          ),
        ),
      ),
      onSelected: (value) async {
        if (value == 'logout') {
          await context.read<AuthService>().signOut();
          if (context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
        } else if (value == 'settings') {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Account", style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'Guest', 
                style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 20, color: Colors.black87),
              const SizedBox(width: 12),
              Text("Settings", style: GoogleFonts.lato()),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: Colors.redAccent.shade200),
              const SizedBox(width: 12),
              Text("Log Out", style: GoogleFonts.lato(color: Colors.redAccent.shade200)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final Color tagsColor; // Alternating pastel colors
  const _RecipeCard({required this.recipe, required this.tagsColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushNamed('/recipe/${recipe.id}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          // Minimalist shadow: very soft, almost invisible, just lifting it slightly
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 11, // Slightly more image focus
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Hero(
                  tag: 'recipe_image_${recipe.id}',
                  child: Image.network(
                    recipe.mainImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_,__,___) => Container(
                      color: Colors.grey[100],
                      child: Icon(Icons.restaurant, color: Colors.grey.shade300, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 9,
              child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.playfairDisplay( // Elegant Serif Title
                              fontSize: 20,
                              fontWeight: FontWeight.w700, 
                              height: 1.2,
                              color: const Color(0xFF2C2C2C),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recipe.description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.lato( // Clean Sans Body
                              fontSize: 13, 
                              color: Colors.grey.shade600, 
                              height: 1.4,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          _buildWatercolorTag(recipe.cuisine.name.toUpperCase()),
                          const SizedBox(width: 8),
                          _buildWatercolorTag("${recipe.prepTimeMinutes + recipe.cookTimeMinutes} min".toUpperCase()),
                        ],
                      ),
                    ],
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatercolorTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tagsColor.withValues(alpha: 0.5), // Watercolor wash
        borderRadius: BorderRadius.circular(20), // Soft rounded
      ),
      child: Text(
        text,
        style: GoogleFonts.lato(
          fontSize: 10, 
          color: Colors.black87, 
          fontWeight: FontWeight.w600, 
          letterSpacing: 1.0
        ),
      ),
    );
  }
}
