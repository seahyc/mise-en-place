import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'agent_bubble.dart';

enum VoiceBarState { listening, userSpeaking, agentSpeaking, idle }

/// The voice interaction strip shown at the bottom of cooking mode.
///
/// Displays a voice orb with breathing animation, waveform bars, and
/// status text. When the agent is speaking, an [AgentBubble] appears above.
class VoiceBar extends StatefulWidget {
  const VoiceBar({
    super.key,
    required this.state,
    this.agentResponseText,
  });

  final VoiceBarState state;
  final String? agentResponseText;

  @override
  State<VoiceBar> createState() => _VoiceBarState();
}

class _VoiceBarState extends State<VoiceBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isActive =>
      widget.state != VoiceBarState.idle;

  bool get _isAmber =>
      widget.state == VoiceBarState.agentSpeaking;

  Color get _accentColor =>
      _isAmber ? AppColors.amber : AppColors.green;

  String get _statusText {
    switch (widget.state) {
      case VoiceBarState.listening:
        return 'Listening...';
      case VoiceBarState.userSpeaking:
        return 'Listening...';
      case VoiceBarState.agentSpeaking:
        return 'Speaking...';
      case VoiceBarState.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Agent bubble above the voice strip when speaking
        if (_isAmber && widget.agentResponseText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AgentBubble(text: widget.agentResponseText!),
          ),
        // Voice strip
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: _isAmber
                ? const Color(0x0AFF9F0A) // rgba(255,159,10,0.04)
                : const Color(0x08FFFFFF), // rgba(255,255,255,0.03)
            borderRadius: BorderRadius.circular(16),
            border: _isAmber
                ? Border.all(color: const Color(0x14FF9F0A))
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              _VoiceOrb(
                color: _accentColor,
                isActive: _isActive,
                controller: _controller,
              ),
              const SizedBox(width: 14),
              _Waveform(
                color: _accentColor,
                isActive: _isActive,
                controller: _controller,
              ),
              const SizedBox(width: 14),
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 12,
                  color: _isAmber
                      ? const Color(0x80FF9F0A)
                      : const Color(0x40FFFFFF),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Voice Orb ─────────────────────────────────────────────────────────────────

class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({
    required this.color,
    required this.isActive,
    required this.controller,
  });

  final Color color;
  final bool isActive;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 3-second breathing cycle mapped to 1.4s controller
        final breathe = isActive
            ? 0.5 + 0.5 * math.sin(controller.value * 2 * math.pi)
            : 0.0;
        return Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isActive ? 0.1 : 0.05),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3 * breathe),
                      blurRadius: 8 + 8 * breathe,
                      spreadRadius: 2 * breathe,
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive
                  ? color
                  : color.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
  }
}

// ── Animated Builder (thin wrapper) ──────────────────────────────────────────

class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
  }) : super(listenable: animation);

  final Widget Function(BuildContext, Widget?) builder;

  @override
  Widget build(BuildContext context) => builder(context, null);
}

// ── Waveform Bars ─────────────────────────────────────────────────────────────

class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.color,
    required this.isActive,
    required this.controller,
  });

  final Color color;
  final bool isActive;
  final AnimationController controller;

  static const _barHeights = [10.0, 16.0, 24.0, 18.0, 12.0, 20.0, 8.0];
  static const _barDelays = [0.0, 0.07, 0.14, 0.21, 0.29, 0.36, 0.43];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(7, (i) {
            final phase = (controller.value + _barDelays[i]) % 1.0;
            final scale = isActive
                ? 0.3 + 0.7 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi))
                : 0.3;
            return Padding(
              padding: EdgeInsets.only(left: i > 0 ? 2.5 : 0),
              child: Container(
                width: 2.5,
                height: _barHeights[i] * scale,
                decoration: BoxDecoration(
                  color: isActive
                      ? color.withValues(alpha: 0.4)
                      : const Color(0x4DFFFFFF), // rgba(255,255,255,0.3)
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
