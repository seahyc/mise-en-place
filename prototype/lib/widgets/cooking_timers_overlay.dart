import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/cooking_timer.dart';
import 'fancy_timer_ring.dart';

/// Convert string to Title Case
String _toTitleCase(String text) {
  if (text.isEmpty) return text;
  return text.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }).join(' ');
}

/// Displays multiple cooking timers as draggable cards with fancy burn-down rings.
///
/// Timers can be dragged and repositioned anywhere on the screen.
/// Each timer shows: emoji (if set), label, animated burn-down ring, time remaining.
/// - Tap to pause/resume
/// - Long-press to cancel
/// - Drag to reposition
class CookingTimersOverlay extends StatefulWidget {
  final List<CookingTimer> timers;
  final Function(String id) onToggle;
  final Function(String id) onCancel;
  final Function(String id)? onDismiss;

  const CookingTimersOverlay({
    super.key,
    required this.timers,
    required this.onToggle,
    required this.onCancel,
    this.onDismiss,
  });

  @override
  State<CookingTimersOverlay> createState() => _CookingTimersOverlayState();
}

class _CookingTimersOverlayState extends State<CookingTimersOverlay>
    with TickerProviderStateMixin {
  // Track positions for each timer by ID
  final Map<String, Offset> _timerPositions = {};

  // Track active smoke animations
  final List<_SmokeAnimation> _smokeAnimations = [];

  @override
  void dispose() {
    for (final smoke in _smokeAnimations) {
      smoke.controller.dispose();
    }
    super.dispose();
  }

  // Default starting position for new timers
  Offset _getDefaultPosition(int index, Size screenSize) {
    // Stack timers horizontally from bottom-left corner (horizontal card design)
    const padding = 16.0;
    const cardWidth = 220.0;
    const cardHeight = 120.0;
    return Offset(
      padding + (index * (cardWidth + 12)),
      screenSize.height - cardHeight - padding,
    );
  }

  void _triggerSmokeAnimation(Offset position) {
    final controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    final smoke = _SmokeAnimation(
      position: position,
      controller: controller,
    );

    setState(() {
      _smokeAnimations.add(smoke);
    });

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _smokeAnimations.remove(smoke);
        });
        controller.dispose();
      }
    });
  }

  void _handleDismiss(String timerId) {
    // Capture position before dismissing
    final position = _timerPositions[timerId];
    if (position != null) {
      // Offset to center the smoke on the card
      _triggerSmokeAnimation(Offset(position.dx + 55, position.dy + 60));
    }
    widget.onDismiss?.call(timerId);
  }

  @override
  Widget build(BuildContext context) {
    // Show smoke animations even if no timers
    if (widget.timers.isEmpty && _smokeAnimations.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Initialize positions for new timers
        for (int i = 0; i < widget.timers.length; i++) {
          final timer = widget.timers[i];
          if (!_timerPositions.containsKey(timer.id)) {
            _timerPositions[timer.id] = _getDefaultPosition(i, screenSize);
          }
        }

        // Remove positions for timers that no longer exist
        _timerPositions.removeWhere(
          (id, _) => !widget.timers.any((t) => t.id == id),
        );

        return Stack(
          children: [
            // Timer cards
            ...widget.timers.map((timer) {
              final position = _timerPositions[timer.id]!;

              return Positioned(
                left: position.dx,
                top: position.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      final newOffset = _timerPositions[timer.id]! + details.delta;
                      // Clamp to screen bounds (horizontal card: ~220w x ~120h)
                      _timerPositions[timer.id] = Offset(
                        newOffset.dx.clamp(0, screenSize.width - 220),
                        newOffset.dy.clamp(0, screenSize.height - 120),
                      );
                    });
                  },
                  child: _TimerCard(
                    timer: timer,
                    onToggle: () => widget.onToggle(timer.id),
                    onCancel: () => widget.onCancel(timer.id),
                    onDismiss: widget.onDismiss != null
                        ? () => _handleDismiss(timer.id)
                        : null,
                  ),
                ),
              );
            }),
            // Smoke animations
            ..._smokeAnimations.map((smoke) => Positioned(
              left: smoke.position.dx - 60,
              top: smoke.position.dy - 60,
              child: AnimatedBuilder(
                animation: smoke.controller,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(120, 120),
                    painter: _SmokePainter(
                      progress: smoke.controller.value,
                    ),
                  );
                },
              ),
            )),
          ],
        );
      },
    );
  }
}

/// Represents an active smoke animation
class _SmokeAnimation {
  final Offset position;
  final AnimationController controller;

  _SmokeAnimation({required this.position, required this.controller});
}

/// Paints rising smoke particles
class _SmokePainter extends CustomPainter {
  final double progress;

  _SmokePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Create multiple smoke particles
    for (int i = 0; i < 12; i++) {
      _drawSmokeParticle(canvas, center, i, size);
    }
  }

  void _drawSmokeParticle(Canvas canvas, Offset center, int index, Size size) {
    // Each particle has unique properties based on index
    final baseAngle = (index / 12) * 2 * math.pi;
    final angleOffset = _seededRandom(index) * 0.5 - 0.25;
    final angle = baseAngle + angleOffset;

    // Particles rise and spread outward
    final riseDistance = progress * size.height * 0.6;
    final spreadDistance = progress * size.width * 0.3 * _seededRandom(index + 100);

    final x = center.dx + math.cos(angle) * spreadDistance;
    final y = center.dy - riseDistance + _seededRandom(index + 200) * 20;

    // Size grows then shrinks
    final sizeProgress = math.sin(progress * math.pi);
    final particleSize = 8.0 + sizeProgress * 12 * _seededRandom(index + 300);

    // Opacity fades out
    final opacity = (1 - progress) * 0.6 * _seededRandom(index + 400);

    if (opacity <= 0 || particleSize <= 0) return;

    // Draw smoke puff
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, particleSize * 0.5);

    canvas.drawCircle(Offset(x, y), particleSize, paint);

    // Add slight gray tint for depth
    final innerPaint = Paint()
      ..color = const Color(0xFFE0E0E0).withValues(alpha: opacity * 0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, particleSize * 0.3);

    canvas.drawCircle(Offset(x, y), particleSize * 0.6, innerPaint);
  }

  double _seededRandom(int seed) {
    return (math.sin(seed * 12.9898 + 78.233) * 43758.5453).abs() % 1;
  }

  @override
  bool shouldRepaint(_SmokePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Draggable timer card with drag handle indicator
class _TimerCard extends StatefulWidget {
  final CookingTimer timer;
  final VoidCallback onToggle;
  final VoidCallback onCancel;
  final VoidCallback? onDismiss;

  const _TimerCard({
    required this.timer,
    required this.onToggle,
    required this.onCancel,
    this.onDismiss,
  });

  @override
  State<_TimerCard> createState() => _TimerCardState();
}

class _TimerCardState extends State<_TimerCard>
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late AnimationController _glowController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    // Fast shake animation like an alarm clock vibrating
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );

    // Slow pulsing glow for completed state
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Horizontal shake - rapid left-right movement
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 3.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 3.0, end: -3.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -3.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    // Subtle scale pulse
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.02), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.02, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    // Glow pulsing animation (0 = dim, 1 = bright)
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    if (widget.timer.isCompleted) {
      _shakeController.repeat();
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_TimerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.timer.isCompleted && !oldWidget.timer.isCompleted) {
      _shakeController.repeat();
      _glowController.repeat(reverse: true);
    } else if (!widget.timer.isCompleted) {
      _shakeController.stop();
      _glowController.stop();
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = widget.timer.isCompleted;
    final isPaused = widget.timer.isPaused;
    final isNearComplete = widget.timer.progress > 0.8 && !isCompleted;

    Color textColor;

    if (isCompleted) {
      textColor = const Color(0xFF4CAF50);
    } else if (isNearComplete) {
      textColor = const Color(0xFFFF9800);
    } else if (isPaused) {
      textColor = Colors.white54;
    } else {
      textColor = Colors.white;
    }

    Widget card = Listener(
      onPointerDown: (_) => setState(() => _isDragging = true),
      onPointerUp: (_) => setState(() => _isDragging = false),
      onPointerCancel: (_) => setState(() => _isDragging = false),
      child: AnimatedScale(
        scale: _isDragging ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            // Calculate animated background and border for completed state
            Color backgroundColor;
            Color borderColor;
            double borderWidth;

            if (isCompleted) {
              // Pulsing glow effect
              final glowIntensity = _glowAnimation.value;
              backgroundColor = Color.lerp(
                const Color(0xFF4CAF50).withValues(alpha: 0.15),
                const Color(0xFF4CAF50).withValues(alpha: 0.35),
                glowIntensity,
              )!;
              borderColor = Color.lerp(
                const Color(0xFF4CAF50).withValues(alpha: 0.4),
                const Color(0xFF4CAF50).withValues(alpha: 0.9),
                glowIntensity,
              )!;
              borderWidth = 2;
            } else if (isNearComplete) {
              backgroundColor = const Color(0xFFFF9800).withValues(alpha: 0.15);
              borderColor = const Color(0xFFFF9800).withValues(alpha: 0.5);
              borderWidth = _isDragging ? 2 : 1;
            } else if (isPaused) {
              backgroundColor = Colors.white.withValues(alpha: 0.08);
              borderColor = _isDragging
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.15);
              borderWidth = _isDragging ? 2 : 1;
            } else {
              backgroundColor = Colors.white.withValues(alpha: 0.1);
              borderColor = _isDragging
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.15);
              borderWidth = _isDragging ? 2 : 1;
            }

            return Material(
              color: Colors.transparent,
              elevation: _isDragging ? 12 : 4,
              shadowColor: isCompleted
                  ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                  : Colors.black54,
              borderRadius: BorderRadius.circular(20),
              child: GestureDetector(
                onTap: isCompleted ? widget.onCancel : widget.onToggle,
                onLongPress: widget.onCancel,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // Shimmer gradient background for completed state
                    gradient: isCompleted
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              backgroundColor,
                              Color.lerp(
                                backgroundColor,
                                const Color(0xFF81C784).withValues(alpha: 0.3),
                                _glowAnimation.value,
                              )!,
                              backgroundColor,
                            ],
                            stops: [
                              0.0,
                              0.3 + 0.4 * _glowAnimation.value,
                              1.0
                            ],
                          )
                        : null,
                    color: isCompleted ? null : backgroundColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor, width: borderWidth),
                    // Extra glow box shadow for completed
                    boxShadow: isCompleted
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.3 * _glowAnimation.value),
                              blurRadius: 12 * _glowAnimation.value,
                              spreadRadius: 2 * _glowAnimation.value,
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      // Drag handle in top-left
                      Positioned(
                        top: 0,
                        left: 0,
                        child: Icon(
                          Icons.drag_indicator,
                          color: Colors.white.withValues(alpha: _isDragging ? 0.6 : 0.3),
                          size: 14,
                        ),
                      ),
                      // Vertical layout: label on top, ring + time below
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Label at top with full width for wrapping
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              _toTitleCase(widget.timer.label),
                              style: GoogleFonts.lato(
                                color: textColor.withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                              softWrap: true,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Row: ring on left, large time on right
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Fancy timer ring with emoji inside
                              AnimatedFancyTimerRing(
                                progress: widget.timer.progress,
                                size: 56,
                                strokeWidth: 5,
                                isRunning: widget.timer.isRunning,
                                isCompleted: isCompleted,
                                isPaused: isPaused,
                                child: widget.timer.emoji != null && widget.timer.emoji!.isNotEmpty
                                    ? Text(
                                        widget.timer.emoji!,
                                        style: const TextStyle(fontSize: 22),
                                      )
                                    : isCompleted
                                        ? Icon(
                                            Icons.check_rounded,
                                            color: textColor,
                                            size: 24,
                                          )
                                        : isPaused
                                            ? Icon(
                                                Icons.pause_rounded,
                                                color: textColor.withValues(alpha: 0.7),
                                                size: 20,
                                              )
                                            : null,
                              ),
                              const SizedBox(width: 14),
                              // Large time display
                              Text(
                                isCompleted ? 'Done!' : widget.timer.displayTime,
                                style: GoogleFonts.jetBrainsMono(
                                  color: textColor,
                                  fontSize: isCompleted ? 24 : 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          // Dismiss button when completed
                          if (isCompleted && widget.onDismiss != null) ...[
                            const SizedBox(height: 8),
                            _buildDismissButton(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Apply shake animation when completed (like alarm clock vibrating)
    if (isCompleted && !_isDragging) {
      return AnimatedBuilder(
        animation: _shakeController,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(_shakeAnimation.value, 0), // Horizontal shake
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            ),
          );
        },
        child: card,
      );
    }

    return card;
  }

  Widget _buildDismissButton() {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          'Got it',
          style: GoogleFonts.lato(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// A single large timer display with the fancy ring.
/// More prominent display suitable for the main cooking view.
class SingleTimerDisplay extends StatelessWidget {
  final CookingTimer timer;
  final VoidCallback onToggle;
  final VoidCallback onCancel;
  final VoidCallback? onDismiss;

  const SingleTimerDisplay({
    super.key,
    required this.timer,
    required this.onToggle,
    required this.onCancel,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = timer.isCompleted;
    final isPaused = timer.isPaused;

    Color textColor;
    if (isCompleted) {
      textColor = const Color(0xFF4CAF50);
    } else if (timer.progress > 0.8) {
      textColor = const Color(0xFFFF9800);
    } else if (isPaused) {
      textColor = Colors.white54;
    } else {
      textColor = Colors.white;
    }

    return GestureDetector(
      onTap: isCompleted ? onCancel : onToggle,
      onLongPress: onCancel,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji above ring if provided
            if (timer.emoji != null && timer.emoji!.isNotEmpty) ...[
              Text(
                timer.emoji!,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(height: 8),
            ],
            // Large fancy timer ring
            AnimatedFancyTimerRing(
              progress: timer.progress,
              size: 120,
              strokeWidth: 8,
              isRunning: timer.isRunning,
              isCompleted: isCompleted,
              isPaused: isPaused,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isCompleted ? 'Done!' : timer.displayTime,
                    style: GoogleFonts.jetBrainsMono(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isPaused)
                    Text(
                      'PAUSED',
                      style: GoogleFonts.lato(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Label
            Text(
              timer.label,
              style: GoogleFonts.lato(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Action hint or dismiss button
            if (isCompleted && onDismiss != null)
              GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Got it!',
                    style: GoogleFonts.lato(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            else
              Text(
                isCompleted
                    ? 'Tap to dismiss'
                    : isPaused
                        ? 'Tap to resume'
                        : 'Tap to pause',
                style: GoogleFonts.lato(
                  color: Colors.white30,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
