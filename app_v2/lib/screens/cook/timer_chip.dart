import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A frosted timer pill displaying a pulsing dot, countdown, and label.
///
/// Tap to expand into a control row with pause/resume and cancel buttons.
class TimerChip extends StatefulWidget {
  const TimerChip({
    super.key,
    required this.label,
    required this.remainingSeconds,
    this.color = AppColors.amber,
    this.isPaused = false,
    this.onTap,
    this.onTogglePause,
    this.onCancel,
  });

  final String label;
  final int remainingSeconds;
  final Color color;
  final bool isPaused;
  final VoidCallback? onTap;
  final VoidCallback? onTogglePause;
  final VoidCallback? onCancel;

  @override
  State<TimerChip> createState() => _TimerChipState();
}

class _TimerChipState extends State<TimerChip>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = widget.remainingSeconds ~/ 60;
    final seconds = widget.remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final dimmedColor = widget.color.withValues(alpha: 0.45);

    return GestureDetector(
      onTap: () {
        setState(() => _expanded = !_expanded);
        widget.onTap?.call();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.08),
          border: Border.all(color: widget.color.withValues(alpha: 0.18)),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Pulsing dot
            FadeTransition(
              opacity: widget.isPaused
                  ? const AlwaysStoppedAnimation(0.4)
                  : _pulseController,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Time
            Text(
              _formattedTime,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: widget.color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            // Label
            Text(
              widget.label,
              style: TextStyle(fontSize: 12, color: dimmedColor),
            ),
            // Expanded controls
            if (_expanded) ...[
              const SizedBox(width: 14),
              _ControlButton(
                icon: widget.isPaused ? Icons.play_arrow : Icons.pause,
                color: widget.color,
                onTap: widget.onTogglePause,
              ),
              const SizedBox(width: 8),
              _ControlButton(
                icon: Icons.close,
                color: widget.color,
                onTap: widget.onCancel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
