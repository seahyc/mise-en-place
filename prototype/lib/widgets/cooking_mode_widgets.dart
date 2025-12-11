import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/cooking_session.dart';
import '../models/instruction.dart';
import '../models/cooking_timer.dart';
import '../widgets/instruction_text.dart';
import '../widgets/streaming_instruction_text.dart';

/// Builds a responsive background with morphing, wave-like colors that react to audio
class ReactiveBackground extends StatelessWidget {
  final double ambientPhase;
  final bool agentIsSpeaking;
  final bool userIsSpeaking;
  final double agentAudioLevel;
  final double userVadScore;
  final Widget child;

  const ReactiveBackground({
    super.key,
    required this.ambientPhase,
    required this.agentIsSpeaking,
    required this.userIsSpeaking,
    required this.agentAudioLevel,
    required this.userVadScore,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Get audio level based on who's speaking
    final double audioLevel = agentIsSpeaking
        ? agentAudioLevel
        : userIsSpeaking
            ? userVadScore
            : 0.0;

    final double intensity = audioLevel.clamp(0.0, 1.0);

    // Base opacity and radius
    final double orangeOpacity;
    final double blueOpacity;
    final double baseRadius;

    if (agentIsSpeaking) {
      orangeOpacity = 0.12 + intensity * 0.25;
      blueOpacity = 0.0;
      baseRadius = 0.8 + intensity * 0.3;
    } else if (userIsSpeaking) {
      orangeOpacity = 0.0;
      blueOpacity = 0.12 + intensity * 0.25;
      baseRadius = 0.8 + intensity * 0.3;
    } else {
      orangeOpacity = 0.08;
      blueOpacity = 0.08;
      baseRadius = 0.7;
    }

    // Phase for trigonometry
    final p = ambientPhase * 2 * math.pi;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF080808),
            Color(0xFF0d0d0d),
            Color(0xFF080808),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Orange wave
          if (orangeOpacity > 0)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      -0.3 + 0.4 * math.sin(p) + 0.15 * math.sin(p * 1.7),
                      -0.2 + 0.3 * math.cos(p * 0.8) + 0.1 * math.cos(p * 1.5),
                    ),
                    radius: baseRadius * (1.2 + 0.2 * math.sin(p * 0.9)),
                    colors: [
                      const Color(0xFFFF8C00).withValues(alpha: orangeOpacity),
                      const Color(0xFFFF6B00).withValues(alpha: orangeOpacity * 0.5),
                      const Color(0xFFFF5500).withValues(alpha: orangeOpacity * 0.2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                  ),
                ),
              ),
            ),

          // Blue wave
          if (blueOpacity > 0)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(
                      0.3 + 0.4 * math.sin(p + math.pi) + 0.15 * math.sin(p * 1.7 + math.pi),
                      0.2 + 0.3 * math.cos(p * 0.8 + math.pi) + 0.1 * math.cos(p * 1.5),
                    ),
                    radius: baseRadius * (1.2 + 0.2 * math.sin(p * 0.9 + math.pi)),
                    colors: [
                      const Color(0xFF00BFFF).withValues(alpha: blueOpacity),
                      const Color(0xFF0099EE).withValues(alpha: blueOpacity * 0.5),
                      const Color(0xFF0077CC).withValues(alpha: blueOpacity * 0.2),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.3, 0.6, 1.0],
                  ),
                ),
              ),
            ),

          // Content
          child,
        ],
      ),
    );
  }
}

/// Step progress bar widget
class StepProgressBars extends StatelessWidget {
  final List<dynamic> activeSteps;
  final CookingSession? session;
  final int currentStepIndex;
  final Set<String> recentlyInsertedStepIds;
  final void Function(int) onNavigateToStep;

  const StepProgressBars({
    super.key,
    required this.activeSteps,
    this.session,
    required this.currentStepIndex,
    required this.recentlyInsertedStepIds,
    required this.onNavigateToStep,
  });

  @override
  Widget build(BuildContext context) {
    final totalSteps = activeSteps.length;
    return Row(
      children: List.generate(totalSteps, (index) {
        final bool isCompleted;
        final bool isNewlyInserted;
        String? stepId;

        if (session != null && index < activeSteps.length) {
          final step = activeSteps[index];
          if (step is SessionStep) {
            isCompleted = step.isCompleted;
            stepId = step.id;
            isNewlyInserted = recentlyInsertedStepIds.contains(step.id);
          } else {
            isCompleted = index < currentStepIndex;
            isNewlyInserted = false;
          }
        } else {
          isCompleted = index < currentStepIndex;
          isNewlyInserted = false;
        }
        final isCurrent = index == currentStepIndex;

        Color barColor;
        List<BoxShadow>? shadows;

        if (isNewlyInserted) {
          barColor = const Color(0xFF4CAF50);
          shadows = [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.6),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ];
        } else if (isCompleted) {
          barColor = Colors.white;
        } else if (isCurrent) {
          barColor = Colors.white;
          shadows = [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.3),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ];
        } else {
          barColor = Colors.white24;
        }

        return Expanded(
          key: stepId != null ? ValueKey('progress-$stepId') : null,
          child: GestureDetector(
            onTap: () => onNavigateToStep(index),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: isCurrent || isNewlyInserted ? 6 : 5,
                margin: EdgeInsets.only(right: index < totalSteps - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: shadows,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Instruction text widget with loading/error states
class CookingInstructionText extends StatelessWidget {
  final bool isLoadingSession;
  final String? sessionError;
  final CookingSession? session;
  final List<dynamic> activeSteps;
  final int currentStepIndex;
  final int currentServings;
  final String unitSystem;
  final Map<String, TextChangeAnimation> pendingTextChanges;
  final void Function(String stepId) onTextChangeAnimationComplete;

  const CookingInstructionText({
    super.key,
    required this.isLoadingSession,
    this.sessionError,
    this.session,
    required this.activeSteps,
    required this.currentStepIndex,
    required this.currentServings,
    required this.unitSystem,
    required this.pendingTextChanges,
    required this.onTextChangeAnimationComplete,
  });

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (isLoadingSession) {
      return Text(
        'Preparing your cooking session...',
        textAlign: TextAlign.center,
        style: GoogleFonts.playfairDisplay(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
          height: 1.4,
        ),
      );
    }

    // Error state
    if (sessionError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Could not start session',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            sessionError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 14,
              color: Colors.white54,
            ),
          ),
        ],
      );
    }

    // Use session step if available
    if (session != null && currentStepIndex < activeSteps.length) {
      final step = activeSteps[currentStepIndex] as SessionStep;

      // Check for pending text change animation
      final pendingChange = pendingTextChanges[step.id];
      if (pendingChange != null) {
        // Clear the pending change after we start animating
        Future.microtask(() => onTextChangeAnimationComplete(step.id));

        return StreamingInstructionText(
          key: ValueKey('streaming-${step.id}-${pendingChange.timestamp.millisecondsSinceEpoch}'),
          step: step,
          oldDescription: pendingChange.oldText,
          textAlign: TextAlign.center,
          baseStyle: GoogleFonts.playfairDisplay(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.4,
          ),
          ingredientColor: const Color(0xFFFFB74D),
          equipmentColor: const Color(0xFF81D4FA),
          unitSystem: unitSystem,
        );
      }

      return InstructionText.fromSessionStep(
        step,
        textAlign: TextAlign.center,
        baseStyle: GoogleFonts.playfairDisplay(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.4,
        ),
        ingredientColor: const Color(0xFFFFB74D),
        equipmentColor: const Color(0xFF81D4FA),
        unitSystem: unitSystem,
      );
    }

    // Fallback to recipe instructions
    if (currentStepIndex < activeSteps.length && activeSteps[currentStepIndex] is InstructionStep) {
      return InstructionText.fromStep(
        activeSteps[currentStepIndex] as InstructionStep,
        textAlign: TextAlign.center,
        baseStyle: GoogleFonts.playfairDisplay(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.4,
        ),
        ingredientColor: const Color(0xFFFFB74D),
        equipmentColor: const Color(0xFF81D4FA),
        paxMultiplier: currentServings.toDouble(),
        unitSystem: unitSystem,
      );
    }

    return Text(
      'No steps available',
      style: GoogleFonts.playfairDisplay(color: Colors.white54),
    );
  }
}

/// Step media widget (images/videos for steps)
class StepMedia extends StatelessWidget {
  final CookingSession? session;
  final List<dynamic> activeSteps;
  final int currentStepIndex;

  const StepMedia({
    super.key,
    this.session,
    required this.activeSteps,
    required this.currentStepIndex,
  });

  String? get _mediaUrl {
    if (session != null && currentStepIndex < activeSteps.length) {
      return (activeSteps[currentStepIndex] as SessionStep).mediaUrl;
    }

    if (currentStepIndex < activeSteps.length && activeSteps[currentStepIndex] is InstructionStep) {
      return (activeSteps[currentStepIndex] as InstructionStep).mediaUrl;
    }

    return null;
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.contains('/video/');
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrl = _mediaUrl;

    if (mediaUrl == null || mediaUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_isVideoUrl(mediaUrl)) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;
    final maxWidth = (screenSize.width * 0.35).clamp(200.0, 350.0);
    final maxHeight = (screenSize.height * 0.35).clamp(180.0, 300.0);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('media-$currentStepIndex'),
        child: ShaderMask(
          shaderCallback: (Rect bounds) {
            return RadialGradient(
              center: Alignment.center,
              radius: 0.85,
              colors: [
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0.0, 0.6, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: maxHeight,
              maxWidth: maxWidth,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                mediaUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: maxHeight * 0.7,
                    width: maxWidth * 0.7,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('[StepMedia] Error loading image: $error');
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Permission request screen
class PermissionScreen extends StatelessWidget {
  final VoidCallback onRequestPermission;

  const PermissionScreen({
    super.key,
    required this.onRequestPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1a1a2e), Color(0xFF16213e)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic_none_rounded,
                  size: 80,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(height: 24),
                Text(
                  "Voice Guidance",
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    "Allow microphone access for hands-free cooking assistance",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: onRequestPermission,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    backgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    "Grant Permission",
                    style: GoogleFonts.lato(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact timer display widget
class CompactTimerWidget extends StatelessWidget {
  final CookingTimer timer;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  const CompactTimerWidget({
    super.key,
    required this.timer,
    required this.onToggle,
    required this.onDismiss,
  });

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = timer.isCompleted;
    final displayLabel = _toTitleCase(timer.label);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isCompleted
            ? const Color(0xFFFF6B6B).withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: isCompleted
            ? Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.5), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Emoji or icon
          Text(
            timer.emoji ?? '⏱️',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 8),
          // Label
          Flexible(
            child: Text(
              displayLabel,
              style: GoogleFonts.lato(
                color: isCompleted ? const Color(0xFFFF6B6B) : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          // Time
          Text(
            timer.displayTime,
            style: GoogleFonts.jetBrainsMono(
              color: isCompleted ? const Color(0xFFFF6B6B) : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          // Action button
          GestureDetector(
            onTap: isCompleted ? onDismiss : onToggle,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isCompleted
                    ? const Color(0xFF4CAF50).withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCompleted
                    ? Icons.check
                    : (timer.isPaused ? Icons.play_arrow : Icons.pause),
                color: isCompleted ? const Color(0xFF4CAF50) : Colors.white70,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Debug status widget for connection info
class DebugStatusWidget extends StatelessWidget {
  final String statusText;
  final bool isConnected;
  final bool isMuted;

  const DebugStatusWidget({
    super.key,
    required this.statusText,
    required this.isConnected,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          if (isMuted) ...[
            const SizedBox(width: 8),
            const Icon(Icons.mic_off, size: 14, color: Colors.red),
          ],
        ],
      ),
    );
  }
}
