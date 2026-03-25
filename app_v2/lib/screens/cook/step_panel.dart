import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'timer_chip.dart';
import 'voice_bar.dart';

// ── Timer State ───────────────────────────────────────────────────────────────

class TimerState {
  TimerState({
    required this.label,
    required this.totalSeconds,
    required this.remainingSeconds,
    this.isPaused = false,
    this.color = AppColors.amber,
  });

  final String label;
  final int totalSeconds;
  int remainingSeconds;
  bool isPaused;
  Color color;
}

// ── Step Panel ────────────────────────────────────────────────────────────────

/// The right-side panel in cooking mode: step dots, step text, timers, voice.
class StepPanel extends StatelessWidget {
  const StepPanel({
    super.key,
    required this.session,
    required this.currentStepIndex,
    required this.timers,
    required this.voiceBarState,
    this.agentResponseText,
    this.onStepTap,
    this.onTimerTogglePause,
    this.onTimerCancel,
    this.completedStepIndices = const {},
    this.dishNames,
    this.dishColors,
    this.onTextSubmitted,
  });

  final CookingSession session;
  final int currentStepIndex;
  final List<TimerState> timers;
  final VoiceBarState voiceBarState;
  final String? agentResponseText;
  final ValueChanged<int>? onStepTap;
  final ValueChanged<int>? onTimerTogglePause;
  final ValueChanged<int>? onTimerCancel;
  final Set<int> completedStepIndices;
  final ValueChanged<String>? onTextSubmitted;

  /// For multi-recipe sessions: dish names keyed by dish tag.
  final Map<String, String>? dishNames;

  /// For multi-recipe sessions: dish colors keyed by dish tag.
  final Map<String, Color>? dishColors;

  bool get _isMultiRecipe =>
      dishNames != null && dishNames!.length > 1;

  SessionStep? get _currentStep =>
      currentStepIndex < session.steps.length
          ? session.steps[currentStepIndex]
          : null;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkBackground,
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBar(),
          const SizedBox(height: 8),
          Expanded(child: _buildStepArea(context)),
          _buildVoiceBar(),
        ],
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Row(
      children: [
        Expanded(child: _isMultiRecipe ? _buildDishTags() : _buildRecipeName()),
        const SizedBox(width: 12),
        _buildStepDots(),
      ],
    );
  }

  Widget _buildRecipeName() {
    final name = dishNames?.values.firstOrNull ?? '';
    return Text(
      name.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        color: Color(0x59FFFFFF), // rgba(255,255,255,0.35)
        letterSpacing: 1.2,
        fontWeight: FontWeight.w500,
      ),
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDishTags() {
    if (dishNames == null || dishColors == null) return const SizedBox.shrink();
    return Row(
      children: dishNames!.entries.map((entry) {
        final color = dishColors![entry.key] ?? AppColors.amber;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStepDots() {
    final total = session.steps.length;
    if (total == 0) return const SizedBox.shrink();

    final dots = List.generate(total, (i) {
      final isDone = completedStepIndices.contains(i);
      final isActive = i == currentStepIndex;
      return GestureDetector(
        onTap: () => onStepTap?.call(i),
        child: Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone
                ? const Color(0x1E30D158) // rgba(48,209,88,0.12)
                : isActive
                    ? AppColors.amber
                    : const Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
          ),
          alignment: Alignment.center,
          child: isDone
              ? const Text(
                  '\u2713',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.green,
                  ),
                )
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? Colors.black
                        : const Color(0x33FFFFFF), // rgba(255,255,255,0.2)
                  ),
                ),
        ),
      );
    });

    // If 10+ steps, use a scrollable horizontal list centered on active dot
    if (total >= 10) {
      return SizedBox(
        height: 26,
        width: 200,
        child: ListView(
          scrollDirection: Axis.horizontal,
          controller: ScrollController(
            initialScrollOffset:
                (currentStepIndex * 32.0 - 80).clamp(0.0, double.infinity),
          ),
          children: dots,
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }

  // ── Step Area ───────────────────────────────────────────────────────────

  Widget _buildStepArea(BuildContext context) {
    final step = _currentStep;
    if (step == null) {
      return const Center(
        child: Text(
          'No steps available',
          style: TextStyle(color: Color(0x66FFFFFF)),
        ),
      );
    }

    // Split step text into main instruction and detail
    // The step text IS the main text; agentNotes or extra detail is secondary.
    final dishTag = step.sourceDishTag;
    final dishColor = (dishColors != null && dishTag != null)
        ? dishColors![dishTag]
        : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step label
        Row(
          children: [
            if (_isMultiRecipe && dishColor != null) ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: dishColor,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              _isMultiRecipe && dishTag != null && dishNames?[dishTag] != null
                  ? '${dishNames![dishTag]} \u2014 Step ${currentStepIndex + 1}'
                  : 'Step ${currentStepIndex + 1}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.amber,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Main step text
        Text(
          step.text,
          style: AppTextStyles.stepText.copyWith(color: Colors.white),
        ),
        if (step.agentNotes != null && step.agentNotes!.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            step.agentNotes!,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0x66FFFFFF), // rgba(255,255,255,0.4)
              height: 1.65,
            ),
          ),
        ],
        // Timer chips
        if (timers.isNotEmpty) ...[
          const SizedBox(height: 28),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: List.generate(timers.length, (i) {
              final timer = timers[i];
              return TimerChip(
                label: timer.label,
                remainingSeconds: timer.remainingSeconds,
                color: timer.color,
                isPaused: timer.isPaused,
                onTogglePause: () => onTimerTogglePause?.call(i),
                onCancel: () => onTimerCancel?.call(i),
              );
            }),
          ),
        ],
      ],
    );
  }

  // ── Voice Bar ───────────────────────────────────────────────────────────

  Widget _buildVoiceBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: VoiceBar(
        state: voiceBarState,
        agentResponseText: agentResponseText,
        onTextSubmitted: onTextSubmitted,
      ),
    );
  }
}
