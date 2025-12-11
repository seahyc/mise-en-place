import 'dart:async' as async;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';
import '../models/instruction.dart';
import '../models/cooking_timer.dart';
import '../models/cooking_session.dart';
import '../services/auth_service.dart';
import '../services/cooking_session_service.dart';
import '../services/realtime_session_service.dart';
import '../widgets/instruction_text.dart';
import '../widgets/streaming_instruction_text.dart';
import '../widgets/debug_tools_sidebar.dart';
import '../widgets/soundwave_visualizer.dart';
import '../utils/web_url_sync.dart';

class CookingModeScreen extends StatefulWidget {
  final Recipe recipe;
  const CookingModeScreen({super.key, required this.recipe});

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen> with TickerProviderStateMixin {
  bool _hasPermission = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  int _currentStepIndex = 0;
  final int _currentServings = 1;

  // Session state
  CookingSession? _session;
  bool _isLoadingSession = true;
  String? _sessionError;
  final CookingSessionService _sessionService = CookingSessionService();
  final RealtimeSessionService _realtimeService = RealtimeSessionService();
  async.StreamSubscription<SessionStepChange>? _stepChangesSubscription;

  // Track pending text changes for streaming animation
  final Map<String, TextChangeAnimation> _pendingTextChanges = {};

  // Track recently inserted steps for visual highlighting (flash animation)
  final Set<String> _recentlyInsertedStepIds = {};

  ConversationClient? _client;
  // ignore: unused_field
  String? _conversationId;
  // ignore: unused_field
  String _statusText = "Connecting...";
  // ignore: unused_field
  String _lastTranscript = "";
  bool _isMuted = false;
  bool _agentIsSpeaking = false;
  bool _userIsSpeaking = false;
  double _userVadScore = 0.0; // Voice activity detection score 0.0-1.0
  double _agentAudioLevel = 0.0; // Simulated agent audio level
  bool _mounted = true;

  // Timer state
  final List<CookingTimer> _activeTimers = [];
  async.Timer? _tickTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Tracks auto-dismiss for completed timers
  // Key: timer ID, Value: seconds since completion
  final Map<String, int> _completedTimerSeconds = {};
  static const int _autoDismissSeconds = 60;

  // Unit system state (metric or imperial)
  String _unitSystem = 'metric';

  // Debug sidebar state
  bool _showDebugSidebar = false;
  final List<DebugLogEntry> _debugLogs = [];

  // Auto-reconnect state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  // Agent audio level simulation timer (fallback when real audio not available)
  async.Timer? _agentAudioSimTimer;
  final math.Random _audioSimRandom = math.Random();

  // Animation controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeInController;
  late Animation<double> _fadeInAnimation;
  late AnimationController _ambientController; // Slow ambient animation
  final WebUrlSync _urlSync = const WebUrlSync();

  @override
  void initState() {
    super.initState();
    print('[CookingMode] initState - recipe: ${widget.recipe.title}');

    _hydrateStepFromUrl();

    // Pulse animation for voice activity
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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

    // Slow, smooth ambient animation for wave-like morphing (10 second cycle)
    _ambientController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    print('[CookingMode] Creating session...');
    _createSession();
    print('[CookingMode] Checking permissions...');
    _checkPermissionsAndStart();
    print('[CookingMode] Initializing ElevenLabs client...');
    _initializeClient();
    _syncUrl();
  }

  Future<void> _createSession() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final userId = auth.currentUser?.id;

    try {
      final session = await _sessionService.createSession(
        recipes: [widget.recipe],
        paxMultiplier: _currentServings.toDouble(),
        userId: userId,
      );

      if (session != null) {
        _safeSetState(() {
          _session = session;
          _isLoadingSession = false;
          if (_currentStepIndex >= _activeSteps.length) {
            _currentStepIndex = _activeSteps.isEmpty ? 0 : _activeSteps.length - 1;
          }
        });
        debugPrint('[Session] Created session ${session.id} with ${session.steps.length} steps');
        _syncUrl();

        // Subscribe to realtime updates for this session
        await _subscribeToRealtimeUpdates(session.id);
      } else {
        _safeSetState(() {
          _sessionError = 'Failed to create cooking session';
          _isLoadingSession = false;
        });
      }
    } catch (e) {
      debugPrint('[Session] Error creating session: $e');
      _safeSetState(() {
        _sessionError = 'Error: $e';
        _isLoadingSession = false;
      });
    }
  }

  /// Subscribe to Supabase Realtime for session step changes.
  Future<void> _subscribeToRealtimeUpdates(String sessionId) async {
    await _realtimeService.subscribe(sessionId);

    _stepChangesSubscription = _realtimeService.stepChanges.listen(
      (change) {
        debugPrint('[Realtime] Received step change: $change');
        _handleStepChange(change);
      },
      onError: (e) {
        debugPrint('[Realtime] Step changes stream error: $e');
      },
    );
  }

  /// Handle a realtime step change from Supabase.
  void _handleStepChange(SessionStepChange change) {
    if (_session == null) return;

    // Track text changes for streaming animation
    if (change.type == StepChangeType.update && change.descriptionChanged) {
      final stepId = change.stepId;
      if (stepId != null) {
        final oldText = change.oldRecord?['detailed_description'] as String? ?? '';
        final newText = change.newRecord?['detailed_description'] as String? ?? '';
        _pendingTextChanges[stepId] = TextChangeAnimation(
          stepId: stepId,
          oldText: oldText,
          newText: newText,
          timestamp: DateTime.now(),
        );
        debugPrint('[Realtime] Text change detected for step $stepId');
      }
    }

    // Track inserted steps for visual highlighting
    if (change.type == StepChangeType.insert) {
      final stepId = change.stepId;
      if (stepId != null) {
        _recentlyInsertedStepIds.add(stepId);
        debugPrint('[Realtime] Step inserted: $stepId');

        // Auto-clear the highlight after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          if (_mounted) {
            _safeSetState(() {
              _recentlyInsertedStepIds.remove(stepId);
            });
          }
        });
      }
    }

    // Apply the change to our session state
    _safeSetState(() {
      _session = _session!.applyStepChange(change);
    });

    // Log to debug panel
    _addDebugLog('realtime', 'Step ${change.type.name}: ${change.stepId}');
  }

  void _safeSetState(VoidCallback fn) {
    if (_mounted && mounted) {
      setState(fn);
    }
  }

  /// Start simulated agent audio level animation for visual feedback
  void _startAgentAudioSimulation() {
    _agentAudioSimTimer?.cancel();
    _agentAudioSimTimer = async.Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        if (!_mounted || !_agentIsSpeaking) {
          timer.cancel();
          return;
        }
        // Generate organic-looking random audio levels
        final target = 0.4 + _audioSimRandom.nextDouble() * 0.5; // 0.4-0.9 range
        final newLevel = _agentAudioLevel * 0.6 + target * 0.4; // Smooth interpolation
        _safeSetState(() {
          _agentAudioLevel = newLevel;
        });
      },
    );
  }

  /// Add a debug log entry for display in the debug panel
  void _addDebugLog(String type, String message, {Map<String, dynamic>? metadata}) {
    _debugLogs.add(DebugLogEntry(type: type, message: message, metadata: metadata));
    // Keep only last 100 entries
    if (_debugLogs.length > 100) {
      _debugLogs.removeAt(0);
    }
  }


  void _syncUrl() {
    if (!kIsWeb) return;
    final uri = Uri(
      path: '/cook/${widget.recipe.id}',
      queryParameters: {'step': _currentStepIndex.toString()},
    );
    _urlSync.replace(uri.toString());
  }

  void _hydrateStepFromUrl() {
    String? stepParam = Uri.base.queryParameters['step'];

    // If using hash URLs (/#/cook/..), parse the fragment for query params.
    if (stepParam == null && Uri.base.fragment.isNotEmpty) {
      try {
        final frag = Uri.parse(
          Uri.base.fragment.startsWith('/') ? Uri.base.fragment : '/${Uri.base.fragment}',
        );
        stepParam = frag.queryParameters['step'];
      } catch (_) {
        stepParam = null;
      }
    }

    final parsed = int.tryParse(stepParam ?? '');
    if (parsed != null && parsed >= 0) {
      final activeSteps = _activeSteps;
      if (activeSteps.isNotEmpty) {
        _currentStepIndex = parsed.clamp(0, activeSteps.length - 1);
      } else {
        _currentStepIndex = parsed;
      }
    }
  }

  void _initializeClient() {
    print('[ElevenLabs] _initializeClient starting...');
    _client = ConversationClient(
      clientTools: {
        'get_cooking_state': GetCookingStateTool(getState: _getCookingState),
        'get_full_recipe_details': GetFullRecipeDetailsTool(getRecipeDetails: _getFullRecipeDetails),
        'navigate_to_step': NavigateToStepTool(
          onNavigate: _navigateToStep,
          getCurrentIndex: () => _currentStepIndex,
          getTotalSteps: () => _activeSteps.length,
        ),
        'mark_step_complete': MarkStepCompleteTool(
          onComplete: _markStepComplete,
          getCurrentIndex: () => _currentStepIndex,
        ),
        'manage_timer': ManageTimerTool(
          onSetTimer: _addTimer,
          onUpdateTimer: _updateTimer,
          onDismissTimer: _dismissTimer,
          getTimers: () => _activeTimers,
        ),
        'switch_units': SwitchUnitsTool(onSwitchUnits: _switchUnits),
      },
      callbacks: ConversationCallbacks(
        onConnect: ({required conversationId}) {
          print('[ElevenLabs] ✅ CONNECTED: $conversationId');
          _reconnectAttempts = 0; // Reset on successful connection
          _addDebugLog('system', 'Connected: $conversationId');
          _safeSetState(() {
            _conversationId = conversationId;
            _isConnected = true;
            _isConnecting = false;
            _statusText = "Listening...";
          });
        },
        onDisconnect: (details) {
          print('[ElevenLabs] ❌ DISCONNECTED: ${details.reason}');
          _addDebugLog('system', 'Disconnected: ${details.reason}');
          if (_mounted) {
            _pulseController.stop();
          }
          _safeSetState(() {
            _isConnected = false;
            _statusText = "Disconnected";
            _agentAudioLevel = 0.0;
          });
          // Auto-reconnect on unexpected disconnections
          _attemptReconnect(details.reason);
        },
        onStatusChange: ({required status}) {
          print('[ElevenLabs] Status changed: $status');
          _addDebugLog('system', 'Status: ${status.name}');
        },
        onMessage: ({required message, required source}) {
          print('[ElevenLabs] Message from $source: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
          // Final messages from both sides
          final type = source == Role.ai ? 'agent' : 'user';
          _addDebugLog(type, message);
        },
        onModeChange: ({required mode}) {
          print('[ElevenLabs] 🎤 Mode: $mode');
          final isSpeaking = mode == ConversationMode.speaking;
          final isListening = mode == ConversationMode.listening;
          _safeSetState(() {
            _agentIsSpeaking = isSpeaking;
            _userIsSpeaking = isListening;
            // Reset agent audio level when not speaking
            if (!isSpeaking) {
              _agentAudioLevel = 0.0;
              _agentAudioSimTimer?.cancel();
              _agentAudioSimTimer = null;
            } else {
              // Start simulated audio level animation when agent speaks
              _startAgentAudioSimulation();
            }
          });
          if (_mounted) {
            if (isSpeaking || isListening) {
              _pulseController.repeat(reverse: true);
            } else {
              _pulseController.stop();
              _pulseController.value = 0;
            }
          }
        },
        onVadScore: ({required vadScore}) {
          // Real-time voice activity detection score from microphone
          // Log occasionally to verify it's working
          if (vadScore > 0.3) {
            print('[ElevenLabs] 🎤 VAD score: ${vadScore.toStringAsFixed(2)}');
          }
          _safeSetState(() {
            _userVadScore = vadScore;
          });
        },
        onAudio: (base64Audio) {
          // Calculate RMS amplitude from agent's audio for visualization
          if (!_agentIsSpeaking) return;
          try {
            final bytes = base64.decode(base64Audio);
            // ElevenLabs sends 16-bit PCM audio at 16kHz
            // Calculate RMS of the audio samples
            double sumSquares = 0.0;
            int sampleCount = 0;
            for (int i = 0; i < bytes.length - 1; i += 2) {
              // Convert two bytes to a 16-bit signed integer (little-endian)
              int sample = bytes[i] | (bytes[i + 1] << 8);
              if (sample >= 32768) sample -= 65536; // Convert to signed
              // Normalize to -1.0 to 1.0
              final normalized = sample / 32768.0;
              sumSquares += normalized * normalized;
              sampleCount++;
            }
            if (sampleCount > 0) {
              // RMS calculation with sqrt for proper amplitude
              final rms = (sumSquares / sampleCount);
              // Scale aggressively for visual punch (sqrt + multiply)
              final level = (rms * 8.0).clamp(0.0, 1.0);
              // Fast attack, medium decay for punchy response
              final newLevel = level > _agentAudioLevel
                  ? _agentAudioLevel * 0.1 + level * 0.9  // Fast attack
                  : _agentAudioLevel * 0.6 + level * 0.4; // Medium decay
              // Log occasionally to verify audio processing
              if (newLevel > 0.3) {
                print('[ElevenLabs] 🔊 Agent audio level: ${newLevel.toStringAsFixed(2)}');
              }
              _safeSetState(() {
                _agentAudioLevel = newLevel;
              });
            }
          } catch (e) {
            // Silently ignore audio processing errors
          }
        },
        onTentativeUserTranscript: ({required transcript, required eventId}) {
          // Real-time user speech (before finalization)
          print('[ElevenLabs] 👤 (tentative) User: $transcript');
        },
        onUserTranscript: ({required transcript, required eventId}) {
          print('[ElevenLabs] 👤 User said: $transcript');
          _addDebugLog('user', transcript);
          _safeSetState(() {
            _lastTranscript = transcript;
          });
        },
        onTentativeAgentResponse: ({required response}) {
          print('[ElevenLabs] 🤖 Agent says: ${response.substring(0, response.length > 100 ? 100 : response.length)}...');
        },
        onAgentToolResponse: (response) {
          print('[ElevenLabs] 🔧 Tool response: ${response.toolName}');
          _addDebugLog('tool', '${response.toolName} (${response.toolType})${response.isError ? " [ERROR]" : ""}');
        },
        onInterruption: (event) {
          print('[ElevenLabs] 🛑 Interruption');
          _addDebugLog('system', 'User interrupted agent');
        },
        onEndCallRequested: () {
          print('[ElevenLabs] 🏁 End call requested by agent');
          _addDebugLog('system', 'Agent ended session');
          _endSessionAndNavigateBack();
        },
        onDebug: (data) {
          print('[ElevenLabs] 🐛 Debug: $data');
        },
        onError: (message, [context]) {
          print('[ElevenLabs] ⚠️ ERROR: $message, context: $context');
          _addDebugLog('error', message);
          _safeSetState(() {
            _statusText = "Error: $message";
          });
        },
      ),
    );
    print('[ElevenLabs] Client initialized: ${_client != null}');
  }

  Future<void> _checkPermissionsAndStart() async {
    print('[ElevenLabs] _checkPermissionsAndStart - isWeb: $kIsWeb');
    if (kIsWeb) {
      print('[ElevenLabs] Web platform - auto-granting permission');
      _safeSetState(() => _hasPermission = true);
      await Future.delayed(const Duration(milliseconds: 500));
      _startConversation();
      return;
    }

    final status = await Permission.microphone.request();
    _safeSetState(() {
      _hasPermission = status.isGranted;
    });

    if (status.isGranted) {
      await Future.delayed(const Duration(milliseconds: 500));
      _startConversation();
    }
  }

  Future<void> _startConversation() async {
    print('[ElevenLabs] _startConversation called');

    if (_client == null) {
      print('[ElevenLabs] ERROR: _client is null!');
      return;
    }

    // Wait for session to be created (with timeout)
    int waitMs = 0;
    while (_session == null && waitMs < 10000) {
      print('[ElevenLabs] Waiting for session to be created... (${waitMs}ms)');
      await Future.delayed(const Duration(milliseconds: 200));
      waitMs += 200;
    }

    if (_session == null) {
      print('[ElevenLabs] ERROR: Session not created after ${waitMs}ms timeout');
      _safeSetState(() {
        _isConnecting = false;
        _statusText = "Session creation failed";
      });
      return;
    }

    print('[ElevenLabs] Session ready: ${_session!.id}');

    final auth = Provider.of<AuthService>(context, listen: false);
    final user = auth.currentUser;
    final userName = auth.displayName ??
        user?.userMetadata?['full_name'] ??
        (user?.email != null ? user!.email!.split('@').first : 'Chef');
    final experienceLevel = (user?.userMetadata?['experience_level'] as String?) ?? 'beginner';

    print('[ElevenLabs] User: $userName, Experience: $experienceLevel');

    final agentId = dotenv.env['ELEVENLABS_AGENT_ID'];
    print('[ElevenLabs] Agent ID from env: ${agentId != null ? "${agentId.substring(0, 8)}..." : "NULL"}');

    if (agentId == null || agentId.isEmpty) {
      print('[ElevenLabs] ERROR: ELEVENLABS_AGENT_ID not set!');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("ELEVENLABS_AGENT_ID not set in .env"), backgroundColor: Colors.red),
      );
      _safeSetState(() {
        _isConnecting = false;
        _statusText = "Agent configuration missing";
      });
      return;
    }

    _safeSetState(() {
      _isConnecting = true;
      _statusText = "Connecting...";
    });

    try {
      // Use the actual Supabase session ID (UUID) for the modify_instructions webhook
      final sessionId = _session?.id ?? '';
      final totalMinutes = widget.recipe.prepTimeMinutes + widget.recipe.cookTimeMinutes;
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      String estimatedTime;
      if (hours > 0 && mins > 0) {
        estimatedTime = '$hours ${hours == 1 ? "hour" : "hours"} $mins ${mins == 1 ? "minute" : "minutes"}';
      } else if (hours > 0) {
        estimatedTime = '$hours ${hours == 1 ? "hour" : "hours"}';
      } else {
        estimatedTime = '$totalMinutes ${totalMinutes == 1 ? "minute" : "minutes"}';
      }
      final totalSteps = _session?.steps.length ?? widget.recipe.instructions.length;

      print('[ElevenLabs] Starting session with agentId: ${agentId.substring(0, 8)}...');
      print('[ElevenLabs] Dynamic vars: user=$userName, recipe=${widget.recipe.title}, steps=$totalSteps, session_id=$sessionId');

      await _client!.startSession(
        agentId: agentId,
        dynamicVariables: {
          'user_name': userName,
          'recipe_title': widget.recipe.title,
          'total_steps': totalSteps.toString(),
          'session_id': sessionId,
          'initial_servings': '1',
          'experience_level': experienceLevel,
          'estimated_time': estimatedTime,
        },
      );

      print('[ElevenLabs] Session started successfully!');
    } catch (e, stack) {
      print('[ElevenLabs] Failed to start session: $e');
      print('[ElevenLabs] Stack trace: $stack');
      _safeSetState(() {
        _isConnecting = false;
        _statusText = "Failed to connect";
      });
    }
  }

  Future<void> _endConversation() async {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect on manual end
    await _client?.endSession();
    _safeSetState(() {
      _isConnected = false;
      _statusText = "Session ended";
    });
  }

  /// End the cooking session and navigate back to the recipe page.
  /// Used by both the agent's end_call tool and the "Served!" button.
  Future<void> _endSessionAndNavigateBack() async {
    await _endConversation();
    if (_mounted && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _attemptReconnect(String reason) {
    // Don't reconnect if user manually ended or we've exceeded attempts
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('[ElevenLabs] Max reconnect attempts reached, not reconnecting');
      return;
    }

    // Don't reconnect on clean disconnects
    if (reason == 'user' || reason == 'completed') {
      print('[ElevenLabs] Clean disconnect ($reason), not reconnecting');
      _reconnectAttempts = 0;
      return;
    }

    _reconnectAttempts++;
    print('[ElevenLabs] 🔄 Auto-reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${_reconnectDelay.inSeconds}s...');

    _safeSetState(() {
      _statusText = "Reconnecting ($_reconnectAttempts/$_maxReconnectAttempts)...";
    });

    Future.delayed(_reconnectDelay, () {
      if (_mounted && !_isConnected && !_isConnecting) {
        print('[ElevenLabs] Attempting reconnect...');
        _startConversation();
      }
    });
  }

  Future<void> _toggleMute() async {
    if (_client == null) return;
    await _client!.toggleMute();
    _safeSetState(() {
      _isMuted = _client!.isMuted;
    });
  }

  void _navigateToStep(int stepIndex) {
    final activeSteps = _activeSteps;
    if (stepIndex >= 0 && stepIndex < activeSteps.length) {
      _safeSetState(() {
        _currentStepIndex = stepIndex;
      });
      _syncUrl();
      // Persist to DB if session exists - use actual step's DB position
      if (_session != null && stepIndex < activeSteps.length) {
        final step = activeSteps[stepIndex] as SessionStep;
        final dbIndex = _session!.steps.indexOf(step);
        _sessionService.updateCurrentStep(_session!.id, dbIndex);
      }
      debugPrint('[ClientTool] Navigated to step $stepIndex (visual index)');
    }
  }

  void _markStepComplete(int stepIndex) {
    debugPrint('[ClientTool] Marked step $stepIndex as complete (visual index)');
    final activeSteps = _activeSteps;

    // Advance to next step if completing current
    _safeSetState(() {
      if (stepIndex == _currentStepIndex && _currentStepIndex < activeSteps.length - 1) {
        _currentStepIndex++;
      }
    });
    _syncUrl();

    // Persist to DB if session exists
    if (_session != null && stepIndex < activeSteps.length) {
      final sessionStep = activeSteps[stepIndex] as SessionStep;
      final dbIndex = _session!.steps.indexOf(sessionStep);

      _sessionService.markStepCompleted(sessionStep.id);
      // Update local state
      _safeSetState(() {
        final updatedSteps = List<SessionStep>.from(_session!.steps);
        updatedSteps[dbIndex] = sessionStep.copyWith(
          isCompleted: true,
          completedAt: DateTime.now(),
        );
        _session = _session!.copyWith(steps: updatedSteps);
      });

      // Persist current step index (need to get DB index of new current step)
      if (_currentStepIndex < _activeSteps.length) {
        final newCurrentStep = _activeSteps[_currentStepIndex] as SessionStep;
        final newDbIndex = _session!.steps.indexOf(newCurrentStep);
        _sessionService.updateCurrentStep(_session!.id, newDbIndex);
      }
    }
  }

  Map<String, dynamic> _getCookingState() {
    print('[Tool] _getCookingState called');
    try {
      final activeSteps = _activeSteps;
      print('[Tool] activeSteps.length=${activeSteps.length}, _currentStepIndex=$_currentStepIndex, _session=${_session != null}');

      if (_session != null && _currentStepIndex < activeSteps.length) {
        final step = activeSteps[_currentStepIndex] as SessionStep;
        // Count completed among active steps only
        final completedIndices = <int>[];
        for (int i = 0; i < activeSteps.length; i++) {
          if ((activeSteps[i] as SessionStep).isCompleted) {
            completedIndices.add(i);
          }
        }
        // Build full instruction set
        final allSteps = <Map<String, dynamic>>[];
        for (int i = 0; i < activeSteps.length; i++) {
          final s = activeSteps[i] as SessionStep;
          allSteps.add({
            'index': i,
            'step_id': s.id,
            'title': s.shortText,
            'description': s.interpolatedDescription,
            'is_completed': s.isCompleted,
          });
        }
        final result = {
          'session_id': _session!.id,
          'current_step_index': _currentStepIndex,
          'current_step': {
            'step_id': step.id,
            'title': step.shortText,
            'description': step.interpolatedDescription,
            'is_completed': step.isCompleted,
          },
          'total_steps': activeSteps.length,
          'completed_steps': completedIndices,
          'all_steps': allSteps,
          'active_timers': _activeTimers.map((t) => t.toJson()).toList(),
          'current_servings': _currentServings,
          'pax_multiplier': _session!.paxMultiplier,
          'is_first_step': _currentStepIndex == 0,
          'is_last_step': _currentStepIndex == activeSteps.length - 1,
          'recipe_title': widget.recipe.title,
          'session_status': _session!.status.toString(),
          'unit_system': _unitSystem,
        };
        print('[Tool] _getCookingState returning: ${result.keys}');
        return result;
      }

      // Fallback to recipe instructions if session not loaded
      if (_currentStepIndex < activeSteps.length) {
        final step = activeSteps[_currentStepIndex];
        final stepData = step is InstructionStep
            ? {'title': step.shortText, 'description': step.detailedDescription}
            : {'title': 'Unknown', 'description': ''};
        // Build full instruction set from recipe
        final allSteps = <Map<String, dynamic>>[];
        for (int i = 0; i < activeSteps.length; i++) {
          final s = activeSteps[i];
          if (s is InstructionStep) {
            allSteps.add({
              'index': i,
              'title': s.shortText,
              'description': s.detailedDescription,
              'is_completed': false,
            });
          }
        }
        final result = {
          'current_step_index': _currentStepIndex,
          'current_step': stepData,
          'total_steps': activeSteps.length,
          'completed_steps': <int>[],
          'all_steps': allSteps,
          'active_timers': _activeTimers.map((t) => t.toJson()).toList(),
          'current_servings': _currentServings,
          'is_first_step': _currentStepIndex == 0,
          'is_last_step': _currentStepIndex == activeSteps.length - 1,
          'recipe_title': widget.recipe.title,
          'unit_system': _unitSystem,
        };
        print('[Tool] _getCookingState fallback returning: ${result.keys}');
        return result;
      }

      print('[Tool] _getCookingState: No steps available');
      return {'error': 'No steps available'};
    } catch (e, stack) {
      print('[Tool] _getCookingState ERROR: $e');
      print('[Tool] Stack: $stack');
      return {'error': e.toString()};
    }
  }

  Map<String, dynamic> _getFullRecipeDetails() {
    final recipe = widget.recipe;
    final paxMultiplier = _session?.paxMultiplier ?? _currentServings.toDouble();
    final activeSteps = _activeSteps;

    // Build ingredients list with scaled amounts
    final ingredients = recipe.ingredients.map((ing) {
      final scaledAmount = ing.amount * paxMultiplier;
      return {
        'name': ing.master.name,
        'amount': ing.amount,
        'scaled_amount': scaledAmount,
        'unit': ing.unit,
        'display_string': ing.displayString,
        'comment': ing.comment,
      };
    }).toList();

    // Build equipment list
    final equipment = recipe.equipmentNeeded.map((eq) {
      return {
        'name': eq.name,
        'icon_url': eq.iconUrl,
      };
    }).toList();

    // Build steps list
    final steps = <Map<String, dynamic>>[];
    for (int i = 0; i < activeSteps.length; i++) {
      final step = activeSteps[i];
      if (step is SessionStep) {
        steps.add({
          'index': i,
          'short_text': step.shortText,
          'detailed_description': step.interpolatedDescription,
          'is_completed': step.isCompleted,
        });
      } else if (step is InstructionStep) {
        steps.add({
          'index': i,
          'short_text': step.shortText,
          'detailed_description': step.detailedDescription,
        });
      }
    }

    return {
      'recipe_id': recipe.id,
      'title': recipe.title,
      'description': recipe.description,
      'base_pax': recipe.basePax,
      'current_pax': (recipe.basePax * paxMultiplier).round(),
      'pax_multiplier': paxMultiplier,
      'prep_time_minutes': recipe.prepTimeMinutes,
      'cook_time_minutes': recipe.cookTimeMinutes,
      'cuisine': recipe.cuisine.name,
      'ingredients': ingredients,
      'equipment': equipment,
      'steps': steps,
      'unit_system': _unitSystem,
    };
  }

  String _switchUnits(String unitSystem) {
    _safeSetState(() {
      _unitSystem = unitSystem;
    });
    debugPrint('[ClientTool] Switched units to: $unitSystem');
    return _unitSystem;
  }

  // Timer methods
  void _addTimer(int seconds, String label, {String? emoji, List<int>? notifyAtSeconds}) {
    print('[Timer] _addTimer called: seconds=$seconds, label=$label, emoji=$emoji');

    // Default milestone: 10 seconds warning if duration > 10s and no milestones specified
    List<int>? effectiveMilestones = notifyAtSeconds;
    if (effectiveMilestones == null && seconds > 10) {
      effectiveMilestones = [10];
    }

    final timer = CookingTimer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      label: label,
      emoji: emoji,
      totalSeconds: seconds,
      startedAt: DateTime.now(),
      notifyAtSeconds: effectiveMilestones,
    );
    _safeSetState(() {
      _activeTimers.add(timer);
      print('[Timer] Timer added to list. Total timers: ${_activeTimers.length}');
    });
    _ensureTickerRunning();
    print('[Timer] Added timer: $label ${emoji ?? ''} for $seconds seconds, milestones: $effectiveMilestones');
  }

  void _updateTimer(String timerId, {String? newLabel, String? emoji, int? addSeconds, int? subtractSeconds}) {
    print('[Timer] _updateTimer called: id=$timerId, newLabel=$newLabel, emoji=$emoji, addSeconds=$addSeconds, subtractSeconds=$subtractSeconds');
    _safeSetState(() {
      final timerIndex = _activeTimers.indexWhere((t) => t.id == timerId);
      if (timerIndex != -1) {
        final oldTimer = _activeTimers[timerIndex];

        // Apply time modifications directly on the timer object
        if (addSeconds != null && addSeconds > 0) {
          oldTimer.addTime(addSeconds);
          print('[Timer] Added $addSeconds seconds to timer: ${oldTimer.label}');
        }
        if (subtractSeconds != null && subtractSeconds > 0) {
          oldTimer.subtractTime(subtractSeconds);
          print('[Timer] Subtracted $subtractSeconds seconds from timer: ${oldTimer.label}');
        }

        // Update label/emoji if provided
        if (newLabel != null || emoji != null) {
          _activeTimers[timerIndex] = oldTimer.copyWith(
            label: newLabel ?? oldTimer.label,
            emoji: emoji ?? oldTimer.emoji,
          );
          print('[Timer] Timer updated: ${oldTimer.label} -> ${newLabel ?? oldTimer.label}');
        }
      }
    });
  }

  void _ensureTickerRunning() {
    if (_tickTimer == null || !_tickTimer!.isActive) {
      _tickTimer = async.Timer.periodic(const Duration(seconds: 1), (_) {
        _tickTimers();
      });
    }
  }

  void _tickTimers() {
    if (!_mounted) return;

    final completedTimers = <CookingTimer>[];
    final milestoneEvents = <(CookingTimer, int)>[];
    final timersToAutoDismiss = <String>[];

    for (final timer in _activeTimers) {
      if (timer.isRunning && !timer.isCompleted) {
        final milestone = timer.tick();

        // Check if a milestone was triggered
        if (milestone != null) {
          milestoneEvents.add((timer, milestone));
        }

        if (timer.isCompleted) {
          completedTimers.add(timer);
        }
      } else if (timer.isCompleted) {
        // Timer is already completed - track time since completion for auto-dismiss
        final secondsSinceComplete = _completedTimerSeconds[timer.id] ?? 0;
        _completedTimerSeconds[timer.id] = secondsSinceComplete + 1;

        // Auto-dismiss after 60 seconds
        if (secondsSinceComplete >= _autoDismissSeconds) {
          timersToAutoDismiss.add(timer.id);
        }
      }
    }

    // Handle milestone notifications
    for (final (timer, secondsRemaining) in milestoneEvents) {
      _onTimerMilestone(timer, secondsRemaining);
    }

    // Handle newly completed timers
    for (final timer in completedTimers) {
      _onTimerComplete(timer);
    }

    // Auto-dismiss timers that exceeded the timeout
    for (final timerId in timersToAutoDismiss) {
      debugPrint('[Timer] Auto-dismissing timer $timerId after $_autoDismissSeconds seconds');
      _dismissTimer(timerId);
    }

    // Stop ticker if no active or completed timers
    final hasActiveTimers = _activeTimers.isNotEmpty;
    if (!hasActiveTimers) {
      _tickTimer?.cancel();
      _tickTimer = null;
    }

    _safeSetState(() {});
  }

  void _onTimerMilestone(CookingTimer timer, int secondsRemaining) {
    debugPrint('[Timer] Milestone for ${timer.label}: $secondsRemaining seconds remaining');
    // Notify agent via contextual update (invisible to user, visible to agent)
    _client?.sendContextualUpdate(
      '[TIMER_MILESTONE] Timer "${timer.label}" has $secondsRemaining seconds remaining. '
      'Alert the user about this countdown milestone.',
    );
  }

  void _onTimerComplete(CookingTimer timer) {
    debugPrint('[Timer] Completed: ${timer.label}');
    // Initialize completion tracking for auto-dismiss
    _completedTimerSeconds[timer.id] = 0;
    // Speak the announcement (plays 3 times via TTS)
    _speakTimerCompletion(timer);
    // Notify agent via contextual update (invisible to user, visible to agent)
    // This is different from sendUserMessage - agent knows it's a system event, not user speech
    _client?.sendContextualUpdate(
      '[TIMER_COMPLETE] Timer "${timer.label}" (id: ${timer.id}) has finished! '
      'Immediately alert the user that the timer is done. '
      'The timer will auto-dismiss after 60 seconds if not acknowledged.',
    );
  }

  void _toggleTimer(String timerId) {
    final timer = _activeTimers.firstWhere((t) => t.id == timerId);
    timer.toggle();
    if (timer.isRunning) {
      _ensureTickerRunning();
    }
    _safeSetState(() {});
  }

  void _cancelTimer(String timerId) {
    _completedTimerSeconds.remove(timerId);
    _safeSetState(() {
      _activeTimers.removeWhere((t) => t.id == timerId);
    });
  }

  /// Dismiss a completed timer (used by "Got it" button and agent tool).
  /// Stops beeping and removes the timer from the active list.
  void _dismissTimer(String timerId) {
    debugPrint('[Timer] Dismissing timer: $timerId');
    _completedTimerSeconds.remove(timerId);
    _safeSetState(() {
      _activeTimers.removeWhere((t) => t.id == timerId);
    });
  }

  /// Convert a CookingTimer to a map for tool responses
  Map<String, dynamic> _timerToMap(CookingTimer timer) {
    return {
      'id': timer.id,
      'label': timer.label,
      'emoji': timer.emoji,
      'duration_seconds': timer.totalSeconds,
      'remaining_seconds': timer.remainingSeconds,
      'display_time': timer.displayTime,
      'progress': timer.progress,
      'is_running': timer.isRunning,
      'is_paused': timer.isPaused,
      'is_completed': timer.isCompleted,
      'pending_milestones': timer.pendingMilestones, // Include milestone info
    };
  }

  Future<void> _playTimerAlert() async {
    try {
      // Use a system sound or bundled asset
      await _audioPlayer.play(AssetSource('sounds/timer_complete.mp3'));
    } catch (e) {
      debugPrint('[Timer] Could not play alert sound: $e');
      // Fallback: the agent will still announce it verbally
    }
  }

  /// Speak a timer completion announcement using ElevenLabs TTS
  Future<void> _speakTimerCompletion(CookingTimer timer) async {
    final apiKey = dotenv.env['ELEVENLABS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[TTS] No API key, falling back to beep');
      await _playTimerAlert();
      return;
    }

    // Format duration for speech (e.g., "5 minutes" or "30 seconds")
    final duration = timer.totalSeconds;
    String durationText;
    if (duration >= 60) {
      final mins = duration ~/ 60;
      durationText = '$mins ${mins == 1 ? "minute" : "minutes"}';
    } else {
      durationText = '$duration seconds';
    }

    // ElevenLabs v3 audio tags use square brackets for sound effects
    final text = '[bell rings] ${timer.label} $durationText done!';
    debugPrint('[TTS] Speaking: "$text"');

    try {
      // Use Brian voice (Gordon Ramsay-like) - same as agent
      const voiceId = 'nPczCjzI2devNBz1zQrb';

      final response = await http.post(
        Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId'),
        headers: {
          'xi-api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'audio/mpeg',
        },
        body: jsonEncode({
          'text': text,
          'model_id': 'eleven_turbo_v2',
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.75,
            'speed': 1.1,
          },
        }),
      );

      if (response.statusCode == 200) {
        // Play the audio once
        await _audioPlayer.play(BytesSource(response.bodyBytes));
      } else {
        debugPrint('[TTS] API error: ${response.statusCode} - ${response.body}');
        await _playTimerAlert();
      }
    } catch (e) {
      debugPrint('[TTS] Error: $e');
      await _playTimerAlert();
    }
  }

  @override
  void dispose() {
    _mounted = false;
    // End session first to trigger callbacks while controllers still exist
    // (callbacks now check _mounted before using controllers)
    _client?.endSession();
    _stepChangesSubscription?.cancel();
    _realtimeService.dispose();
    _tickTimer?.cancel();
    _agentAudioSimTimer?.cancel();
    _audioPlayer.dispose();
    _pulseController.dispose();
    _fadeInController.dispose();
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return _buildPermissionScreen();
    }

    return Scaffold(
      body: Stack(
        children: [
          // Tap left/right to navigate steps
          GestureDetector(
            onTapUp: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              final tapX = details.globalPosition.dx;

              if (tapX < screenWidth / 2) {
                // Tap left half - previous step
                if (_currentStepIndex > 0) {
                  _navigateToStep(_currentStepIndex - 1);
                }
              } else {
                // Tap right half - next step
                if (_currentStepIndex < _activeSteps.length - 1) {
                  _navigateToStep(_currentStepIndex + 1);
                }
              }
            },
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, child) => _buildReactiveBackground(
                ambientPhase: _ambientController.value,
                child: child!,
              ),
              child: SafeArea(
                child: FadeTransition(
                  opacity: _fadeInAnimation,
                  child: Stack(
                    children: [
                      // Back button top-left (below progress bars, aligned with content padding)
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
                      // Subtle left arrow indicator (previous step)
                      if (_currentStepIndex > 0)
                        Positioned(
                          left: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Icon(
                              Icons.chevron_left,
                              color: Colors.white.withValues(alpha: 0.15),
                              size: 32,
                            ),
                          ),
                        ),
                      // Subtle right arrow indicator (next step)
                      if (_currentStepIndex < _activeSteps.length - 1)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Icon(
                              Icons.chevron_right,
                              color: Colors.white.withValues(alpha: 0.15),
                              size: 32,
                            ),
                          ),
                        ),
                      // Main content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            const SizedBox(height: 16),

                            // Instagram story-like progress bars
                            _buildStepProgressBars(),

                            const SizedBox(height: 20),

                            // Recipe title
                            Text(
                              widget.recipe.title.toUpperCase(),
                              style: GoogleFonts.lato(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 2.0,
                              ),
                            ),

                            const Spacer(),

                            // Current step instruction - centered with highlighted ingredients/equipment
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 400),
                                child: KeyedSubtree(
                                  key: ValueKey(_currentStepIndex),
                                  child: _buildInstructionText(),
                                ),
                              ),
                            ),

                            // "Served!" button on last step
                            if (_currentStepIndex == _activeSteps.length - 1 && _activeSteps.isNotEmpty)
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
                                    child: Text(
                                      'Served!',
                                      style: GoogleFonts.playfairDisplay(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            const Spacer(),

                            // Timer display (horizontal scrollable list)
                            if (_activeTimers.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: SizedBox(
                                  height: 90,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    itemCount: _activeTimers.length,
                                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                                    itemBuilder: (context, index) {
                                      final timer = _activeTimers[index];
                                      return _buildCompactTimer(timer);
                                    },
                                  ),
                                ),
                              ),

                            // Voice activity soundwave visualizers
                            _buildVoiceVisualizers(),

                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Debug panel (bottom-right) - collapsed or expanded
          Positioned(
            right: 16,
            bottom: 16,
            child: _showDebugSidebar
                ? DebugToolsSidebar(
                    tools: _getDebugTools(),
                    logEntries: _debugLogs,
                    conversationId: _conversationId,
                    connectionStatus: _isConnected ? 'connected' : (_isConnecting ? 'connecting' : 'disconnected'),
                    agentSpeaking: _agentIsSpeaking,
                    userSpeaking: _userIsSpeaking,
                    vadScore: _userVadScore,
                    lastUserTranscript: _lastTranscript,
                    activeTimers: _activeTimers.length,
                    onClose: () {
                      _safeSetState(() {
                        _showDebugSidebar = false;
                      });
                    },
                  )
                : GestureDetector(
                    onTap: () {
                      _safeSetState(() {
                        _showDebugSidebar = true;
                      });
                    },
                    child: _buildDebugStatus(),
                  ),
          ),
        ],
      ),
    );
  }

  Map<String, Function> _getDebugTools() {
    return {
      'get_cooking_state': () async {
        final result = _getCookingState();
        try {
          final json = jsonEncode(result);
          print('[DebugTool] get_cooking_state JSON OK, length: ${json.length}');
        } catch (e) {
          print('[DebugTool] get_cooking_state JSON FAILED: $e');
        }
        return result;
      },
      'get_full_recipe_details': () async {
        final result = _getFullRecipeDetails();
        try {
          final json = jsonEncode(result);
          print('[DebugTool] get_full_recipe_details JSON OK, length: ${json.length}');
        } catch (e) {
          print('[DebugTool] get_full_recipe_details JSON FAILED: $e');
        }
        return result;
      },
      'navigate_to_step': (Map<String, dynamic> params) async {
        // Supports: integer index, "next", "previous"
        final target = params['target']?.toString() ?? 'next';
        int stepIndex;
        if (target == 'next') {
          stepIndex = (_currentStepIndex + 1).clamp(0, _activeSteps.length - 1);
        } else if (target == 'previous') {
          stepIndex = (_currentStepIndex - 1).clamp(0, _activeSteps.length - 1);
        } else {
          stepIndex = int.tryParse(target) ?? _currentStepIndex;
        }
        _navigateToStep(stepIndex);
        debugPrint('[DebugTool] navigate_to_step: $target -> $stepIndex');
        return {'success': true, 'target': target, 'navigated_to': stepIndex};
      },
      'mark_step_complete': (Map<String, dynamic> params) async {
        // step_index is optional, defaults to current
        final stepParam = params['step_index'];
        final stepIndex = stepParam != null
            ? (stepParam is int ? stepParam : int.tryParse(stepParam.toString()) ?? _currentStepIndex)
            : _currentStepIndex;
        _markStepComplete(stepIndex);
        debugPrint('[DebugTool] mark_step_complete: $stepIndex');
        return {'success': true, 'step_index': stepIndex};
      },
      'manage_timer': (Map<String, dynamic> params) async {
        final action = params['action'] as String?;
        if (action == null) return {'success': false, 'error': 'action is required'};

        switch (action) {
          case 'set':
            final secondsParam = params['duration_seconds'];
            if (secondsParam == null) return {'success': false, 'error': 'duration_seconds is required for set action'};
            final seconds = secondsParam is int ? secondsParam : (secondsParam as num).toInt();
            final label = params['label'] as String?;
            if (label == null || label.isEmpty) return {'success': false, 'error': 'label is required for set action'};
            final emoji = params['emoji'] as String?;
            final rawMilestones = params['notify_at_seconds'];

            List<int>? milestones;
            if (rawMilestones != null && rawMilestones is String && rawMilestones.isNotEmpty) {
              try {
                final trimmed = rawMilestones.trim();
                if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
                  final inner = trimmed.substring(1, trimmed.length - 1);
                  if (inner.isNotEmpty) {
                    milestones = inner.split(',').map((s) => int.parse(s.trim())).toList();
                  }
                }
              } catch (e) {
                debugPrint('[DebugTool] Failed to parse milestones: $e');
              }
            }

            final effectiveEmoji = (emoji != null && emoji.isNotEmpty) ? emoji : null;
            _addTimer(seconds, label, emoji: effectiveEmoji, notifyAtSeconds: milestones);
            debugPrint('[DebugTool] manage_timer set: $seconds seconds, label: $label');
            return {'success': true, 'action': 'set', 'duration_seconds': seconds, 'label': label};

          case 'get':
            // Get timer state - optional filter by id or label
            final timerId = params['timer_id']?.toString();
            final label = params['label']?.toString();

            if (timerId != null && timerId.isNotEmpty) {
              final timer = _activeTimers.where((t) => t.id == timerId).firstOrNull;
              if (timer == null) return {'success': false, 'error': 'Timer not found: $timerId'};
              return {'success': true, 'action': 'get', 'timer': _timerToMap(timer)};
            } else if (label != null && label.isNotEmpty) {
              final timer = _activeTimers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
              if (timer == null) return {'success': false, 'error': 'Timer not found with label: $label'};
              return {'success': true, 'action': 'get', 'timer': _timerToMap(timer)};
            } else {
              // Return all timers
              return {
                'success': true,
                'action': 'get',
                'timers': _activeTimers.map(_timerToMap).toList(),
                'count': _activeTimers.length,
              };
            }

          case 'dismiss':
            String? timerId = params['timer_id']?.toString();
            final label = params['label']?.toString();

            // Find by label if provided
            if ((timerId == null || timerId.isEmpty) && label != null && label.isNotEmpty) {
              final timer = _activeTimers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
              if (timer != null) timerId = timer.id;
            }

            // Default to most recent completed or first timer
            if (timerId == null || timerId.isEmpty) {
              final completed = _activeTimers.where((t) => t.isCompleted).toList();
              if (completed.isNotEmpty) {
                timerId = completed.first.id;
              } else if (_activeTimers.isNotEmpty) {
                timerId = _activeTimers.first.id;
              }
            }

            if (timerId != null) {
              _dismissTimer(timerId);
              debugPrint('[DebugTool] manage_timer dismiss: $timerId');
              return {'success': true, 'action': 'dismiss', 'timer_id': timerId};
            }
            return {'success': false, 'error': 'No timers to dismiss'};

          default:
            return {'success': false, 'error': 'Unknown action: $action'};
        }
      },
      'switch_units': (Map<String, dynamic> params) async {
        final unitSystem = params['unit_system'] as String;
        final result = _switchUnits(unitSystem);
        debugPrint('[DebugTool] switch_units: $unitSystem -> $result');
        return {'success': true, 'unit_system': result};
      },
      // Note: modify_instructions is a webhook tool (calls n8n directly)
    };
  }

  Widget _buildPermissionScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a1a1a), Color(0xFF2d1f1a)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic_off, size: 64, color: Colors.white38),
                const SizedBox(height: 24),
                Text(
                  "Microphone Access Required",
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Voice guidance needs to hear you",
                  style: GoogleFonts.lato(color: Colors.white54, fontSize: 16),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: _checkPermissionsAndStart,
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

  /// Returns only active (non-skipped) steps
  List<dynamic> get _activeSteps {
    if (_session != null) {
      return _session!.steps.where((s) => !s.isSkipped).toList();
    }
    return widget.recipe.instructions;
  }

  /// Maps visual index (in active steps) to actual DB step
  // ignore: unused_element
  SessionStep? _getActiveStep(int visualIndex) {
    final active = _activeSteps;
    if (visualIndex >= 0 && visualIndex < active.length) {
      return active[visualIndex] as SessionStep?;
    }
    return null;
  }

  /// Builds a responsive background with morphing, wave-like colors that react to audio
  Widget _buildReactiveBackground({required double ambientPhase, required Widget child}) {
    // Get audio level based on who's speaking
    final double audioLevel = _agentIsSpeaking
        ? _agentAudioLevel
        : _userIsSpeaking
            ? _userVadScore
            : 0.0;

    final double intensity = audioLevel.clamp(0.0, 1.0);

    // Base opacity and radius
    final double orangeOpacity;
    final double blueOpacity;
    final double baseRadius;

    if (_agentIsSpeaking) {
      orangeOpacity = 0.12 + intensity * 0.25;
      blueOpacity = 0.0;
      baseRadius = 0.8 + intensity * 0.3;
    } else if (_userIsSpeaking) {
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

    // Create multiple overlapping blobs that move independently to create morphing wave effect
    // Each blob has different frequency multipliers for organic movement

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
          // Single large orange wave - slow, gentle movement
          if (orangeOpacity > 0) Positioned.fill(
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

          // Single large blue wave - slow, gentle movement (opposite phase)
          if (blueOpacity > 0) Positioned.fill(
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

  Widget _buildStepProgressBars() {
    final activeSteps = _activeSteps;
    final totalSteps = activeSteps.length;
    return Row(
      children: List.generate(totalSteps, (index) {
        // Check step status from active steps
        final bool isCompleted;
        final bool isNewlyInserted;
        String? stepId;

        if (_session != null && index < activeSteps.length) {
          final step = activeSteps[index];
          if (step is SessionStep) {
            isCompleted = step.isCompleted;
            stepId = step.id;
            isNewlyInserted = _recentlyInsertedStepIds.contains(step.id);
          } else {
            isCompleted = index < _currentStepIndex;
            isNewlyInserted = false;
          }
        } else {
          isCompleted = index < _currentStepIndex;
          isNewlyInserted = false;
        }
        final isCurrent = index == _currentStepIndex;

        // Determine bar color and shadows
        Color barColor;
        List<BoxShadow>? shadows;

        if (isNewlyInserted) {
          // Newly inserted step - green pulsing glow
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
            onTap: () => _navigateToStep(index),
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

  Widget _buildInstructionText() {
    // Loading state
    if (_isLoadingSession) {
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
    if (_sessionError != null) {
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
            _sessionError!,
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              fontSize: 14,
              color: Colors.white54,
            ),
          ),
        ],
      );
    }

    final activeSteps = _activeSteps;

    // Use session step if available
    if (_session != null && _currentStepIndex < activeSteps.length) {
      final step = activeSteps[_currentStepIndex] as SessionStep;

      // Check if there's a pending text change animation for this step
      final pendingChange = _pendingTextChanges[step.id];
      if (pendingChange != null) {
        // Clear the pending change after we start animating
        // (StreamingInstructionText handles the animation internally)
        Future.microtask(() => _pendingTextChanges.remove(step.id));

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
          unitSystem: _unitSystem,
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
        unitSystem: _unitSystem,
      );
    }

    // Fallback to recipe instructions
    if (_currentStepIndex < activeSteps.length && activeSteps[_currentStepIndex] is InstructionStep) {
      return InstructionText.fromStep(
        activeSteps[_currentStepIndex] as InstructionStep,
        textAlign: TextAlign.center,
        baseStyle: GoogleFonts.playfairDisplay(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.4,
        ),
        ingredientColor: const Color(0xFFFFB74D),
        equipmentColor: const Color(0xFF81D4FA),
        paxMultiplier: _currentServings.toDouble(),
        unitSystem: _unitSystem,
      );
    }

    return Text(
      'No steps available',
      style: GoogleFonts.playfairDisplay(color: Colors.white54),
    );
  }

  Widget _buildVoiceVisualizers() {
    final isActive = _agentIsSpeaking || _userIsSpeaking;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isActive ? 1.0 : 0.3,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Agent visualizer (left side - warm orange)
          Column(
            children: [
              CircularSoundwave(
                level: _agentAudioLevel,
                isUser: false,
                isActive: _agentIsSpeaking,
                size: 80,
                barCount: 20,
              ),
              const SizedBox(height: 8),
              Text(
                'CHEF',
                style: GoogleFonts.lato(
                  color: _agentIsSpeaking
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

          // User visualizer (right side - cool blue) - tap to mute/unmute
          GestureDetector(
            onTap: _isConnected ? _toggleMute : null,
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Greyed out when muted
                    Opacity(
                      opacity: _isMuted ? 0.3 : 1.0,
                      child: CircularSoundwave(
                        level: _isMuted ? 0.0 : _userVadScore,
                        isUser: true,
                        isActive: _userIsSpeaking && !_isMuted,
                        size: 80,
                        barCount: 20,
                      ),
                    ),
                    // Mute icon overlay when muted
                    if (_isMuted)
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
                  _isMuted ? 'MUTED' : 'YOU',
                  style: GoogleFonts.lato(
                    color: _isMuted
                        ? Colors.red.withValues(alpha: 0.7)
                        : _userIsSpeaking
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

  Widget _buildDebugStatus() {
    final status = _client?.status.name ?? 'no client';
    final connected = _isConnected ? '✅' : '❌';
    final connecting = _isConnecting ? '🔄' : '';
    final timers = _activeTimers.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            '$connected Status: $status $connecting',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          Text(
            'ConvID: ${_conversationId ?? "none"} | Timers: $timers',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          Text(
            'Agent: ${_agentIsSpeaking ? "🗣️" : "—"} | User: ${_userIsSpeaking ? "🎤" : "—"} | VAD: ${_userVadScore.toStringAsFixed(2)}',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTimer(CookingTimer timer) {
    final isCompleted = timer.isCompleted;
    final isPaused = timer.isPaused;

    Color ringColor;
    if (isCompleted) {
      ringColor = const Color(0xFF4CAF50);
    } else if (isPaused) {
      ringColor = Colors.white38;
    } else {
      // Green to red based on progress
      ringColor = Color.lerp(
        const Color(0xFF4CAF50),
        const Color(0xFFFF5252),
        timer.progress,
      )!;
    }

    return GestureDetector(
      onTap: () => _toggleTimer(timer.id),
      onLongPress: () => _cancelTimer(timer.id),
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: ringColor.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            // Mini timer ring
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: 1 - timer.progress,
                    strokeWidth: 4,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation(ringColor),
                  ),
                  if (timer.emoji != null && timer.emoji!.isNotEmpty)
                    Text(timer.emoji!, style: const TextStyle(fontSize: 18))
                  else
                    Icon(
                      isCompleted ? Icons.check : (isPaused ? Icons.pause : Icons.timer),
                      color: ringColor,
                      size: 20,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Time and label
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isCompleted ? 'Done!' : timer.displayTime,
                    style: GoogleFonts.jetBrainsMono(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    timer.label,
                    style: GoogleFonts.lato(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// Client Tool Classes
class NavigateToStepTool implements ClientTool {
  final void Function(int stepIndex) onNavigate;
  final int Function() getCurrentIndex;
  final int Function() getTotalSteps;

  NavigateToStepTool({
    required this.onNavigate,
    required this.getCurrentIndex,
    required this.getTotalSteps,
  });

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    print('[ElevenLabs Tool] navigate_to_step called with: $parameters');
    try {
      final rawTarget = parameters['target'];
      final currentIndex = getCurrentIndex();
      final totalSteps = getTotalSteps();
      int stepIndex;

      if (rawTarget == null) {
        // Default to next step
        stepIndex = (currentIndex + 1).clamp(0, totalSteps - 1);
      } else if (rawTarget is String) {
        switch (rawTarget.toLowerCase()) {
          case 'next':
            stepIndex = (currentIndex + 1).clamp(0, totalSteps - 1);
            break;
          case 'previous':
          case 'prev':
          case 'back':
            stepIndex = (currentIndex - 1).clamp(0, totalSteps - 1);
            break;
          case 'first':
            stepIndex = 0;
            break;
          case 'last':
            stepIndex = totalSteps - 1;
            break;
          default:
            // Try parsing as integer
            stepIndex = int.tryParse(rawTarget) ?? currentIndex;
        }
      } else if (rawTarget is num) {
        stepIndex = rawTarget.toInt();
      } else {
        stepIndex = currentIndex;
      }

      // Clamp to valid range
      stepIndex = stepIndex.clamp(0, totalSteps - 1);
      onNavigate(stepIndex);

      print('[ElevenLabs Tool] navigate_to_step success: $stepIndex');
      return ClientToolResult.success(jsonEncode({
        'navigated_to': stepIndex,
        'is_first': stepIndex == 0,
        'is_last': stepIndex == totalSteps - 1,
      }));
    } catch (e, stack) {
      print('[ElevenLabs Tool] navigate_to_step ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

class MarkStepCompleteTool implements ClientTool {
  final void Function(int stepIndex) onComplete;
  final int Function() getCurrentIndex;

  MarkStepCompleteTool({
    required this.onComplete,
    required this.getCurrentIndex,
  });

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    print('[ElevenLabs Tool] mark_step_complete called with: $parameters');
    try {
      final rawIndex = parameters['step_index'];
      // Default to current step if not specified
      final stepIndex = rawIndex != null
          ? (rawIndex is int ? rawIndex : (rawIndex is num ? rawIndex.toInt() : int.tryParse(rawIndex.toString()) ?? getCurrentIndex()))
          : getCurrentIndex();

      onComplete(stepIndex);
      print('[ElevenLabs Tool] mark_step_complete success: $stepIndex');
      return ClientToolResult.success(jsonEncode({'completed': stepIndex}));
    } catch (e, stack) {
      print('[ElevenLabs Tool] mark_step_complete ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

class GetCookingStateTool implements ClientTool {
  final Map<String, dynamic> Function() getState;
  DateTime? _lastCall;  // Deduplication via timing

  GetCookingStateTool({required this.getState});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    // Deduplicate: skip if called within 500ms of last call
    final now = DateTime.now();
    if (_lastCall != null && now.difference(_lastCall!).inMilliseconds < 500) {
      print('[ElevenLabs Tool] get_cooking_state SKIPPED (duplicate within 500ms)');
      return null;  // Return null to skip duplicate
    }
    _lastCall = now;

    print('[ElevenLabs Tool] get_cooking_state called');
    try {
      final result = getState();
      // Verify JSON-encodable first
      final jsonTest = jsonEncode(result);
      print('[ElevenLabs Tool] get_cooking_state success, json length: ${jsonTest.length}');
      // Return Map directly - SDK's toJson will include it as 'data' field
      return ClientToolResult.success(result);
    } catch (e, stack) {
      print('[ElevenLabs Tool] get_cooking_state ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

/// Consolidated timer management tool (set, update, get, dismiss)
class ManageTimerTool implements ClientTool {
  final void Function(int seconds, String label, {String? emoji, List<int>? notifyAtSeconds}) onSetTimer;
  final void Function(String timerId, {String? newLabel, String? emoji, int? addSeconds, int? subtractSeconds}) onUpdateTimer;
  final void Function(String timerId) onDismissTimer;
  final List<CookingTimer> Function() getTimers;

  ManageTimerTool({
    required this.onSetTimer,
    required this.onUpdateTimer,
    required this.onDismissTimer,
    required this.getTimers,
  });

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    print('[ManageTimerTool] execute called with: $parameters');

    final action = parameters['action']?.toString();
    if (action == null) {
      return ClientToolResult.failure('action is required (set, get, or dismiss)');
    }

    try {
      switch (action) {
        case 'set':
          return _handleSetTimer(parameters);
        case 'update':
          return _handleUpdateTimer(parameters);
        case 'get':
          return _handleGetTimer(parameters);
        case 'dismiss':
          return _handleDismissTimer(parameters);
        default:
          return ClientToolResult.failure('Unknown action: $action. Use set, update, get, or dismiss.');
      }
    } catch (e, stack) {
      print('[ManageTimerTool] ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }

  ClientToolResult _handleSetTimer(Map<String, dynamic> parameters) {
    // Parse duration_seconds
    final rawSeconds = parameters['duration_seconds'];
    int? seconds;
    if (rawSeconds is int) {
      seconds = rawSeconds;
    } else if (rawSeconds is double) {
      seconds = rawSeconds.toInt();
    } else if (rawSeconds is String) {
      seconds = int.tryParse(rawSeconds) ?? double.tryParse(rawSeconds)?.toInt();
    }

    final label = parameters['label']?.toString();
    final emoji = parameters['emoji']?.toString();
    final rawMilestones = parameters['notify_at_seconds'];

    // Validate required parameters
    if (seconds == null) return ClientToolResult.failure('duration_seconds is required for set action');
    if (label == null || label.isEmpty) return ClientToolResult.failure('label is required for set action');
    if (seconds <= 0) return ClientToolResult.failure('duration_seconds must be positive');
    if (seconds > 86400) return ClientToolResult.failure('duration_seconds cannot exceed 24 hours');

    // Parse milestones
    List<int>? notifyAtSeconds;
    if (rawMilestones != null) {
      notifyAtSeconds = _parseMilestones(rawMilestones, seconds);
    }

    // Add default milestone at 10 seconds if duration > 10s and no milestones specified
    if ((notifyAtSeconds == null || notifyAtSeconds.isEmpty) && seconds > 10) {
      notifyAtSeconds = [10];
    }

    onSetTimer(seconds, label, emoji: emoji, notifyAtSeconds: notifyAtSeconds);
    print('[ManageTimerTool] set success: $label for $seconds seconds');
    return ClientToolResult.success(jsonEncode({
      'action': 'set',
      'success': true,
      'label': label,
      'emoji': emoji,
      'duration_seconds': seconds,
    }));
  }

  ClientToolResult _handleUpdateTimer(Map<String, dynamic> parameters) {
    final timers = getTimers();
    String? timerId = parameters['timer_id']?.toString();
    final label = parameters['label']?.toString();
    final newLabel = parameters['new_label']?.toString();
    final emoji = parameters['emoji']?.toString();
    final addSeconds = parameters['add_seconds'] is int ? parameters['add_seconds'] as int : int.tryParse(parameters['add_seconds']?.toString() ?? '');
    final subtractSeconds = parameters['subtract_seconds'] is int ? parameters['subtract_seconds'] as int : int.tryParse(parameters['subtract_seconds']?.toString() ?? '');

    // Find timer by ID or label
    if ((timerId == null || timerId.isEmpty) && label != null && label.isNotEmpty) {
      final timer = timers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
      if (timer != null) timerId = timer.id;
    }

    // Auto-select most recent if not specified
    if (timerId == null || timerId.isEmpty) {
      if (timers.isEmpty) {
        return ClientToolResult.failure('No active timers to update');
      }
      timerId = timers.last.id;
    }

    // Validate timer exists
    final timer = timers.where((t) => t.id == timerId).firstOrNull;
    if (timer == null) {
      return ClientToolResult.failure('Timer not found: $timerId');
    }

    // Must have at least one update action
    final hasTimeChange = (addSeconds != null && addSeconds > 0) || (subtractSeconds != null && subtractSeconds > 0);
    final hasLabelChange = newLabel != null && newLabel.isNotEmpty;
    final hasEmojiChange = emoji != null && emoji.isNotEmpty;

    if (!hasTimeChange && !hasLabelChange && !hasEmojiChange) {
      return ClientToolResult.failure('Update requires at least one of: new_label, emoji, add_seconds, subtract_seconds');
    }

    onUpdateTimer(timerId, newLabel: newLabel, emoji: emoji, addSeconds: addSeconds, subtractSeconds: subtractSeconds);

    // Build response with what was changed
    final changes = <String>[];
    if (hasLabelChange) changes.add('label: $newLabel');
    if (hasEmojiChange) changes.add('emoji: $emoji');
    if (addSeconds != null && addSeconds > 0) changes.add('added ${addSeconds}s');
    if (subtractSeconds != null && subtractSeconds > 0) changes.add('subtracted ${subtractSeconds}s');

    print('[ManageTimerTool] update success: $timerId -> ${changes.join(', ')}');
    return ClientToolResult.success(jsonEncode({
      'action': 'update',
      'success': true,
      'timer_id': timerId,
      'timer_label': timer.label,
      'changes': changes,
      'new_remaining_seconds': timer.remainingSeconds,
    }));
  }

  ClientToolResult _handleGetTimer(Map<String, dynamic> parameters) {
    final timers = getTimers();
    final timerId = parameters['timer_id']?.toString();
    final label = parameters['label']?.toString();

    if (timerId != null && timerId.isNotEmpty) {
      final timer = timers.where((t) => t.id == timerId).firstOrNull;
      if (timer == null) {
        return ClientToolResult.failure('Timer not found: $timerId');
      }
      return ClientToolResult.success(jsonEncode({
        'action': 'get',
        'success': true,
        'timer': _timerToMap(timer),
      }));
    } else if (label != null && label.isNotEmpty) {
      final timer = timers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
      if (timer == null) {
        return ClientToolResult.failure('Timer not found with label: $label');
      }
      return ClientToolResult.success(jsonEncode({
        'action': 'get',
        'success': true,
        'timer': _timerToMap(timer),
      }));
    } else {
      // Return all timers
      return ClientToolResult.success(jsonEncode({
        'action': 'get',
        'success': true,
        'timers': timers.map(_timerToMap).toList(),
        'count': timers.length,
      }));
    }
  }

  ClientToolResult _handleDismissTimer(Map<String, dynamic> parameters) {
    final timers = getTimers();
    String? timerId = parameters['timer_id']?.toString();
    final label = parameters['label']?.toString();

    // Find by label if provided
    if ((timerId == null || timerId.isEmpty) && label != null && label.isNotEmpty) {
      final timer = timers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
      if (timer != null) timerId = timer.id;
    }

    // Auto-select if not specified
    if (timerId == null || timerId.isEmpty) {
      if (timers.isEmpty) {
        return ClientToolResult.failure('No active timers to dismiss');
      }
      final completed = timers.where((t) => t.isCompleted).toList();
      timerId = completed.isNotEmpty ? completed.first.id : timers.first.id;
      print('[ManageTimerTool] dismiss auto-selected: $timerId');
    }

    // Validate timer exists
    if (!timers.any((t) => t.id == timerId)) {
      return ClientToolResult.failure('Timer not found: $timerId');
    }

    onDismissTimer(timerId);
    print('[ManageTimerTool] dismiss success: $timerId');
    return ClientToolResult.success(jsonEncode({
      'action': 'dismiss',
      'success': true,
      'timer_id': timerId,
    }));
  }

  Map<String, dynamic> _timerToMap(CookingTimer timer) {
    return {
      'id': timer.id,
      'label': timer.label,
      'emoji': timer.emoji,
      'duration_seconds': timer.totalSeconds,
      'remaining_seconds': timer.remainingSeconds,
      'display_time': timer.displayTime,
      'progress': timer.progress,
      'is_running': timer.isRunning,
      'is_paused': timer.isPaused,
      'is_completed': timer.isCompleted,
      'pending_milestones': timer.pendingMilestones, // Include milestone info
    };
  }

  List<int>? _parseMilestones(dynamic rawMilestones, int duration) {
    List<dynamic> milestoneList;

    if (rawMilestones is List) {
      milestoneList = rawMilestones;
    } else if (rawMilestones is String) {
      final trimmed = rawMilestones.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        final inner = trimmed.substring(1, trimmed.length - 1);
        if (inner.isEmpty) return null;
        milestoneList = inner.split(',').map((s) => s.trim()).toList();
      } else {
        return null;
      }
    } else {
      return null;
    }

    final result = <int>[];
    for (final m in milestoneList) {
      final milestone = m is int ? m : int.tryParse(m.toString());
      if (milestone != null && milestone > 0 && milestone < duration) {
        result.add(milestone);
      }
    }
    return result.isEmpty ? null : (result.toSet().toList()..sort((a, b) => b.compareTo(a)));
  }
}

class GetFullRecipeDetailsTool implements ClientTool {
  final Map<String, dynamic> Function() getRecipeDetails;
  GetFullRecipeDetailsTool({required this.getRecipeDetails});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    print('[ElevenLabs Tool] get_full_recipe_details called');
    try {
      final result = getRecipeDetails();
      final jsonString = jsonEncode(result);
      print('[ElevenLabs Tool] get_full_recipe_details success, json length: ${jsonString.length}');
      return ClientToolResult.success(jsonString);
    } catch (e, stack) {
      print('[ElevenLabs Tool] get_full_recipe_details ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

class SwitchUnitsTool implements ClientTool {
  final String Function(String unitSystem) onSwitchUnits;
  SwitchUnitsTool({required this.onSwitchUnits});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    print('[ElevenLabs Tool] switch_units called with: $parameters');
    try {
      final unitSystem = parameters['unit_system']?.toString();

      if (unitSystem == null || unitSystem.isEmpty) {
        return ClientToolResult.failure('unit_system is required');
      }

      if (unitSystem != 'metric' && unitSystem != 'imperial') {
        return ClientToolResult.failure(
          'unit_system must be "metric" or "imperial", got "$unitSystem"',
        );
      }

      final newSystem = onSwitchUnits(unitSystem);
      print('[ElevenLabs Tool] switch_units success: $newSystem');
      return ClientToolResult.success('{"switched": true, "unit_system": "$newSystem"}');
    } catch (e, stack) {
      print('[ElevenLabs Tool] switch_units ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

// Fade page route for smooth transition
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
          transitionDuration: const Duration(milliseconds: 500),
        );
}
