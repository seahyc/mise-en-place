import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../services/recipe_service.dart';
import '../widgets/instruction_text.dart';

class RecipeDetailScreen extends StatefulWidget {
  final String recipeId;
  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isMetric = true;
  int? _currentPax;
  final Set<int> _checkedIngredients = {};
  late Future<Recipe?> _recipeFuture;

  void _toggleIngredient(int index) {
    setState(() {
      if (_checkedIngredients.contains(index)) {
        _checkedIngredients.remove(index);
      } else {
        _checkedIngredients.add(index);
      }
    });
  }

  // Watercolor Palette
  final Color _paperColor = const Color(0xFFFAFAF5);
  final Color _textCharcoal = const Color(0xFF2C2C2C);
  final Color _watercolorOrange = const Color(0xFFFBE4D5);
  final Color _watercolorBlue = const Color(0xFFE3EFF3);
  final Color _watercolorGreen = const Color(0xFFE0F2F1);

  @override
  void initState() {
    super.initState();
    _recipeFuture = context.read<RecipeService>().getRecipeById(widget.recipeId);
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Scaffold(
        backgroundColor: _paperColor,
        body: FutureBuilder<Recipe?>(
        future: _recipeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}", style: GoogleFonts.lato()));
          } else if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text("Recipe not found"));
          }

          final recipe = snapshot.data!;
          // Initialize pax from recipe base once
          _currentPax ??= recipe.basePax == 0 ? 1 : recipe.basePax;
          final currentPax = _currentPax ?? 1;
          return Stack(
            children: [
              CustomScrollView(
                clipBehavior: Clip.none,
                slivers: [
                  _buildAppBar(recipe),
                  SliverToBoxAdapter(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _paperColor,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeaderControls(recipe, currentPax),
                                const SizedBox(height: 32),
                                _sectionHeading("Ingredients"),
                                _buildIngredientsList(recipe, currentPax),
                                const SizedBox(height: 32),
                                _sectionHeading("Equipment"),
                                _buildEquipmentList(recipe),
                                const SizedBox(height: 32),
                                _sectionHeading("Instructions"),
                                _buildInstructionsSection(recipe),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: _BreathingOrbitButton(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/cook/${recipe.id}',
                        arguments: recipe,
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _paxPill({
    required int currentPax,
    required Color textColor,
    required Color background,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPaxButton(icon: Icons.remove, onTap: onDecrement),
          const SizedBox(width: 8),
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: textColor.withValues(alpha: 0.7)),
              const SizedBox(width: 4),
              Text(
                "$currentPax pax",
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          _buildPaxButton(icon: Icons.add, onTap: onIncrement),
        ],
      ),
    );
  }

  Widget _buildAppBar(Recipe recipe) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 350,
        child: Stack(
          children: [
            // BOTTOM LAYER: Hero image with gradient overlay
            Hero(
              tag: 'recipe_image_${recipe.id}',
              child: Image.network(
                recipe.mainImageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
              ),
            ),
            // Grey gradient overlay on the image
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0), // Fully transparent at top
                      Colors.black.withValues(alpha: 0.2), // Darker at middle
                      Colors.black.withValues(alpha: 0.6), // Very dark at bottom
                    ],
                  ),
                ),
              ),
            ),
            // Curved white overlay panel at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: _paperColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(48),
                    topRight: Radius.circular(48),
                  ),
                ),
              ),
            ),
            // Back button at top-left
            Positioned(
              top: 16,
              left: 16,
              child: CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.9),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87, size: 24),
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderControls(Recipe recipe, int currentPax) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          recipe.title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            color: _textCharcoal,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildWatercolorTag(recipe.cuisine.name.toUpperCase(), _watercolorOrange),
            const SizedBox(width: 8),
            _buildWatercolorTag("${recipe.prepTimeMinutes + recipe.cookTimeMinutes} MIN", _watercolorBlue),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _paxPill(
              currentPax: currentPax,
              textColor: _textCharcoal,
              background: Colors.white,
              onDecrement: () {
                if ((_currentPax ?? recipe.basePax) > 1) {
                  setState(() => _currentPax = (currentPax - 1).clamp(1, 9999));
                }
              },
              onIncrement: () => setState(() => _currentPax = currentPax + 1),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0.08, 0),
                  end: Offset.zero,
                ).animate(animation);
                final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
                return FadeTransition(
                  opacity: fade,
                  child: SlideTransition(position: offset, child: child),
                );
              },
              child: Row(
                key: ValueKey(_isMetric),
                children: [
                  _UnitToggle(
                    isMetric: _isMetric,
                    onChanged: (val) => setState(() => _isMetric = val),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWatercolorTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.lato(
          fontSize: 11,
          color: _textCharcoal,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _sectionHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 16),
      child: Text(
        text,
        style: GoogleFonts.playfairDisplay(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: _textCharcoal,
        ),
      ),
    );
  }

  Widget _buildIngredientsList(Recipe recipe, int currentPax) {
    // Determine scaling ratio
    final basePax = recipe.basePax == 0 ? 1 : recipe.basePax;
    final ratio = currentPax / basePax;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.02),
            blurRadius: 10,
            offset: const Offset(0, 4)
          )
        ]
      ),
      child: Column(
        children: [
          // Header Row with Title and Serving Adjuster
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "",
                style: GoogleFonts.playfairDisplay(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold, 
                  color: _textCharcoal
                ),
              ),
              
              // Serving Size Adjuster (Pax Control)
              const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 24),
          
          ...recipe.ingredients.asMap().entries.map((entry) {
            final index = entry.key;
            final ing = entry.value;
            final scaledIng = ing.scaled(ratio);

            return Padding(
              padding: const EdgeInsets.only(bottom: 20), // Spacing between rows
              child: TweenAnimationBuilder<double>(
                  // ... Keep existing animation logic or simplify
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 600 + (index * 100)),
                  curve: Curves.easeOutQuart,
                  builder: (context, val, child) {
                    return Opacity(
                      opacity: val,
                      child: Transform.translate(
                          offset: Offset(0, 20 * (1 - val)),
                          child: child
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      // Checkbox
                      InkWell(
                        onTap: () => _toggleIngredient(index),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _checkedIngredients.contains(index)
                                ? _watercolorGreen
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _checkedIngredients.contains(index)
                                  ? _watercolorGreen
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                          ),
                          child: _checkedIngredients.contains(index)
                              ? Icon(Icons.check, size: 16, color: Colors.teal.shade700)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Text
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: _checkedIngredients.contains(index) ? 10 : 0,
                            vertical: _checkedIngredients.contains(index) ? 6 : 0,
                          ),
                          decoration: _checkedIngredients.contains(index)
                              ? BoxDecoration(
                                  color: const Color(0xFFE7F6F0), // softer mint wash
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF8BCFB1).withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                      offset: const Offset(-2, 3),
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFF6ABF9C).withValues(alpha: 0.06),
                                      blurRadius: 18,
                                      spreadRadius: -4,
                                      offset: const Offset(2, -2),
                                    ),
                                  ],
                                )
                              : null,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              color: _textCharcoal,
                              fontWeight: _checkedIngredients.contains(index) ? FontWeight.w600 : FontWeight.normal,
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.lato(
                                  fontSize: 16,
                                  color: _textCharcoal,
                                  fontWeight: _checkedIngredients.contains(index) ? FontWeight.w600 : FontWeight.normal,
                                ),
                                children: [
                                  TextSpan(
                                    text: _formatNumberOnly(scaledIng.amount, scaledIng.unit, _isMetric),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(
                                    text: " ${_getUnitName(scaledIng.amount, scaledIng.unit, _isMetric)} ",
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  WidgetSpan(
                                    child: _HoverableIngredientText(
                                      text: scaledIng.master.name,
                                      imageUrl: scaledIng.master.imageUrl,
                                      style: GoogleFonts.lato(
                                        fontSize: 16,
                                        color: _textCharcoal,
                                        fontWeight: _checkedIngredients.contains(index) ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPaxButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha:0.05), blurRadius: 4, offset: const Offset(0, 2))
          ]
        ),
        child: Icon(icon, size: 16, color: _textCharcoal),
      ),
    );
  }

  Widget _buildEquipmentList(Recipe recipe) {
    return Container(
      padding: const EdgeInsets.all(24),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: recipe.equipmentNeeded.map((eq) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: _buildIcon(eq.iconUrl, size: 20)),
                const SizedBox(width: 12),
                _HoverableIngredientText(
                  text: eq.name,
                  imageUrl: eq.imageUrl,
                  style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.w500, color: _textCharcoal),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInstructionsSection(Recipe recipe) {
    // Calculate pax multiplier for step-level scaling
    final basePax = recipe.basePax == 0 ? 1 : recipe.basePax;
    final paxMultiplier = (_currentPax ?? basePax) / basePax;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: recipe.instructions.map((step) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _watercolorOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${step.orderIndex + 1}",
                    style: GoogleFonts.playfairDisplay(
                      color: Colors.brown.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: InstructionText.fromStep(
                    step,
                    baseStyle: GoogleFonts.lato(color: _textCharcoal, height: 1.6, fontSize: 16),
                    ingredientColor: const Color(0xFFE07C24), // Warm orange for ingredients
                    equipmentColor: const Color(0xFF5B9BD5), // Cool blue for equipment
                    paxMultiplier: paxMultiplier,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildIcon(String? url, {double size = 24}) {
    if (url != null && url.startsWith('http')) {
      return Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Text("🥣", style: TextStyle(fontSize: size)),
      );
    }
    return Text(url ?? "🥣", style: TextStyle(fontSize: size));
  }

  String _formatNumberOnly(double amount, String unit, bool toMetric) {
    final (val, _) = _convert(amount, unit, toMetric);
    return _formatNumber(val);
  }

  String _getUnitName(double amount, String unit, bool toMetric) {
    final (val, outUnit) = _convert(amount, unit, toMetric);
    return _pluralizeUnit(outUnit, val);
  }

  (double, String) _convert(double amount, String unit, bool toMetric) {
    final u = unit.toLowerCase();
    double val = amount;
    String outUnit = unit;

    if (toMetric) {
      switch (u) {
        case 'oz':
          val = amount * 28.3495;
          outUnit = val >= 1000 ? 'kg' : 'g';
          if (outUnit == 'kg') val /= 1000;
          break;
        case 'lb':
          val = amount * 453.592;
          outUnit = 'kg';
          val /= 1000;
          break;
        case 'cup':
          val = amount * 240;
          outUnit = val >= 1000 ? 'L' : 'ml';
          if (outUnit == 'L') val /= 1000;
          break;
        case 'tbsp':
          val = amount * 15;
          outUnit = 'ml';
          break;
        case 'tsp':
          val = amount * 5;
          outUnit = 'ml';
          break;
        case 'fl oz':
          val = amount * 29.5735;
          outUnit = 'ml';
          break;
        default:
          outUnit = unit;
      }
    } else {
      switch (u) {
        case 'g':
          val = amount * 0.035274;
          if (val >= 16) {
            outUnit = 'lb';
            val /= 16;
          } else {
            outUnit = 'oz';
          }
          break;
        case 'kg':
          val = amount * 2.20462;
          outUnit = 'lb';
          break;
        case 'ml':
          if (amount >= 240) {
            val = amount / 240;
            outUnit = 'cup';
          } else if (amount >= 15) {
            val = amount / 15;
            outUnit = 'tbsp';
          } else {
            val = amount / 5;
            outUnit = 'tsp';
          }
          break;
        case 'l':
          val = amount * 4.22675;
          outUnit = 'cup';
          break;
        default:
          outUnit = unit;
      }
    }
    return (val, outUnit);
  }

  String _formatNumber(double value) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);
  }

  String _pluralizeUnit(String unit, double value) {
    if ((value - 1).abs() < 1e-9) return unit;
    final shortUnits = {'g', 'kg', 'oz', 'lb', 'ml', 'l', 'fl oz'};
    if (shortUnits.contains(unit.toLowerCase())) return unit;
    if (unit.toLowerCase().endsWith('s')) return unit;
    return "${unit}s";
  }
}

// Floating earthy button with shimmer effect for "Start Cooking"
class _BreathingOrbitButton extends StatefulWidget {
  final VoidCallback onTap;
  const _BreathingOrbitButton({required this.onTap});

  @override
  State<_BreathingOrbitButton> createState() => _BreathingOrbitButtonState();
}

class _BreathingOrbitButtonState extends State<_BreathingOrbitButton> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _shimmerController;
  late AnimationController _waveController;
  late Animation<double> _breatheAnimation;

  // Earthy brown colors
  static const Color _primaryBrown = Color(0xFF5D4037);  // Medium brown
  static const Color _darkBrown = Color(0xFF3E2723);     // Dark brown
  static const Color _lightBrown = Color(0xFF8D6E63);    // Light brown
  static const Color _shimmerGold = Color(0xFFD7CCC8);   // Warm shimmer

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _breatheAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOutSine),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _shimmerController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathingController, _shimmerController, _waveController]),
      builder: (context, child) {
        final shimmerAngle = _shimmerController.value * 2 * math.pi;
        final wavePhase = _waveController.value * 2 * math.pi;

        // Create wave effect by oscillating gradient stops
        final wave1 = 0.15 + 0.1 * math.sin(wavePhase);
        final wave2 = 0.5 + 0.15 * math.sin(wavePhase + math.pi * 0.5);
        final wave3 = 0.85 + 0.1 * math.sin(wavePhase + math.pi);

        return Transform.scale(
          scale: _breatheAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              // Floating shadow effect - multiple layered shadows
              boxShadow: [
                // Ambient shadow (soft, wide)
                BoxShadow(
                  color: _darkBrown.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 0,
                  offset: const Offset(0, 20),
                ),
                // Main floating shadow
                BoxShadow(
                  color: _darkBrown.withValues(alpha: 0.35),
                  blurRadius: 25,
                  spreadRadius: -5,
                  offset: const Offset(0, 15),
                ),
                // Close contact shadow
                BoxShadow(
                  color: _darkBrown.withValues(alpha: 0.2),
                  blurRadius: 10,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CustomPaint(
              painter: _ShimmerBorderPainter(
                shimmerAngle: shimmerAngle,
                borderRadius: 40,
                shimmerColor: _shimmerGold,
                baseColor: _lightBrown.withValues(alpha: 0.3),
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      _darkBrown,
                      _primaryBrown,
                      _lightBrown,
                      _primaryBrown,
                      _darkBrown,
                    ],
                    stops: [0.0, wave1, wave2, wave3, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(40),
                    splashColor: _shimmerGold.withValues(alpha: 0.3),
                    highlightColor: _lightBrown.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.restaurant_menu, color: Colors.white, size: 22),
                          const SizedBox(width: 12),
                          Text(
                            "Start Cooking",
                            style: GoogleFonts.playfairDisplay(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Custom painter for animated shimmer border effect
class _ShimmerBorderPainter extends CustomPainter {
  final double shimmerAngle;
  final double borderRadius;
  final Color shimmerColor;
  final Color baseColor;

  _ShimmerBorderPainter({
    required this.shimmerAngle,
    required this.borderRadius,
    required this.shimmerColor,
    required this.baseColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // Calculate shimmer position along the border
    final shimmerX = size.width / 2 + (size.width / 2 + 20) * math.cos(shimmerAngle);
    final shimmerY = size.height / 2 + (size.height / 2 + 20) * math.sin(shimmerAngle);

    // Create gradient that follows the shimmer position
    final gradient = RadialGradient(
      center: Alignment(
        (shimmerX / size.width) * 2 - 1,
        (shimmerY / size.height) * 2 - 1,
      ),
      radius: 0.8,
      colors: [
        shimmerColor.withValues(alpha: 0.9),
        shimmerColor.withValues(alpha: 0.4),
        baseColor.withValues(alpha: 0.2),
        Colors.transparent,
      ],
      stops: const [0.0, 0.2, 0.5, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRRect(rrect, paint);

    // Add a subtle inner glow
    final innerGlowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (shimmerX / size.width) * 2 - 1,
          (shimmerY / size.height) * 2 - 1,
        ),
        radius: 1.2,
        colors: [
          shimmerColor.withValues(alpha: 0.15),
          Colors.transparent,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(rrect.deflate(1), innerGlowPaint);
  }

  @override
  bool shouldRepaint(_ShimmerBorderPainter oldDelegate) {
    return oldDelegate.shimmerAngle != shimmerAngle;
  }
}

// Custom painter that draws the curved top edge shape with shadows
class _CurvedTopEdgePainter extends CustomPainter {
  final Color backgroundColor;
  final double curveDepth;
  final Color? borderColor;
  final Color? shadowColor;

  _CurvedTopEdgePainter({
    required this.backgroundColor,
    this.curveDepth = 40,
    this.borderColor,
    this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('🎨 _CurvedTopEdgePainter: size=$size, curveDepth=$curveDepth');

    final path = Path();

    // Start from top-left corner
    path.moveTo(0, 0);

    // Flat section at top left
    path.lineTo(curveDepth * 2, 0);

    // Left curve that dips DOWN into the content
    path.quadraticBezierTo(
      curveDepth * 3, // control point x
      curveDepth * 2, // control point y (dips down)
      curveDepth * 4, // end point x
      0, // end point y (returns to baseline)
    );

    // Middle flat section
    path.lineTo(size.width - (curveDepth * 4), 0);

    // Right curve that dips DOWN into the content
    path.quadraticBezierTo(
      size.width - (curveDepth * 3), // control point x
      curveDepth * 2, // control point y (dips down)
      size.width - (curveDepth * 2), // end point x
      0, // end point y (returns to baseline)
    );

    // Complete top edge
    path.lineTo(size.width, 0);

    // Right edge
    path.lineTo(size.width, size.height);

    // Bottom edge
    path.lineTo(0, size.height);

    // Close the path
    path.close();

    // Draw shadows first (underneath, casting upward onto image)
    if (shadowColor != null) {
      // Create a path just for the curved top edge
      final shadowPath = Path();
      shadowPath.moveTo(0, 0);
      shadowPath.lineTo(curveDepth * 2, 0);
      shadowPath.quadraticBezierTo(curveDepth * 3, curveDepth * 2, curveDepth * 4, 0);
      shadowPath.lineTo(size.width - (curveDepth * 4), 0);
      shadowPath.quadraticBezierTo(size.width - (curveDepth * 3), curveDepth * 2, size.width - (curveDepth * 2), 0);
      shadowPath.lineTo(size.width, 0);
      shadowPath.lineTo(size.width, 80); // Extend down for shadow area
      shadowPath.lineTo(0, 80);
      shadowPath.close();

      // Draw multiple shadow layers for depth
      canvas.save();
      canvas.translate(0, -20); // Shift shadow up to cast on image above
      final shadowPaint1 = Paint()
        ..color = shadowColor!.withValues(alpha: shadowColor!.a * 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
      canvas.drawPath(shadowPath, shadowPaint1);
      canvas.restore();

      canvas.save();
      canvas.translate(0, -10);
      final shadowPaint2 = Paint()
        ..color = shadowColor!.withValues(alpha: shadowColor!.a * 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
      canvas.drawPath(shadowPath, shadowPaint2);
      canvas.restore();
    }

    // Fill the background
    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // Draw border if specified (for debugging)
    if (borderColor != null) {
      final borderPaint = Paint()
        ..color = borderColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8; // THICK border for visibility
      canvas.drawPath(path, borderPaint);
    }

    print('✅ _CurvedTopEdgePainter: painted successfully');
  }

  @override
  bool shouldRepaint(_CurvedTopEdgePainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.curveDepth != curveDepth ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.shadowColor != shadowColor;
  }
}

// Custom painter to draw shadow beneath the curved panel
class _CurvedPanelShadowPainter extends CustomPainter {
  final Color shadowColor;
  final double curveDepth;

  _CurvedPanelShadowPainter({
    required this.shadowColor,
    this.curveDepth = 24,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    // Match the new clip path shape - curved down on left and right
    path.moveTo(0, 0);

    // Left side curve down
    path.quadraticBezierTo(
      curveDepth * 1.5,
      curveDepth,
      size.width / 2,
      0,
    );

    // Right side curve down
    path.quadraticBezierTo(
      size.width - (curveDepth * 1.5),
      curveDepth,
      size.width,
      0,
    );

    // Extend below to create shadow area
    path.lineTo(size.width, 60);
    path.lineTo(0, 60);
    path.close();

    // Draw multiple shadow layers for depth
    final shadowPaint1 = Paint()
      ..color = shadowColor.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);

    final shadowPaint2 = Paint()
      ..color = shadowColor.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);

    final shadowPaint3 = Paint()
      ..color = shadowColor.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

    // Offset shadows upward to cast onto the image above
    canvas.save();
    canvas.translate(0, -25);
    canvas.drawPath(path, shadowPaint3);
    canvas.restore();

    canvas.save();
    canvas.translate(0, -12);
    canvas.drawPath(path, shadowPaint1);
    canvas.restore();

    canvas.save();
    canvas.translate(0, -6);
    canvas.drawPath(path, shadowPaint2);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurvedPanelShadowPainter oldDelegate) {
    return oldDelegate.shadowColor != shadowColor ||
        oldDelegate.curveDepth != curveDepth;
  }
}

// Unit toggle widget
class _UnitToggle extends StatelessWidget {
  final bool isMetric;
  final ValueChanged<bool> onChanged;

  const _UnitToggle({required this.isMetric, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha:0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(label: "Metric", selected: isMetric, icon: Icons.scale_outlined, onTap: () => onChanged(true)),
          const SizedBox(width: 4),
          _buildOption(label: "Imperial", selected: !isMetric, icon: Icons.flag_outlined, onTap: () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _buildOption({required String label, required bool selected, required IconData icon, required VoidCallback onTap}) {
    final textColor = selected ? Colors.black87 : Colors.grey.shade400;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: selected
            ? BoxDecoration(
                color: const Color(0xFFE3EFF3),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[Icon(icon, size: 14, color: Colors.black54), const SizedBox(width: 4)],
            Text(
              label,
              style: GoogleFonts.lato(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Hoverable text widget that shows image preview on hover
class _HoverableIngredientText extends StatefulWidget {
  final String text;
  final String? imageUrl;
  final TextStyle style;

  const _HoverableIngredientText({
    required this.text,
    required this.imageUrl,
    required this.style,
  });

  @override
  State<_HoverableIngredientText> createState() => _HoverableIngredientTextState();
}

class _HoverableIngredientTextState extends State<_HoverableIngredientText> {
  bool _isHovering = false;
  OverlayEntry? _overlayEntry;

  void _showOverlay(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Calculate position to keep overlay on screen
    double left = offset.dx;
    double top = offset.dy + size.height + 8;

    // Adjust if overlay would go off right edge
    if (left + 200 > screenSize.width) {
      left = screenSize.width - 210;
    }

    // Adjust if overlay would go off bottom edge
    if (top + 200 > screenSize.height) {
      top = offset.dy - 208; // Show above instead
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              widget.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovering = true);
        _showOverlay(context);
      },
      onExit: (_) {
        setState(() => _isHovering = false);
        _hideOverlay();
      },
      cursor: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
            ? () {
                if (_overlayEntry == null) {
                  _showOverlay(context);
                } else {
                  _hideOverlay();
                }
              }
            : null,
        child: Text(
          widget.text,
          style: widget.style.copyWith(
            decoration: _isHovering && widget.imageUrl != null && widget.imageUrl!.isNotEmpty
                ? TextDecoration.underline
                : null,
          ),
        ),
      ),
    );
  }
}

// CustomClipper for curved top edge
class _CurvedTopEdgeClipper extends CustomClipper<Path> {
  final double curveDepth;

  _CurvedTopEdgeClipper({required this.curveDepth});

  @override
  Path getClip(Size size) {
    final path = Path();

    // Number of scallops across the width
    const scallops = 8;
    final scallopsWidth = size.width / scallops;

    // Start from top-left corner
    path.moveTo(0, curveDepth);

    // Create continuous wavy scallops across the entire top edge
    for (int i = 0; i < scallops; i++) {
      final startX = i * scallopsWidth;
      final endX = (i + 1) * scallopsWidth;
      final midX = startX + (scallopsWidth / 2);

      // Each scallop curves UP (to y=0) and back down (to curveDepth)
      path.quadraticBezierTo(
        midX,      // control point x (middle of scallop)
        0,         // control point y (curves up to top)
        endX,      // end point x
        curveDepth, // end point y (back down to baseline)
      );
    }

    // Complete the rectangle from top-right down
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(_CurvedTopEdgeClipper oldClipper) {
    return oldClipper.curveDepth != curveDepth;
  }
}

// Fade page transition for cooking mode
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  FadePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        );
}
