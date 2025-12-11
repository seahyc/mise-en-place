import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../controllers/cooking_mode_controller.dart';
import '../services/auth_service.dart';
import '../widgets/cooking_mode_widgets.dart';
import '../widgets/soundwave_visualizer.dart';
import '../widgets/cooking_timers_overlay.dart';
import '../utils/web_url_sync.dart';

/// Main cooking mode screen - voice-guided cooking experience.
/// Uses CookingModeController to manage state and business logic.
class CookingModeScreen extends StatefulWidget {
  final Recipe recipe;
  const CookingModeScreen({super.key, required this.recipe});

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen> with TickerProviderStateMixin {
  late CookingModeController _controller;
  bool _mounted = true;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;
  late AnimationController _ambientController;

  final WebUrlSync _urlSync = const WebUrlSync();

  @override
  void initState() {
    super.initState();
    debugPrint('[CookingMode] initState - recipe: ${widget.recipe.title}');

    _hydrateStepFromUrl();
    _setupAnimationControllers();
    _initializeController();
  }

  void _setupAnimationControllers() {
    // Pulse animation for voice activity (controller is used by callbacks)
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Fade-in animation for content
    _fadeInController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeOut,
    );
    _fadeInController.forward();

    // Slow, smooth ambient animation for wave-like morphing
    _ambientController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
  }

  void _initializeController() {
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.currentUser;
    final userName = auth.displayName ??
        user?.userMetadata?['full_name'] ??
        (user?.email != null ? user!.email!.split('@').first : 'Chef');
    final experienceLevel = (user?.userMetadata?['experience_level'] as String?) ?? 'beginner';

    _controller = CookingModeController(
      recipe: widget.recipe,
      userId: user?.id,
      userName: userName,
      experienceLevel: experienceLevel,
    );

    // Set up callbacks
    _controller.onStartPulse = () {
      if (_mounted) {
        _pulseController.repeat(reverse: true);
      }
    };
    _controller.onStopPulse = () {
      if (_mounted) {
        _pulseController.stop();
        _pulseController.value = 0;
      }
    };
    _controller.onEndSessionAndNavigateBack = _endSessionAndNavigateBack;

    // Listen for changes
    _controller.addListener(_onControllerChanged);

    // Initialize
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (_mounted && mounted) {
      setState(() {});
      _syncUrl();
    }
  }

  void _syncUrl() {
    if (!kIsWeb) return;
    final uri = Uri(
      path: '/cook/${widget.recipe.id}',
      queryParameters: {'step': _controller.currentStepIndex.toString()},
    );
    _urlSync.replace(uri.toString());
  }

  void _hydrateStepFromUrl() {
    String? stepParam = Uri.base.queryParameters['step'];

    if (stepParam == null && Uri.base.fragment.isNotEmpty) {
      try {
        final frag = Uri.parse(
          Uri.base.fragment.startsWith('/') ? Uri.base.fragment : '/${Uri.base.fragment}',
        );
        stepParam = frag.queryParameters['step'];
      } catch (_) {}
    }

    // Will be applied after controller initialization via addListener
  }

  Future<void> _endSessionAndNavigateBack() async {
    await _controller.endSession();
    if (_mounted && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _pulseController.dispose();
    _fadeInController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.hasPermission) {
      return PermissionScreen(
        onRequestPermission: _controller.requestPermission,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Main content with tap navigation
          GestureDetector(
            onTapUp: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              final tapX = details.globalPosition.dx;

              if (tapX < screenWidth / 2) {
                if (_controller.currentStepIndex > 0) {
                  _controller.navigateToStep(_controller.currentStepIndex - 1);
                }
              } else {
                if (_controller.currentStepIndex < _controller.activeSteps.length - 1) {
                  _controller.navigateToStep(_controller.currentStepIndex + 1);
                }
              }
            },
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, child) => ReactiveBackground(
                ambientPhase: _ambientController.value,
                agentIsSpeaking: _controller.agentIsSpeaking,
                userIsSpeaking: _controller.userIsSpeaking,
                agentAudioLevel: _controller.agentAudioLevel,
                userVadScore: _controller.userVadScore,
                child: child!,
              ),
              child: SafeArea(
                child: FadeTransition(
                  opacity: _fadeInAnimation,
                  child: Stack(
                    children: [
                      // Back button
                      Positioned(
                        top: 52,
                        left: 24,
                        child: GestureDetector(
                          onTap: _endSessionAndNavigateBack,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white70,
                              size: 28,
                            ),
                          ),
                        ),
                      ),

                      // Debug toggle button
                      Positioned(
                        top: 52,
                        right: 24,
                        child: GestureDetector(
                          onTap: _controller.toggleDebugSidebar,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _controller.showDebugSidebar ? Icons.bug_report : Icons.bug_report_outlined,
                              color: _controller.showDebugSidebar ? const Color(0xFFFFB74D) : Colors.white70,
                              size: 24,
                            ),
                          ),
                        ),
                      ),

                      // Main content
                      Column(
                        children: [
                          // Progress bars at top
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: StepProgressBars(
                              activeSteps: _controller.activeSteps,
                              session: _controller.session,
                              currentStepIndex: _controller.currentStepIndex,
                              recentlyInsertedStepIds: _controller.recentlyInsertedStepIds,
                              onNavigateToStep: _controller.navigateToStep,
                            ),
                          ),

                          // Center content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Step media (image)
                                  StepMedia(
                                    session: _controller.session,
                                    activeSteps: _controller.activeSteps,
                                    currentStepIndex: _controller.currentStepIndex,
                                  ),
                                  const SizedBox(height: 20),

                                  // Instruction text
                                  CookingInstructionText(
                                    isLoadingSession: _controller.isLoadingSession,
                                    sessionError: _controller.sessionError,
                                    session: _controller.session,
                                    activeSteps: _controller.activeSteps,
                                    currentStepIndex: _controller.currentStepIndex,
                                    currentServings: _controller.currentServings,
                                    unitSystem: _controller.unitSystem,
                                    pendingTextChanges: _controller.pendingTextChanges,
                                    onTextChangeAnimationComplete: (stepId) {
                                      _controller.pendingTextChanges.remove(stepId);
                                    },
                                  ),

                                  // Served button on last step
                                  if (_controller.currentStepIndex == _controller.activeSteps.length - 1)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: GestureDetector(
                                        onTap: _endSessionAndNavigateBack,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFFB74D), Color(0xFFFF8A65)],
                                            ),
                                            borderRadius: BorderRadius.circular(30),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFFFFB74D).withValues(alpha: 0.4),
                                                blurRadius: 16,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('🍽️', style: TextStyle(fontSize: 20)),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Served!',
                                                style: GoogleFonts.lato(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Voice visualizers at bottom
                          Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: _buildVoiceVisualizers(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Cooking timers overlay
          if (_controller.activeTimers.isNotEmpty)
            CookingTimersOverlay(
              timers: _controller.activeTimers,
              onToggle: _controller.toggleTimer,
              onDismiss: _controller.dismissTimer,
              onCancel: _controller.cancelTimer,
            ),

          // Debug sidebar
          // Discrete debug panel - bottom right, translucent
          if (_controller.showDebugSidebar)
            Positioned(
              right: 16,
              bottom: 120,
              child: Container(
                width: 320,
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with close button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _controller.isConnected ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _controller.isConnected ? 'Connected' : (_controller.isConnecting ? 'Connecting...' : 'Disconnected'),
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          if (_controller.agentIsSpeaking)
                            Text('🗣️ ', style: const TextStyle(fontSize: 12)),
                          if (_controller.userIsSpeaking)
                            Text('🎤 ', style: const TextStyle(fontSize: 12)),
                          GestureDetector(
                            onTap: _controller.toggleDebugSidebar,
                            child: const Icon(Icons.close, color: Colors.white54, size: 18),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    // Log entries
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        shrinkWrap: true,
                        reverse: true,
                        itemCount: _controller.debugLogs.length,
                        itemBuilder: (context, index) {
                          final log = _controller.debugLogs[_controller.debugLogs.length - 1 - index];
                          Color typeColor;
                          switch (log.type) {
                            case 'agent':
                              typeColor = const Color(0xFFFFB74D);
                              break;
                            case 'user':
                              typeColor = const Color(0xFF64B5F6);
                              break;
                            case 'tool':
                              typeColor = const Color(0xFF81C784);
                              break;
                            case 'error':
                              typeColor = Colors.red;
                              break;
                            default:
                              typeColor = Colors.white54;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${log.type}: ${log.message.length > 60 ? '${log.message.substring(0, 60)}...' : log.message}',
                              style: GoogleFonts.jetBrainsMono(
                                color: typeColor,
                                fontSize: 10,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceVisualizers() {
    final isActive = _controller.agentIsSpeaking || _controller.userIsSpeaking;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isActive ? 1.0 : 0.3,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Agent visualizer (left)
          Column(
            children: [
              CircularSoundwave(
                level: _controller.agentAudioLevel,
                isUser: false,
                isActive: _controller.agentIsSpeaking,
                size: 80,
                barCount: 20,
              ),
              const SizedBox(height: 8),
              Text(
                'CHEF',
                style: GoogleFonts.lato(
                  color: _controller.agentIsSpeaking
                      ? const Color(0xFFFFB74D)
                      : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          const SizedBox(width: 40),

          // User visualizer (right) - tap to mute
          GestureDetector(
            onTap: _controller.isConnected ? _controller.toggleMute : null,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: _controller.isMuted ? 0.3 : 1.0,
                      child: CircularSoundwave(
                        level: _controller.isMuted ? 0.0 : _controller.userVadScore,
                        isUser: true,
                        isActive: _controller.userIsSpeaking && !_controller.isMuted,
                        size: 80,
                        barCount: 20,
                      ),
                    ),
                    if (_controller.isMuted)
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.5),
                        ),
                        child: const Icon(
                          Icons.mic_off,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _controller.isMuted ? 'MUTED' : 'YOU',
                  style: GoogleFonts.lato(
                    color: _controller.isMuted
                        ? Colors.red.withValues(alpha: 0.7)
                        : _controller.userIsSpeaking
                            ? const Color(0xFF64B5F6)
                            : Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fade page route for smooth transitions
class FadePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  FadePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        );
}
