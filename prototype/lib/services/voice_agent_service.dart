import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';

/// Callback type definitions for voice agent events
typedef OnAgentSpeakingChanged = void Function(bool isSpeaking);
typedef OnUserSpeakingChanged = void Function(bool isSpeaking);
typedef OnVadScoreChanged = void Function(double vadScore);
typedef OnAudioLevelChanged = void Function(double level);
typedef OnConnectionChanged = void Function(bool isConnected, bool isConnecting);
typedef OnStatusChanged = void Function(String status);
typedef OnDebugLog = void Function(String type, String message, {Map<String, dynamic>? metadata});
typedef OnEndCallRequested = void Function();

/// Service that manages the ElevenLabs voice agent connection and lifecycle.
/// Extracted from CookingModeScreen to separate concerns.
class VoiceAgentService {
  // Re-export ClientTool type for convenience
  // ignore: constant_identifier_names
  static const Type ClientToolType = ClientTool;
  ConversationClient? _client;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _statusText = "Connecting...";

  // Reconnection state
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  static const Duration _reconnectDelay = Duration(seconds: 2);

  // Audio level state
  double _agentAudioLevel = 0.0;
  bool _agentIsSpeaking = false;

  // Callbacks
  OnAgentSpeakingChanged? onAgentSpeakingChanged;
  OnUserSpeakingChanged? onUserSpeakingChanged;
  OnVadScoreChanged? onVadScoreChanged;
  OnAudioLevelChanged? onAudioLevelChanged;
  OnConnectionChanged? onConnectionChanged;
  OnStatusChanged? onStatusChanged;
  OnDebugLog? onDebugLog;
  OnEndCallRequested? onEndCallRequested;

  // Pulse animation callbacks (for visual feedback)
  VoidCallback? onStartPulse;
  VoidCallback? onStopPulse;

  // Getters
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get statusText => _statusText;
  double get agentAudioLevel => _agentAudioLevel;
  bool get isMuted => _client?.isMuted ?? false;
  ConversationStatus? get status => _client?.status;

  /// Initialize the conversation client with client tools
  void initialize({required Map<String, ClientTool> clientTools}) {
    debugPrint('[VoiceAgent] Initializing client...');

    _client = ConversationClient(
      clientTools: clientTools,
      callbacks: ConversationCallbacks(
        onConnect: _handleConnect,
        onDisconnect: _handleDisconnect,
        onStatusChange: _handleStatusChange,
        onMessage: _handleMessage,
        onModeChange: _handleModeChange,
        onVadScore: _handleVadScore,
        onAudio: _handleAudio,
        onTentativeUserTranscript: _handleTentativeUserTranscript,
        onUserTranscript: _handleUserTranscript,
        onTentativeAgentResponse: _handleTentativeAgentResponse,
        onAgentToolResponse: _handleAgentToolResponse,
        onInterruption: _handleInterruption,
        onEndCallRequested: _handleEndCallRequested,
        onDebug: _handleDebug,
        onError: _handleError,
      ),
    );

    debugPrint('[VoiceAgent] Client initialized: ${_client != null}');
  }

  /// Start a conversation session with the ElevenLabs agent
  Future<bool> startSession({
    required String userName,
    required String recipeTitle,
    required int totalSteps,
    required String sessionId,
    required String experienceLevel,
    required String estimatedTime,
  }) async {
    debugPrint('[VoiceAgent] Starting session...');

    if (_client == null) {
      debugPrint('[VoiceAgent] ERROR: Client is null!');
      return false;
    }

    final agentId = dotenv.env['ELEVENLABS_AGENT_ID'];
    debugPrint('[VoiceAgent] Agent ID: ${agentId != null ? "${agentId.substring(0, 8)}..." : "NULL"}');

    if (agentId == null || agentId.isEmpty) {
      debugPrint('[VoiceAgent] ERROR: ELEVENLABS_AGENT_ID not set!');
      _statusText = "Agent configuration missing";
      onStatusChanged?.call(_statusText);
      return false;
    }

    _isConnecting = true;
    _statusText = "Connecting...";
    onConnectionChanged?.call(_isConnected, _isConnecting);
    onStatusChanged?.call(_statusText);

    try {
      debugPrint('[VoiceAgent] Starting session with agentId: ${agentId.substring(0, 8)}...');
      debugPrint('[VoiceAgent] Dynamic vars: user=$userName, recipe=$recipeTitle, steps=$totalSteps, session_id=$sessionId');

      await _client!.startSession(
        agentId: agentId,
        dynamicVariables: {
          'user_name': userName,
          'recipe_title': recipeTitle,
          'total_steps': totalSteps.toString(),
          'session_id': sessionId,
          'initial_servings': '1',
          'experience_level': experienceLevel,
          'estimated_time': estimatedTime,
        },
      );

      debugPrint('[VoiceAgent] Session started successfully!');
      return true;
    } catch (e, stack) {
      debugPrint('[VoiceAgent] Failed to start session: $e');
      debugPrint('[VoiceAgent] Stack trace: $stack');
      _isConnecting = false;
      _statusText = "Failed to connect";
      onConnectionChanged?.call(_isConnected, _isConnecting);
      onStatusChanged?.call(_statusText);
      return false;
    }
  }

  /// End the current conversation session
  Future<void> endSession() async {
    _reconnectAttempts = _maxReconnectAttempts; // Prevent auto-reconnect
    await _client?.endSession();
    _isConnected = false;
    _statusText = "Session ended";
    onConnectionChanged?.call(_isConnected, _isConnecting);
    onStatusChanged?.call(_statusText);
  }

  /// Toggle microphone mute state
  Future<void> toggleMute() async {
    if (_client == null) return;
    await _client!.toggleMute();
  }

  /// Send a contextual update to the agent
  void sendContextualUpdate(String message) {
    _client?.sendContextualUpdate(message);
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    debugPrint('[VoiceAgent] Disposing...');
    _client?.endSession();
    _client?.dispose();
    _client = null;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Callback Handlers
  // ─────────────────────────────────────────────────────────────────────────────

  void _handleConnect({required String conversationId}) {
    debugPrint('[VoiceAgent] ✅ CONNECTED: $conversationId');
    _reconnectAttempts = 0;
    _isConnected = true;
    _isConnecting = false;
    _statusText = "Listening...";
    onConnectionChanged?.call(_isConnected, _isConnecting);
    onStatusChanged?.call(_statusText);
    onDebugLog?.call('system', 'Connected: $conversationId');
  }

  void _handleDisconnect(DisconnectionDetails details) {
    debugPrint('[VoiceAgent] ❌ DISCONNECTED: ${details.reason}');
    onStopPulse?.call();
    _isConnected = false;
    _agentAudioLevel = 0.0;
    _statusText = "Disconnected";
    onConnectionChanged?.call(_isConnected, _isConnecting);
    onStatusChanged?.call(_statusText);
    onAudioLevelChanged?.call(_agentAudioLevel);
    onDebugLog?.call('system', 'Disconnected: ${details.reason}');

    // Auto-reconnect on unexpected disconnections
    _attemptReconnect(details.reason);
  }

  void _handleStatusChange({required ConversationStatus status}) {
    debugPrint('[VoiceAgent] Status changed: $status');
    onDebugLog?.call('system', 'Status: ${status.name}');
  }

  void _handleMessage({required String message, required Role source}) {
    debugPrint('[VoiceAgent] Message from $source: ${message.substring(0, message.length > 100 ? 100 : message.length)}...');
    final type = source == Role.ai ? 'agent' : 'user';
    onDebugLog?.call(type, message);
  }

  void _handleModeChange({required ConversationMode mode}) {
    debugPrint('[VoiceAgent] 🎤 Mode: $mode');
    final isSpeaking = mode == ConversationMode.speaking;
    final isListening = mode == ConversationMode.listening;

    _agentIsSpeaking = isSpeaking;
    onAgentSpeakingChanged?.call(isSpeaking);
    onUserSpeakingChanged?.call(isListening);

    if (!isSpeaking) {
      _agentAudioLevel = 0.0;
      onAudioLevelChanged?.call(_agentAudioLevel);
    }

    if (isSpeaking || isListening) {
      onStartPulse?.call();
    } else {
      onStopPulse?.call();
    }
  }

  void _handleVadScore({required double vadScore}) {
    if (vadScore > 0.3) {
      debugPrint('[VoiceAgent] 🎤 VAD score: ${vadScore.toStringAsFixed(2)}');
    }
    onVadScoreChanged?.call(vadScore);
  }

  void _handleAudio(String base64Audio) {
    if (!_agentIsSpeaking) return;

    try {
      final bytes = base64.decode(base64Audio);
      // Calculate RMS amplitude from 16-bit PCM audio
      double sumSquares = 0.0;
      int sampleCount = 0;
      for (int i = 0; i < bytes.length - 1; i += 2) {
        int sample = bytes[i] | (bytes[i + 1] << 8);
        if (sample >= 32768) sample -= 65536;
        final normalized = sample / 32768.0;
        sumSquares += normalized * normalized;
        sampleCount++;
      }
      if (sampleCount > 0) {
        final rms = (sumSquares / sampleCount);
        final level = (rms * 8.0).clamp(0.0, 1.0);
        // Fast attack, medium decay
        final newLevel = level > _agentAudioLevel
            ? _agentAudioLevel * 0.1 + level * 0.9
            : _agentAudioLevel * 0.6 + level * 0.4;

        if (newLevel > 0.3) {
          debugPrint('[VoiceAgent] 🔊 Agent audio level: ${newLevel.toStringAsFixed(2)}');
        }
        _agentAudioLevel = newLevel;
        onAudioLevelChanged?.call(_agentAudioLevel);
      }
    } catch (e) {
      // Silently ignore audio processing errors
    }
  }

  void _handleTentativeUserTranscript({required String transcript, required int eventId}) {
    debugPrint('[VoiceAgent] 👤 (tentative) User: $transcript');
  }

  void _handleUserTranscript({required String transcript, required int eventId}) {
    debugPrint('[VoiceAgent] 👤 User said: $transcript');
    onDebugLog?.call('user', transcript);
  }

  void _handleTentativeAgentResponse({required String response}) {
    debugPrint('[VoiceAgent] 🤖 Agent says: ${response.substring(0, response.length > 100 ? 100 : response.length)}...');
  }

  void _handleAgentToolResponse(AgentToolResponse response) {
    debugPrint('[VoiceAgent] 🔧 Tool response: ${response.toolName}');
    onDebugLog?.call('tool', '${response.toolName} (${response.toolType})${response.isError ? " [ERROR]" : ""}');
  }

  void _handleInterruption(InterruptionEvent event) {
    debugPrint('[VoiceAgent] 🛑 Interruption');
    onDebugLog?.call('system', 'User interrupted agent');
  }

  void _handleEndCallRequested() {
    debugPrint('[VoiceAgent] 🏁 End call requested by agent');
    onDebugLog?.call('system', 'Agent ended session');
    onEndCallRequested?.call();
  }

  void _handleDebug(dynamic data) {
    final dataStr = data.toString();
    if (dataStr.contains('tool') || dataStr.contains('Tool')) {
      debugPrint('[VoiceAgent] 🔧 Tool: $data');
    }
  }

  void _handleError(String message, [dynamic context]) {
    debugPrint('[VoiceAgent] ⚠️ ERROR: $message, context: $context');
    _statusText = "Error: $message";
    onStatusChanged?.call(_statusText);
    onDebugLog?.call('error', message);
  }

  void _attemptReconnect(String reason) {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[VoiceAgent] Max reconnect attempts reached');
      return;
    }

    if (reason == 'user' || reason == 'completed') {
      debugPrint('[VoiceAgent] Clean disconnect ($reason), not reconnecting');
      _reconnectAttempts = 0;
      return;
    }

    _reconnectAttempts++;
    debugPrint('[VoiceAgent] 🔄 Auto-reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts in ${_reconnectDelay.inSeconds}s...');

    _statusText = "Reconnecting ($_reconnectAttempts/$_maxReconnectAttempts)...";
    onStatusChanged?.call(_statusText);

    // Note: The actual reconnection should be triggered by the caller
    // since we need session data to reconnect
  }
}
