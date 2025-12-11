import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A fancy circular timer ring that burns down with a flame effect.
///
/// Features:
/// - Ring depletes clockwise from top
/// - Color gradient: green → yellow → orange → red as time runs out
/// - Glowing flame effect at the leading edge
/// - Pulsing glow when near completion
/// - Celebratory effect when completed
class FancyTimerRing extends StatelessWidget {
  final double progress; // 0.0 (just started) to 1.0 (completed)
  final double size;
  final double strokeWidth;
  final bool isRunning;
  final bool isCompleted;
  final bool isPaused;
  final Widget? child;

  const FancyTimerRing({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 6,
    this.isRunning = true,
    this.isCompleted = false,
    this.isPaused = false,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _TimerRingPainter(
          progress: progress,
          strokeWidth: strokeWidth,
          isRunning: isRunning,
          isCompleted: isCompleted,
          isPaused: isPaused,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final bool isRunning;
  final bool isCompleted;
  final bool isPaused;

  _TimerRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.isRunning,
    required this.isCompleted,
    required this.isPaused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (isCompleted) {
      _drawCompletedRing(canvas, center, radius, rect);
      return;
    }

    if (isPaused) {
      _drawPausedRing(canvas, center, radius, rect);
      return;
    }

    // Calculate remaining arc (burns down from full to empty)
    final remaining = 1.0 - progress;
    if (remaining <= 0) return;

    // Get color based on progress
    final ringColor = _getProgressColor(progress);

    // Main progress arc - starts at top (-90°), sweeps clockwise
    final sweepAngle = remaining * 2 * math.pi;
    final startAngle = -math.pi / 2;

    // Create gradient for the arc
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [
          ringColor,
          ringColor.withValues(alpha: 0.8),
          ringColor.withValues(alpha: 0.6),
        ],
        stops: const [0.0, 0.7, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, gradientPaint);

    // Draw flame/glow at the leading edge (end of the arc)
    if (isRunning && remaining > 0.02) {
      _drawFlameEffect(canvas, center, radius, startAngle + sweepAngle, ringColor);
    }

    // Pulsing outer glow when near completion (>80% done)
    if (progress > 0.8 && isRunning) {
      _drawUrgencyGlow(canvas, center, radius, ringColor);
    }
  }

  Color _getProgressColor(double progress) {
    // Green (0%) → Yellow (50%) → Orange (75%) → Red (100%)
    if (progress < 0.5) {
      // Green to Yellow
      return Color.lerp(
        const Color(0xFF4CAF50), // Green
        const Color(0xFFFFEB3B), // Yellow
        progress * 2,
      )!;
    } else if (progress < 0.75) {
      // Yellow to Orange
      return Color.lerp(
        const Color(0xFFFFEB3B), // Yellow
        const Color(0xFFFF9800), // Orange
        (progress - 0.5) * 4,
      )!;
    } else {
      // Orange to Red
      return Color.lerp(
        const Color(0xFFFF9800), // Orange
        const Color(0xFFF44336), // Red
        (progress - 0.75) * 4,
      )!;
    }
  }

  void _drawFlameEffect(Canvas canvas, Offset center, double radius, double angle, Color color) {
    // Position of the flame (at the end of the arc)
    final flameX = center.dx + radius * math.cos(angle);
    final flameY = center.dy + radius * math.sin(angle);
    final flameCenter = Offset(flameX, flameY);

    // Outer glow
    final outerGlow = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(flameCenter, strokeWidth * 1.5, outerGlow);

    // Middle glow
    final middleGlow = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(flameCenter, strokeWidth * 1.0, middleGlow);

    // Bright center
    final brightCenter = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(flameCenter, strokeWidth * 0.4, brightCenter);
  }

  void _drawUrgencyGlow(Canvas canvas, Offset center, double radius, Color color) {
    // Pulsing red/orange glow around the entire ring
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawCircle(center, radius, glowPaint);
  }

  void _drawCompletedRing(Canvas canvas, Offset center, double radius, Rect rect) {
    // Full green ring with celebratory glow
    final completePaint = Paint()
      ..color = const Color(0xFF4CAF50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, completePaint);

    // Celebratory outer glow
    final glowPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(center, radius, glowPaint);
  }

  void _drawPausedRing(Canvas canvas, Offset center, double radius, Rect rect) {
    // Muted ring when paused
    final remaining = 1.0 - progress;
    if (remaining <= 0) return;

    final sweepAngle = remaining * 2 * math.pi;
    final startAngle = -math.pi / 2;

    final pausedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, pausedPaint);
  }

  @override
  bool shouldRepaint(_TimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isRunning != isRunning ||
        oldDelegate.isCompleted != isCompleted ||
        oldDelegate.isPaused != isPaused;
  }
}

/// Animated version of FancyTimerRing that adds smooth transitions
/// and a pulsing flame effect.
class AnimatedFancyTimerRing extends StatefulWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final bool isRunning;
  final bool isCompleted;
  final bool isPaused;
  final Widget? child;

  const AnimatedFancyTimerRing({
    super.key,
    required this.progress,
    this.size = 80,
    this.strokeWidth = 6,
    this.isRunning = true,
    this.isCompleted = false,
    this.isPaused = false,
    this.child,
  });

  @override
  State<AnimatedFancyTimerRing> createState() => _AnimatedFancyTimerRingState();
}

class _AnimatedFancyTimerRingState extends State<AnimatedFancyTimerRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _updatePulseState();
  }

  @override
  void didUpdateWidget(AnimatedFancyTimerRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulseState();
  }

  void _updatePulseState() {
    // Pulse when running and near completion, or when completed
    if ((widget.isRunning && widget.progress > 0.8) || widget.isCompleted) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _AnimatedTimerRingPainter(
              progress: widget.progress,
              strokeWidth: widget.strokeWidth,
              isRunning: widget.isRunning,
              isCompleted: widget.isCompleted,
              isPaused: widget.isPaused,
              pulseValue: _pulseAnimation.value,
            ),
            child: Center(child: widget.child),
          ),
        );
      },
    );
  }
}

class _AnimatedTimerRingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final bool isRunning;
  final bool isCompleted;
  final bool isPaused;
  final double pulseValue;

  _AnimatedTimerRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.isRunning,
    required this.isCompleted,
    required this.isPaused,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    if (isCompleted) {
      _drawCompletedRing(canvas, center, radius);
      return;
    }

    if (isPaused) {
      _drawPausedRing(canvas, center, radius);
      return;
    }

    final remaining = 1.0 - progress;
    if (remaining <= 0) return;

    final ringColor = _getProgressColor(progress);
    final sweepAngle = remaining * 2 * math.pi;
    final startAngle = -math.pi / 2;

    // Main arc with gradient
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          ringColor,
          ringColor.withValues(alpha: 0.7),
        ],
        stops: const [0.0, 1.0],
        transform: GradientRotation(startAngle),
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);

    // Animated flame at leading edge
    if (isRunning && remaining > 0.02) {
      _drawAnimatedFlame(canvas, center, radius, startAngle + sweepAngle, ringColor);
    }

    // Pulsing urgency glow
    if (progress > 0.8 && isRunning) {
      _drawPulsingGlow(canvas, center, radius, ringColor);
    }
  }

  Color _getProgressColor(double progress) {
    if (progress < 0.5) {
      return Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFFEB3B),
        progress * 2,
      )!;
    } else if (progress < 0.75) {
      return Color.lerp(
        const Color(0xFFFFEB3B),
        const Color(0xFFFF9800),
        (progress - 0.5) * 4,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFFFF9800),
        const Color(0xFFF44336),
        (progress - 0.75) * 4,
      )!;
    }
  }

  void _drawAnimatedFlame(Canvas canvas, Offset center, double radius, double angle, Color color) {
    final flameX = center.dx + radius * math.cos(angle);
    final flameY = center.dy + radius * math.sin(angle);
    final flameCenter = Offset(flameX, flameY);

    // Calculate flame direction (pointing outward from center, slightly upward)
    final flameAngle = angle - math.pi / 2; // Perpendicular to arc, pointing outward

    // Animated flame size based on pulse
    final flameHeight = strokeWidth * (2.5 + pulseValue * 1.5);
    final flameWidth = strokeWidth * (1.2 + pulseValue * 0.4);

    // Draw flame shape (teardrop pointing outward)
    final path = Path();

    // Flame tip (outer point)
    final tipX = flameCenter.dx + flameHeight * math.cos(flameAngle);
    final tipY = flameCenter.dy + flameHeight * math.sin(flameAngle);

    // Base points (on the ring)
    final baseAngle1 = flameAngle + math.pi / 2;
    final baseAngle2 = flameAngle - math.pi / 2;
    final base1X = flameCenter.dx + flameWidth * math.cos(baseAngle1);
    final base1Y = flameCenter.dy + flameWidth * math.sin(baseAngle1);
    final base2X = flameCenter.dx + flameWidth * math.cos(baseAngle2);
    final base2Y = flameCenter.dy + flameWidth * math.sin(baseAngle2);

    // Draw flame path
    path.moveTo(base1X, base1Y);
    path.quadraticBezierTo(
      tipX, tipY,
      base2X, base2Y,
    );
    path.close();

    // Outer flame glow (pulsing, color-matched)
    final outerGlow = Paint()
      ..color = color.withValues(alpha: 0.3 + pulseValue * 0.2)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + pulseValue * 8)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, outerGlow);

    // Middle flame (orange/yellow core)
    final innerColor = Color.lerp(color, const Color(0xFFFFAB00), 0.5)!;
    final middleFlame = Paint()
      ..color = innerColor.withValues(alpha: 0.7 + pulseValue * 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, middleFlame);

    // Hot white center dot
    final brightCenter = Paint()
      ..color = Colors.white.withValues(alpha: 0.9 + pulseValue * 0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(flameCenter, strokeWidth * 0.4, brightCenter);

    // Outer glow circle for ambient light
    final ambientGlow = Paint()
      ..color = color.withValues(alpha: 0.15 + pulseValue * 0.1)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16 + pulseValue * 8);
    canvas.drawCircle(flameCenter, strokeWidth * 2, ambientGlow);
  }

  void _drawPulsingGlow(Canvas canvas, Offset center, double radius, Color color) {
    final glowAlpha = 0.15 + pulseValue * 0.15;
    final glowBlur = 6 + pulseValue * 6;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.5
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);

    canvas.drawCircle(center, radius, glowPaint);
  }

  void _drawCompletedRing(Canvas canvas, Offset center, double radius) {
    const green = Color(0xFF4CAF50);

    // Pulsing completed ring
    final completePaint = Paint()
      ..color = green
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, completePaint);

    // Pulsing celebration glow
    final glowAlpha = 0.3 + pulseValue * 0.3;
    final glowBlur = 8 + pulseValue * 8;

    final glowPaint = Paint()
      ..color = green.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 3
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);

    canvas.drawCircle(center, radius, glowPaint);
  }

  void _drawPausedRing(Canvas canvas, Offset center, double radius) {
    final remaining = 1.0 - progress;
    if (remaining <= 0) return;

    final sweepAngle = remaining * 2 * math.pi;
    final startAngle = -math.pi / 2;

    final pausedPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      pausedPaint,
    );
  }

  @override
  bool shouldRepaint(_AnimatedTimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isRunning != isRunning ||
        oldDelegate.isCompleted != isCompleted ||
        oldDelegate.isPaused != isPaused ||
        oldDelegate.pulseValue != pulseValue;
  }
}
