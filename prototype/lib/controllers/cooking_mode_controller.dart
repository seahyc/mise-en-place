import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import '../models/recipe.dart';
import '../models/instruction.dart';
import '../models/cooking_session.dart';
import '../models/cooking_timer.dart';
import '../services/cooking_session_service.dart';
import '../services/realtime_session_service.dart';
import '../services/voice_agent_service.dart';
import '../services/cooking_timer_manager.dart';
import '../tools/cooking_mode_tools.dart';
import '../widgets/debug_tools_sidebar.dart';
import '../widgets/streaming_instruction_text.dart';

/// Controller that manages all cooking mode state and business logic.
/// Extracted from CookingModeScreen to separate concerns and reduce file size.
class CookingModeController extends ChangeNotifier {
  final Recipe recipe;
  final String? userId;
  final String userName;
  final String experienceLevel;

  CookingModeController({
    required this.recipe,
    this.userId,
    required this.userName,
    required this.experienceLevel,
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Services
  // ─────────────────────────────────────────────────────────────────────────────

  final CookingSessionService _sessionService = CookingSessionService();
  final RealtimeSessionService _realtimeService = RealtimeSessionService();
  final VoiceAgentService _voiceAgent = VoiceAgentService();
  final CookingTimerManager _timerManager = CookingTimerManager();

  StreamSubscription<SessionStepChange>? _stepChangesSubscription;

  // ─────────────────────────────────────────────────────────────────────────────
  // State
  // ─────────────────────────────────────────────────────────────────────────────

  bool _hasPermission = false;
  bool _isLoadingSession = true;
  String? _sessionError;
  CookingSession? _session;
  int _currentStepIndex = 0;
  final int _currentServings = 1;
  String _unitSystem = 'metric';

  // Voice agent state (proxied from VoiceAgentService)
  bool _agentIsSpeaking = false;
  bool _userIsSpeaking = false;
  double _userVadScore = 0.0;
  double _agentAudioLevel = 0.0;

  // Debug state
  bool _showDebugSidebar = false;
  final List<DebugLogEntry> _debugLogs = [];

  // Text animation tracking
  final Map<String, TextChangeAnimation> _pendingTextChanges = {};
  final Set<String> _recentlyInsertedStepIds = {};

  // Callbacks for UI updates that need Flutter widgets
  VoidCallback? onStartPulse;
  VoidCallback? onStopPulse;
  VoidCallback? onEndSessionAndNavigateBack;

  // ─────────────────────────────────────────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────────────────────────────────────────

  bool get hasPermission => _hasPermission;
  bool get isLoadingSession => _isLoadingSession;
  String? get sessionError => _sessionError;
  CookingSession? get session => _session;
  int get currentStepIndex => _currentStepIndex;
  int get currentServings => _currentServings;
  String get unitSystem => _unitSystem;

  bool get isConnected => _voiceAgent.isConnected;
  bool get isConnecting => _voiceAgent.isConnecting;
  String get statusText => _voiceAgent.statusText;
  bool get isMuted => _voiceAgent.isMuted;

  bool get agentIsSpeaking => _agentIsSpeaking;
  bool get userIsSpeaking => _userIsSpeaking;
  double get userVadScore => _userVadScore;
  double get agentAudioLevel => _agentAudioLevel;

  bool get showDebugSidebar => _showDebugSidebar;
  List<DebugLogEntry> get debugLogs => _debugLogs;

  List<CookingTimer> get activeTimers => _timerManager.activeTimers;

  Map<String, TextChangeAnimation> get pendingTextChanges => _pendingTextChanges;
  Set<String> get recentlyInsertedStepIds => _recentlyInsertedStepIds;

  /// Returns only active (non-skipped) steps
  List<dynamic> get activeSteps {
    if (_session != null) {
      return _session!.steps.where((s) => !s.isSkipped).toList();
    }
    return recipe.instructions;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────────

  /// Initialize the controller - call this after construction
  Future<void> initialize() async {
    debugPrint('[CookingModeController] Initializing...');

    // Setup voice agent callbacks
    _voiceAgent.onAgentSpeakingChanged = (isSpeaking) {
      _agentIsSpeaking = isSpeaking;
      notifyListeners();
    };
    _voiceAgent.onUserSpeakingChanged = (isSpeaking) {
      _userIsSpeaking = isSpeaking;
      notifyListeners();
    };
    _voiceAgent.onVadScoreChanged = (score) {
      _userVadScore = score;
      notifyListeners();
    };
    _voiceAgent.onAudioLevelChanged = (level) {
      _agentAudioLevel = level;
      notifyListeners();
    };
    _voiceAgent.onConnectionChanged = (connected, connecting) {
      notifyListeners();
    };
    _voiceAgent.onStatusChanged = (status) {
      notifyListeners();
    };
    _voiceAgent.onDebugLog = _addDebugLog;
    _voiceAgent.onEndCallRequested = () {
      onEndSessionAndNavigateBack?.call();
    };
    _voiceAgent.onStartPulse = () => onStartPulse?.call();
    _voiceAgent.onStopPulse = () => onStopPulse?.call();

    // Setup timer manager callbacks
    _timerManager.onTimersChanged = () => notifyListeners();
    _timerManager.sendContextualUpdate = (msg) => _voiceAgent.sendContextualUpdate(msg);

    // Initialize the voice agent client with tools
    _voiceAgent.initialize(clientTools: _buildClientTools());

    // Create session and check permissions
    await _createSession();
    await _checkPermissionsAndStart();
  }

  Map<String, ClientTool> _buildClientTools() {
    return {
      'get_cooking_state': GetCookingStateTool(getState: _getCookingState),
      'get_full_recipe_details': GetFullRecipeDetailsTool(getRecipeDetails: _getFullRecipeDetails),
      'navigate_to_step': NavigateToStepTool(
        onNavigate: navigateToStep,
        getCurrentIndex: () => _currentStepIndex,
        getTotalSteps: () => activeSteps.length,
      ),
      'mark_step_complete': MarkStepCompleteTool(
        onComplete: markStepComplete,
        getCurrentIndex: () => _currentStepIndex,
      ),
      'manage_timer': ManageTimerTool(
        onSetTimer: _timerManager.addTimer,
        onUpdateTimer: _timerManager.updateTimer,
        onDismissTimer: _timerManager.dismissTimer,
        getTimers: () => _timerManager.activeTimers,
      ),
      'switch_units': SwitchUnitsTool(onSwitchUnits: switchUnits),
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Session Management
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _createSession() async {
    try {
      final session = await _sessionService.createSession(
        recipes: [recipe],
        paxMultiplier: _currentServings.toDouble(),
        userId: userId,
      );

      if (session != null) {
        _session = session;
        _isLoadingSession = false;
        if (_currentStepIndex >= activeSteps.length) {
          _currentStepIndex = activeSteps.isEmpty ? 0 : activeSteps.length - 1;
        }
        notifyListeners();
        debugPrint('[Session] Created session ${session.id} with ${session.steps.length} steps');

        // Subscribe to realtime updates
        await _subscribeToRealtimeUpdates(session.id);
      } else {
        _sessionError = 'Failed to create cooking session';
        _isLoadingSession = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[Session] Error creating session: $e');
      _sessionError = 'Error: $e';
      _isLoadingSession = false;
      notifyListeners();
    }
  }

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

        // Auto-clear highlight after 3 seconds
        Future.delayed(const Duration(seconds: 3), () {
          _recentlyInsertedStepIds.remove(stepId);
          notifyListeners();
        });
      }
    }

    // Apply the change to session state
    _session = _session!.applyStepChange(change);
    notifyListeners();

    _addDebugLog('realtime', 'Step ${change.type.name}: ${change.stepId}');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Permissions & Connection
  // ─────────────────────────────────────────────────────────────────────────────

  Future<void> _checkPermissionsAndStart() async {
    debugPrint('[CookingModeController] Checking permissions - isWeb: $kIsWeb');

    if (kIsWeb) {
      debugPrint('[CookingModeController] Web platform - auto-granting permission');
      _hasPermission = true;
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 500));
      _startConversation();
      return;
    }

    final status = await Permission.microphone.request();
    _hasPermission = status.isGranted;
    notifyListeners();

    if (status.isGranted) {
      await Future.delayed(const Duration(milliseconds: 500));
      _startConversation();
    }
  }

  Future<void> requestPermission() async {
    await _checkPermissionsAndStart();
  }

  Future<void> _startConversation() async {
    debugPrint('[CookingModeController] Starting conversation...');

    // Wait for session to be created
    int waitMs = 0;
    while (_session == null && waitMs < 10000) {
      debugPrint('[CookingModeController] Waiting for session... (${waitMs}ms)');
      await Future.delayed(const Duration(milliseconds: 200));
      waitMs += 200;
    }

    if (_session == null) {
      debugPrint('[CookingModeController] ERROR: Session not created after timeout');
      return;
    }

    final totalMinutes = recipe.prepTimeMinutes + recipe.cookTimeMinutes;
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

    await _voiceAgent.startSession(
      userName: userName,
      recipeTitle: recipe.title,
      totalSteps: _session?.steps.length ?? recipe.instructions.length,
      sessionId: _session?.id ?? '',
      experienceLevel: experienceLevel,
      estimatedTime: estimatedTime,
    );
  }

  Future<void> endSession() async {
    await _voiceAgent.endSession();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    await _voiceAgent.toggleMute();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Navigation
  // ─────────────────────────────────────────────────────────────────────────────

  void navigateToStep(int stepIndex) {
    final steps = activeSteps;
    if (stepIndex >= 0 && stepIndex < steps.length) {
      _currentStepIndex = stepIndex;
      notifyListeners();

      // Persist to DB
      if (_session != null && stepIndex < steps.length) {
        final step = steps[stepIndex] as SessionStep;
        final dbIndex = _session!.steps.indexOf(step);
        debugPrint('[Navigation] Updating DB: visual=$stepIndex, db=$dbIndex');
        _sessionService.updateCurrentStep(_session!.id, dbIndex);
      }
      debugPrint('[Navigation] Navigated to step $stepIndex');
    }
  }

  void markStepComplete(int stepIndex) {
    debugPrint('[CookingModeController] Marked step $stepIndex as complete');
    final steps = activeSteps;

    // Advance to next step if completing current
    if (stepIndex == _currentStepIndex && _currentStepIndex < steps.length - 1) {
      _currentStepIndex++;
    }
    notifyListeners();

    // Persist to DB
    if (_session != null && stepIndex < steps.length) {
      final sessionStep = steps[stepIndex] as SessionStep;
      final dbIndex = _session!.steps.indexOf(sessionStep);

      _sessionService.markStepCompleted(sessionStep.id);

      // Update local state
      final updatedSteps = List<SessionStep>.from(_session!.steps);
      updatedSteps[dbIndex] = sessionStep.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
      );
      _session = _session!.copyWith(steps: updatedSteps);
      notifyListeners();

      // Persist current step index
      if (_currentStepIndex < activeSteps.length) {
        final newCurrentStep = activeSteps[_currentStepIndex] as SessionStep;
        final newDbIndex = _session!.steps.indexOf(newCurrentStep);
        _sessionService.updateCurrentStep(_session!.id, newDbIndex);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Unit System
  // ─────────────────────────────────────────────────────────────────────────────

  String switchUnits(String unitSystem) {
    _unitSystem = unitSystem;
    notifyListeners();
    debugPrint('[CookingModeController] Switched units to: $unitSystem');
    return _unitSystem;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Timer Operations (delegated to CookingTimerManager)
  // ─────────────────────────────────────────────────────────────────────────────

  void addTimer(int seconds, String label, {String? emoji, List<int>? notifyAtSeconds}) {
    _timerManager.addTimer(seconds, label, emoji: emoji, notifyAtSeconds: notifyAtSeconds);
  }

  void updateTimer(String timerId, {String? newLabel, String? emoji, int? addSeconds, int? subtractSeconds}) {
    _timerManager.updateTimer(timerId, newLabel: newLabel, emoji: emoji, addSeconds: addSeconds, subtractSeconds: subtractSeconds);
  }

  void toggleTimer(String timerId) {
    _timerManager.toggleTimer(timerId);
  }

  void cancelTimer(String timerId) {
    _timerManager.cancelTimer(timerId);
  }

  void dismissTimer(String timerId) {
    _timerManager.dismissTimer(timerId);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Debug
  // ─────────────────────────────────────────────────────────────────────────────

  void toggleDebugSidebar() {
    _showDebugSidebar = !_showDebugSidebar;
    notifyListeners();
  }

  void _addDebugLog(String type, String message, {Map<String, dynamic>? metadata}) {
    _debugLogs.add(DebugLogEntry(type: type, message: message, metadata: metadata));
    if (_debugLogs.length > 100) {
      _debugLogs.removeAt(0);
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Tool Callbacks
  // ─────────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _getCookingState() {
    debugPrint('[Tool] _getCookingState called');
    try {
      final steps = activeSteps;

      if (_session != null && _currentStepIndex < steps.length) {
        final step = steps[_currentStepIndex] as SessionStep;
        final completedIndices = <int>[];
        for (int i = 0; i < steps.length; i++) {
          if ((steps[i] as SessionStep).isCompleted) {
            completedIndices.add(i);
          }
        }

        final allSteps = <Map<String, dynamic>>[];
        for (int i = 0; i < steps.length; i++) {
          final s = steps[i] as SessionStep;
          allSteps.add({
            'index': i,
            'step_id': s.id,
            'title': s.shortText,
            'description': s.interpolatedDescription,
            'is_completed': s.isCompleted,
          });
        }

        return {
          'session_id': _session!.id,
          'current_step_index': _currentStepIndex,
          'current_step': {
            'step_id': step.id,
            'title': step.shortText,
            'description': step.interpolatedDescription,
            'is_completed': step.isCompleted,
          },
          'total_steps': steps.length,
          'completed_steps': completedIndices,
          'all_steps': allSteps,
          'active_timers': _timerManager.activeTimers.map((t) => t.toJson()).toList(),
          'current_servings': _currentServings,
          'pax_multiplier': _session!.paxMultiplier,
          'is_first_step': _currentStepIndex == 0,
          'is_last_step': _currentStepIndex == steps.length - 1,
          'recipe_title': recipe.title,
          'session_status': _session!.status.toString(),
          'unit_system': _unitSystem,
        };
      }

      // Fallback for recipe instructions
      if (_currentStepIndex < steps.length) {
        final step = steps[_currentStepIndex];
        final stepData = step is InstructionStep
            ? {'title': step.shortText, 'description': step.detailedDescription}
            : {'title': 'Unknown', 'description': ''};

        final allSteps = <Map<String, dynamic>>[];
        for (int i = 0; i < steps.length; i++) {
          final s = steps[i];
          if (s is InstructionStep) {
            allSteps.add({
              'index': i,
              'title': s.shortText,
              'description': s.detailedDescription,
              'is_completed': false,
            });
          }
        }

        return {
          'current_step_index': _currentStepIndex,
          'current_step': stepData,
          'total_steps': steps.length,
          'completed_steps': <int>[],
          'all_steps': allSteps,
          'active_timers': _timerManager.activeTimers.map((t) => t.toJson()).toList(),
          'current_servings': _currentServings,
          'is_first_step': _currentStepIndex == 0,
          'is_last_step': _currentStepIndex == steps.length - 1,
          'recipe_title': recipe.title,
          'unit_system': _unitSystem,
        };
      }

      return {'error': 'No steps available'};
    } catch (e, stack) {
      debugPrint('[Tool] _getCookingState ERROR: $e\n$stack');
      return {'error': e.toString()};
    }
  }

  Map<String, dynamic> _getFullRecipeDetails() {
    final paxMultiplier = _session?.paxMultiplier ?? _currentServings.toDouble();
    final steps = activeSteps;

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

    final equipment = recipe.equipmentNeeded.map((eq) {
      return {
        'name': eq.name,
        'icon_url': eq.iconUrl,
      };
    }).toList();

    final stepsList = <Map<String, dynamic>>[];
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      if (step is SessionStep) {
        stepsList.add({
          'index': i,
          'short_text': step.shortText,
          'detailed_description': step.interpolatedDescription,
          'is_completed': step.isCompleted,
        });
      } else if (step is InstructionStep) {
        stepsList.add({
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
      'steps': stepsList,
      'unit_system': _unitSystem,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    debugPrint('[CookingModeController] Disposing...');
    _stepChangesSubscription?.cancel();
    _realtimeService.dispose();
    _voiceAgent.dispose();
    _timerManager.dispose();
    super.dispose();
  }
}
