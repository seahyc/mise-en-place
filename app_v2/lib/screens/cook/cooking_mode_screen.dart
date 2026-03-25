import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/voice_provider.dart';
import '../../services/voice_client.dart';
import '../../theme/app_colors.dart';
import '../../widgets/responsive_layout.dart';
import 'cooking_mode_phone.dart';
import 'ingredient_panel.dart';
import 'step_panel.dart';
import 'voice_bar.dart';

/// The main cooking mode screen. Shows split-pane (image + panel) on iPad,
/// and delegates to [CookingModePhone] on phone-sized screens.
class CookingModeScreen extends ConsumerStatefulWidget {
  const CookingModeScreen({
    super.key,
    required this.sessionId,
    this.recipeImageUrl,
  });

  final String sessionId;
  final String? recipeImageUrl;

  @override
  ConsumerState<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends ConsumerState<CookingModeScreen> {
  CookingSession? _session;
  bool _loading = true;
  String? _error;

  int _currentStepIndex = 0;
  final Set<int> _completedSteps = {};
  final List<TimerState> _activeTimers = [];
  VoiceBarState _voiceBarState = VoiceBarState.listening;
  String? _agentResponseText;

  Timer? _tickTimer;
  StreamSubscription<VoiceEvent>? _voiceSub;

  @override
  void initState() {
    super.initState();
    _fetchSession();
    _startTickTimer();
    // Voice events will be subscribed after build via ref
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _voiceSub?.cancel();
    super.dispose();
  }

  Future<void> _fetchSession() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final session = await apiClient.getSession(widget.sessionId);
      if (mounted) {
        setState(() {
          _session = session;
          _loading = false;
          // Mark already-completed steps
          for (int i = 0; i < session.steps.length; i++) {
            if (session.steps[i].isCompleted) {
              _completedSteps.add(i);
            }
          }
        });
        _connectVoice();
        _subscribeVoiceEvents();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _connectVoice() {
    try {
      final client = ref.read(voiceClientProvider);
      final apiClient = ref.read(apiClientProvider);
      client.connect(widget.sessionId, '', _baseUrl(apiClient));
    } catch (e) {
      debugPrint('Voice connection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice unavailable — using manual mode')),
        );
      }
    }
  }

  String _baseUrl(dynamic apiClient) {
    // ApiClient doesn't expose baseUrl directly; default fallback
    return 'http://localhost:8090';
  }

  void _subscribeVoiceEvents() {
    final client = ref.read(voiceClientProvider);
    _voiceSub = client.events.listen(_handleVoiceEvent);
  }

  void _handleVoiceEvent(VoiceEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ToolCallEvent():
          _handleToolCall(event);
        case AgentResponseEvent():
          _agentResponseText = event.text;
          _voiceBarState = VoiceBarState.agentSpeaking;
        case TTSStartEvent():
          _voiceBarState = VoiceBarState.agentSpeaking;
        case TTSEndEvent():
          _voiceBarState = VoiceBarState.listening;
          // Clear agent text after a brief delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) {
              setState(() => _agentResponseText = null);
            }
          });
        case TranscriptEvent():
          if (event.text.isNotEmpty) {
            _voiceBarState = VoiceBarState.userSpeaking;
          }
        case DisconnectedEvent():
          _voiceBarState = VoiceBarState.idle;
        case ErrorEvent():
          _voiceBarState = VoiceBarState.idle;
        case AudioEvent():
          break; // handled by audio player
      }
    });
  }

  void _handleToolCall(ToolCallEvent event) {
    switch (event.tool) {
      case 'navigate_step':
        final step = event.args['step'];
        if (step is int && step >= 0 && step < (_session?.steps.length ?? 0)) {
          _currentStepIndex = step;
        }
      case 'set_timer':
        final label = event.args['label'] as String? ?? 'Timer';
        final seconds = event.args['seconds'] as int? ?? 60;
        _activeTimers.add(TimerState(
          label: label,
          totalSeconds: seconds,
          remainingSeconds: seconds,
        ));
      case 'mark_step_complete':
        _completedSteps.add(_currentStepIndex);
        if (_currentStepIndex < (_session?.steps.length ?? 1) - 1) {
          _currentStepIndex++;
        }
    }
  }

  void _startTickTimer() {
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeTimers.isEmpty) return;
      setState(() {
        for (final timer in _activeTimers) {
          if (!timer.isPaused && timer.remainingSeconds > 0) {
            timer.remainingSeconds--;
          }
        }
        // Remove expired timers
        _activeTimers.removeWhere((t) => t.remainingSeconds <= 0);
      });
    });
  }

  void _onStepTap(int index) {
    setState(() => _currentStepIndex = index);
  }

  void _onTimerTogglePause(int index) {
    if (index < _activeTimers.length) {
      setState(() {
        _activeTimers[index].isPaused = !_activeTimers[index].isPaused;
      });
    }
  }

  void _onTimerCancel(int index) {
    if (index < _activeTimers.length) {
      setState(() => _activeTimers.removeAt(index));
    }
  }

  void _onTextSubmitted(String text) {
    final client = ref.read(voiceClientProvider);
    client.sendTextInput(text);
    setState(() {
      _voiceBarState = VoiceBarState.userSpeaking;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: CircularProgressIndicator(color: AppColors.amber)),
      );
    }

    if (_error != null || _session == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.amber, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _error ?? 'Session not found',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: _buildCloseButton(),
            ),
          ],
        ),
      );
    }

    final deviceType = getDeviceType(context);
    if (deviceType == DeviceType.phone) {
      return CookingModePhone(
        session: _session!,
        currentStepIndex: _currentStepIndex,
        completedSteps: _completedSteps,
        timers: _activeTimers,
        voiceBarState: _voiceBarState,
        agentResponseText: _agentResponseText,
        onStepChanged: (i) => setState(() => _currentStepIndex = i),
        onTimerTogglePause: _onTimerTogglePause,
        onTimerCancel: _onTimerCancel,
        onClose: _handleClose,
        onTextSubmitted: _onTextSubmitted,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          _buildTabletLayout(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: _buildCloseButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    final session = _session!;
    final step = _currentStepIndex < session.steps.length
        ? session.steps[_currentStepIndex]
        : null;

    // Determine step image — from step's source recipe or fallback
    final imageUrl = _resolveStepImageUrl(step);

    // Build ingredient list for current step
    final ingredients = _resolveIngredients(step);

    // Multi-recipe support
    final dishNames = _buildDishNames(session);
    final dishColors = _buildDishColors(session);

    return Row(
      children: [
        // Left: cinematic image (45%)
        Expanded(
          flex: 45,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              if (imageUrl != null)
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.darkSurface),
                  errorWidget: (_, __, ___) =>
                      Container(color: AppColors.darkSurface),
                )
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1a1a1a), Color(0xFF0f0f0f)],
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.restaurant,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),

              // Gradient overlay: transparent → dark (blends into right panel)
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Colors.transparent, AppColors.darkBackground],
                    stops: [0.55, 1.0],
                  ),
                ),
              ),

              // Vignette top/bottom
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x4D000000), // rgba(0,0,0,0.3)
                      Colors.transparent,
                      Colors.transparent,
                      Color(0x66000000), // rgba(0,0,0,0.4)
                    ],
                    stops: [0.0, 0.15, 0.85, 1.0],
                  ),
                ),
              ),

              // Ingredient panel
              if (ingredients.isNotEmpty)
                Positioned(
                  bottom: 20,
                  left: 16,
                  child: IngredientPanel(ingredients: ingredients),
                ),
            ],
          ),
        ),

        // Right: step panel (55%)
        Expanded(
          flex: 55,
          child: StepPanel(
            session: session,
            currentStepIndex: _currentStepIndex,
            timers: _activeTimers,
            voiceBarState: _voiceBarState,
            agentResponseText: _agentResponseText,
            completedStepIndices: _completedSteps,
            dishNames: dishNames,
            dishColors: dishColors,
            onStepTap: _onStepTap,
            onTimerTogglePause: _onTimerTogglePause,
            onTimerCancel: _onTimerCancel,
            onTextSubmitted: _onTextSubmitted,
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String? _resolveStepImageUrl(SessionStep? step) {
    // Session steps don't carry image URLs; fall back to the recipe's main image.
    return widget.recipeImageUrl;
  }

  void _handleClose() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: _handleClose,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.4),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  List<String> _resolveIngredients(SessionStep? step) {
    // Ingredients are per-step data from the backend.
    // For now return empty; the cooking mode controller will populate these.
    return [];
  }

  Map<String, String>? _buildDishNames(CookingSession session) {
    if (session.recipeIds.length <= 1) return null;
    // Build from unique sourceDishTag values in steps
    final tags = <String, String>{};
    for (final step in session.steps) {
      final tag = step.sourceDishTag;
      if (tag != null && !tags.containsKey(tag)) {
        tags[tag] = tag; // Tag is typically the dish name
      }
    }
    return tags.length > 1 ? tags : null;
  }

  Map<String, Color>? _buildDishColors(CookingSession session) {
    if (session.recipeIds.length <= 1) return null;
    final tags = <String>[];
    for (final step in session.steps) {
      final tag = step.sourceDishTag;
      if (tag != null && !tags.contains(tag)) {
        tags.add(tag);
      }
    }
    if (tags.length <= 1) return null;
    final colors = <String, Color>{};
    for (int i = 0; i < tags.length; i++) {
      colors[tags[i]] = AppColors.dishTags[i % AppColors.dishTags.length];
    }
    return colors;
  }
}
