import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A soundwave visualizer that shows animated bars responding to audio levels.
///
/// Displays a row of vertical bars that animate based on the provided [level].
/// Different colors distinguish between user (blue) and agent (warm) audio.
class SoundwaveVisualizer extends StatefulWidget {
  /// Audio level from 0.0 to 1.0
  final double level;

  /// Whether this is for user audio (blue) or agent audio (warm orange)
  final bool isUser;

  /// Whether the visualizer is active
  final bool isActive;

  /// Number of bars to display
  final int barCount;

  /// Width of each bar
  final double barWidth;

  /// Maximum height of bars
  final double maxHeight;

  /// Gap between bars
  final double gap;

  const SoundwaveVisualizer({
    super.key,
    required this.level,
    this.isUser = true,
    this.isActive = true,
    this.barCount = 5,
    this.barWidth = 4,
    this.maxHeight = 40,
    this.gap = 3,
  });

  @override
  State<SoundwaveVisualizer> createState() => _SoundwaveVisualizerState();
}

class _SoundwaveVisualizerState extends State<SoundwaveVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<double> _barHeights = [];
  final List<double> _targetHeights = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 50),
      vsync: this,
    )..addListener(_updateBars);

    // Initialize bar heights
    for (int i = 0; i < widget.barCount; i++) {
      _barHeights.add(0.15);
      _targetHeights.add(0.15);
    }

    if (widget.isActive) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(SoundwaveVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!widget.isActive && _animController.isAnimating) {
      _animController.stop();
      // Animate bars down to minimum
      setState(() {
        for (int i = 0; i < _targetHeights.length; i++) {
          _targetHeights[i] = 0.1;
        }
      });
    }

    // Update target heights based on new level
    if (widget.level != oldWidget.level) {
      _generateTargetHeights();
    }
  }

  void _generateTargetHeights() {
    final level = widget.level.clamp(0.0, 1.0);

    for (int i = 0; i < widget.barCount; i++) {
      // Create varied heights - middle bars tend to be taller
      final centerWeight = 1.0 - (i - widget.barCount / 2).abs() / (widget.barCount / 2);
      final baseHeight = 0.15 + (level * 0.85 * centerWeight);

      // Add randomness proportional to level
      final randomFactor = level * 0.3 * (_random.nextDouble() - 0.5);

      _targetHeights[i] = (baseHeight + randomFactor).clamp(0.1, 1.0);
    }
  }

  void _updateBars() {
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        // Smooth interpolation toward target
        final diff = _targetHeights[i] - _barHeights[i];
        _barHeights[i] += diff * 0.3;

        // Add subtle continuous movement when active
        if (widget.isActive && widget.level > 0.05) {
          _barHeights[i] += (_random.nextDouble() - 0.5) * 0.05 * widget.level;
          _barHeights[i] = _barHeights[i].clamp(0.1, 1.0);
        }
      }
    });

    // Periodically regenerate targets for organic movement
    if (_random.nextDouble() < 0.15 && widget.isActive) {
      _generateTargetHeights();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth =
        widget.barCount * widget.barWidth + (widget.barCount - 1) * widget.gap;

    return SizedBox(
      width: totalWidth,
      height: widget.maxHeight,
      child: CustomPaint(
        painter: _SoundwavePainter(
          barHeights: _barHeights,
          barWidth: widget.barWidth,
          gap: widget.gap,
          maxHeight: widget.maxHeight,
          isUser: widget.isUser,
          isActive: widget.isActive,
        ),
      ),
    );
  }
}

class _SoundwavePainter extends CustomPainter {
  final List<double> barHeights;
  final double barWidth;
  final double gap;
  final double maxHeight;
  final bool isUser;
  final bool isActive;

  _SoundwavePainter({
    required this.barHeights,
    required this.barWidth,
    required this.gap,
    required this.maxHeight,
    required this.isUser,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    for (int i = 0; i < barHeights.length; i++) {
      final x = i * (barWidth + gap);
      final heightFraction = barHeights[i];
      final barHeight = maxHeight * heightFraction;

      // Create gradient based on whether user or agent
      final Paint paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isUser
              ? [
                  // User: cool blue gradient
                  const Color(0xFF64B5F6).withValues(alpha: isActive ? 1.0 : 0.4),
                  const Color(0xFF1976D2).withValues(alpha: isActive ? 1.0 : 0.4),
                ]
              : [
                  // Agent: warm orange gradient
                  const Color(0xFFFFB74D).withValues(alpha: isActive ? 1.0 : 0.4),
                  const Color(0xFFFF8A65).withValues(alpha: isActive ? 1.0 : 0.4),
                ],
        ).createShader(Rect.fromLTWH(x, centerY - barHeight / 2, barWidth, barHeight));

      // Draw rounded rect bar centered vertically
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: barHeight,
        ),
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(rect, paint);

      // Add glow effect when active and level is high
      if (isActive && heightFraction > 0.5) {
        final glowPaint = Paint()
          ..color = (isUser ? const Color(0xFF64B5F6) : const Color(0xFFFFB74D))
              .withValues(alpha: (heightFraction - 0.5) * 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

        canvas.drawRRect(rect, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SoundwavePainter oldDelegate) {
    return true; // Always repaint for smooth animation
  }
}

/// A larger, more prominent soundwave display for the cooking mode screen.
/// Shows audio activity with a circular arrangement of bars around a center point.
class CircularSoundwave extends StatefulWidget {
  /// Audio level from 0.0 to 1.0
  final double level;

  /// Whether this is for user audio (blue) or agent audio (warm orange)
  final bool isUser;

  /// Whether the visualizer is active
  final bool isActive;

  /// Size of the circular visualizer
  final double size;

  /// Number of bars around the circle
  final int barCount;

  const CircularSoundwave({
    super.key,
    required this.level,
    this.isUser = true,
    this.isActive = true,
    this.size = 120,
    this.barCount = 24,
  });

  @override
  State<CircularSoundwave> createState() => _CircularSoundwaveState();
}

class _CircularSoundwaveState extends State<CircularSoundwave>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final List<double> _barHeights = [];
  final List<double> _targetHeights = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    // 33ms = ~30fps for smoother animation
    _animController = AnimationController(
      duration: const Duration(milliseconds: 33),
      vsync: this,
    )..addListener(_updateBars);

    for (int i = 0; i < widget.barCount; i++) {
      _barHeights.add(0.15);
      _targetHeights.add(0.15);
    }

    if (widget.isActive) {
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(CircularSoundwave oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!widget.isActive && _animController.isAnimating) {
      _animController.stop();
      setState(() {
        for (int i = 0; i < _targetHeights.length; i++) {
          _targetHeights[i] = 0.15;
        }
      });
    }

    if (widget.level != oldWidget.level) {
      _generateTargetHeights();
    }
  }

  void _generateTargetHeights() {
    final level = widget.level.clamp(0.0, 1.0);
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    for (int i = 0; i < widget.barCount; i++) {
      // Base height scales with level - more responsive to input
      final baseHeight = 0.15 + (level * 0.75);

      // Multi-frequency wave pattern for more organic movement
      final wave1 = math.sin(i * 0.4 + time * 8.0) * 0.12;
      final wave2 = math.sin(i * 0.7 + time * 5.0) * 0.08;
      final waveOffset = (wave1 + wave2) * level;

      // Add randomness proportional to level for natural variation
      final randomFactor = level * 0.25 * (_random.nextDouble() - 0.5);

      _targetHeights[i] = (baseHeight + waveOffset + randomFactor).clamp(0.12, 1.0);
    }
  }

  void _updateBars() {
    if (!mounted) return;

    setState(() {
      for (int i = 0; i < widget.barCount; i++) {
        final diff = _targetHeights[i] - _barHeights[i];
        // Faster interpolation for more responsive feel (0.4 instead of 0.25)
        _barHeights[i] += diff * 0.4;
        _barHeights[i] = _barHeights[i].clamp(0.12, 1.0);
      }
    });

    if (widget.isActive) {
      _generateTargetHeights();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _CircularSoundwavePainter(
          barHeights: _barHeights,
          isUser: widget.isUser,
          isActive: widget.isActive,
        ),
      ),
    );
  }
}

class _CircularSoundwavePainter extends CustomPainter {
  final List<double> barHeights;
  final bool isUser;
  final bool isActive;

  _CircularSoundwavePainter({
    required this.barHeights,
    required this.isUser,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = size.width * 0.25;
    final maxBarLength = size.width * 0.2;
    final barWidth = 3.0;

    final baseColor = isUser ? const Color(0xFF42A5F5) : const Color(0xFFFFB74D);
    final highlightColor = isUser ? const Color(0xFF90CAF9) : const Color(0xFFFFE0B2);

    for (int i = 0; i < barHeights.length; i++) {
      final angle = (i / barHeights.length) * 2 * math.pi - math.pi / 2;
      final heightFraction = barHeights[i];
      final barLength = maxBarLength * heightFraction;

      final startX = center.dx + innerRadius * math.cos(angle);
      final startY = center.dy + innerRadius * math.sin(angle);
      final endX = center.dx + (innerRadius + barLength) * math.cos(angle);
      final endY = center.dy + (innerRadius + barLength) * math.sin(angle);

      final paint = Paint()
        ..strokeWidth = barWidth
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            baseColor.withValues(alpha: isActive ? 0.8 : 0.3),
            highlightColor.withValues(alpha: isActive ? 1.0 : 0.4),
          ],
        ).createShader(Rect.fromPoints(Offset(startX, startY), Offset(endX, endY)));

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

      // Glow for high levels
      if (isActive && heightFraction > 0.5) {
        final glowPaint = Paint()
          ..strokeWidth = barWidth + 2
          ..strokeCap = StrokeCap.round
          ..color = baseColor.withValues(alpha: (heightFraction - 0.5) * 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

        canvas.drawLine(Offset(startX, startY), Offset(endX, endY), glowPaint);
      }
    }

    // Draw center circle
    final centerPaint = Paint()
      ..color = (isUser ? const Color(0xFF1976D2) : const Color(0xFFFF8A65))
          .withValues(alpha: isActive ? 0.3 : 0.15)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, innerRadius - 2, centerPaint);

    // Center ring
    final ringPaint = Paint()
      ..color = (isUser ? const Color(0xFF42A5F5) : const Color(0xFFFFB74D))
          .withValues(alpha: isActive ? 0.6 : 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, innerRadius - 2, ringPaint);
  }

  @override
  bool shouldRepaint(_CircularSoundwavePainter oldDelegate) => true;
}
