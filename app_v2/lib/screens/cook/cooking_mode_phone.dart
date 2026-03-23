import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'step_panel.dart';
import 'timer_chip.dart';
import 'voice_bar.dart';

/// Phone-optimized cooking mode: full-screen dark layout with swipeable steps,
/// collapsible ingredient row, and voice bar at the bottom.
class CookingModePhone extends StatefulWidget {
  const CookingModePhone({
    super.key,
    required this.session,
    required this.currentStepIndex,
    required this.completedSteps,
    required this.timers,
    required this.voiceBarState,
    this.agentResponseText,
    this.onStepChanged,
    this.onTimerTogglePause,
    this.onTimerCancel,
    this.onClose,
  });

  final CookingSession session;
  final int currentStepIndex;
  final Set<int> completedSteps;
  final List<TimerState> timers;
  final VoiceBarState voiceBarState;
  final String? agentResponseText;
  final ValueChanged<int>? onStepChanged;
  final ValueChanged<int>? onTimerTogglePause;
  final ValueChanged<int>? onTimerCancel;
  final VoidCallback? onClose;

  @override
  State<CookingModePhone> createState() => _CookingModePhoneState();
}

class _CookingModePhoneState extends State<CookingModePhone> {
  late PageController _pageController;
  bool _ingredientsExpanded = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.currentStepIndex);
  }

  @override
  void didUpdateWidget(CookingModePhone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStepIndex != widget.currentStepIndex) {
      _pageController.animateToPage(
        widget.currentStepIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Ingredient data (placeholder for backend-supplied data) ─────────────

  List<String> get _ingredients => [];

  List<String> get _ingredientEmojis {
    // Extract just the emoji from each ingredient for collapsed view
    return _ingredients.map((ing) {
      final trimmed = ing.trim();
      if (trimmed.isEmpty) return '\u{1F958}'; // 🥘
      final firstRune = trimmed.runes.first;
      if (firstRune > 0x1F000) {
        final spaceIdx = trimmed.indexOf(' ');
        return spaceIdx > 0 ? trimmed.substring(0, spaceIdx) : trimmed;
      }
      return '\u{1F958}'; // 🥘
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Close button row
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible ingredient row
            if (_ingredients.isNotEmpty) _buildIngredientSection(),

            // Step PageView
            Expanded(child: _buildStepPageView()),

            // Timer chips
            if (widget.timers.isNotEmpty) _buildTimerRow(),

            // Voice bar at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: VoiceBar(
                state: widget.voiceBarState,
                agentResponseText: widget.agentResponseText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Ingredient Section ──────────────────────────────────────────────────

  Widget _buildIngredientSection() {
    return GestureDetector(
      onTap: () => setState(() => _ingredientsExpanded = !_ingredientsExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        constraints: _ingredientsExpanded
            ? BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4)
            : const BoxConstraints(maxHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: _ingredientsExpanded
            ? _buildExpandedIngredients()
            : _buildCollapsedIngredients(),
      ),
    );
  }

  Widget _buildCollapsedIngredients() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _ingredientEmojis.map((emoji) {
          return Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0x14FFFFFF),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildExpandedIngredients() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: _ingredients.map((ing) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              ing,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0x99FFFFFF),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Step PageView ───────────────────────────────────────────────────────

  Widget _buildStepPageView() {
    final steps = widget.session.steps;
    if (steps.isEmpty) {
      return const Center(
        child: Text(
          'No steps',
          style: TextStyle(color: Color(0x66FFFFFF)),
        ),
      );
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: steps.length,
      onPageChanged: (index) => widget.onStepChanged?.call(index),
      itemBuilder: (context, index) {
        final step = steps[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Step number
              Text(
                'STEP ${index + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.amber,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              // Step text
              Text(
                step.text,
                style: AppTextStyles.stepText.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              if (step.agentNotes != null &&
                  step.agentNotes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  step.agentNotes!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0x66FFFFFF),
                    height: 1.65,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Timer Row ───────────────────────────────────────────────────────────

  Widget _buildTimerRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(widget.timers.length, (i) {
            final timer = widget.timers[i];
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TimerChip(
                label: timer.label,
                remainingSeconds: timer.remainingSeconds,
                color: timer.color,
                isPaused: timer.isPaused,
                onTogglePause: () => widget.onTimerTogglePause?.call(i),
                onCancel: () => widget.onTimerCancel?.call(i),
              ),
            );
          }),
        ),
      ),
    );
  }
}
