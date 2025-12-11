import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../models/cooking_timer.dart';

/// Callback types for timer events
typedef OnTimerMilestone = void Function(CookingTimer timer, int secondsRemaining);
typedef OnTimerComplete = void Function(CookingTimer timer);
typedef OnTimersChanged = void Function();

/// Manages cooking timers with tick updates, milestones, and completion handling.
/// Extracted from CookingModeScreen to separate concerns.
class CookingTimerManager {
  final List<CookingTimer> _activeTimers = [];
  Timer? _tickTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Auto-dismiss tracking
  final Map<String, int> _completedTimerSeconds = {};
  static const int _autoDismissSeconds = 10;

  // Callbacks
  OnTimerMilestone? onTimerMilestone;
  OnTimerComplete? onTimerComplete;
  OnTimersChanged? onTimersChanged;

  // External notification callback (for agent)
  void Function(String message)? sendContextualUpdate;

  /// Get all active timers
  List<CookingTimer> get activeTimers => List.unmodifiable(_activeTimers);

  /// Add a new timer
  void addTimer(int seconds, String label, {String? emoji, List<int>? notifyAtSeconds}) {
    debugPrint('[Timer] Adding timer: seconds=$seconds, label=$label, emoji=$emoji');

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

    _activeTimers.add(timer);
    debugPrint('[Timer] Timer added. Total timers: ${_activeTimers.length}');

    _ensureTickerRunning();
    onTimersChanged?.call();

    debugPrint('[Timer] Added timer: $label ${emoji ?? ''} for $seconds seconds, milestones: $effectiveMilestones');
  }

  /// Update an existing timer
  void updateTimer(String timerId, {String? newLabel, String? emoji, int? addSeconds, int? subtractSeconds}) {
    debugPrint('[Timer] Updating timer: id=$timerId, newLabel=$newLabel, emoji=$emoji, addSeconds=$addSeconds, subtractSeconds=$subtractSeconds');

    final timerIndex = _activeTimers.indexWhere((t) => t.id == timerId);
    if (timerIndex == -1) {
      debugPrint('[Timer] Timer not found: $timerId');
      return;
    }

    final oldTimer = _activeTimers[timerIndex];

    // Apply time modifications
    if (addSeconds != null && addSeconds > 0) {
      oldTimer.addTime(addSeconds);
      debugPrint('[Timer] Added $addSeconds seconds to timer: ${oldTimer.label}');
    }
    if (subtractSeconds != null && subtractSeconds > 0) {
      oldTimer.subtractTime(subtractSeconds);
      debugPrint('[Timer] Subtracted $subtractSeconds seconds from timer: ${oldTimer.label}');
    }

    // Update label/emoji if provided
    if (newLabel != null || emoji != null) {
      _activeTimers[timerIndex] = oldTimer.copyWith(
        label: newLabel ?? oldTimer.label,
        emoji: emoji ?? oldTimer.emoji,
      );
      debugPrint('[Timer] Timer updated: ${oldTimer.label} -> ${newLabel ?? oldTimer.label}');
    }

    onTimersChanged?.call();
  }

  /// Toggle timer pause/resume
  void toggleTimer(String timerId) {
    final timer = _activeTimers.firstWhere(
      (t) => t.id == timerId,
      orElse: () => throw StateError('Timer not found: $timerId'),
    );
    timer.toggle();
    if (timer.isRunning) {
      _ensureTickerRunning();
    }
    onTimersChanged?.call();
  }

  /// Cancel (remove) a timer
  void cancelTimer(String timerId) {
    _completedTimerSeconds.remove(timerId);
    _activeTimers.removeWhere((t) => t.id == timerId);
    onTimersChanged?.call();
  }

  /// Dismiss a completed timer (stops beeping and removes)
  void dismissTimer(String timerId) {
    debugPrint('[Timer] Dismissing timer: $timerId');
    _completedTimerSeconds.remove(timerId);
    _activeTimers.removeWhere((t) => t.id == timerId);
    onTimersChanged?.call();
  }

  /// Ensure the tick timer is running
  void _ensureTickerRunning() {
    if (_tickTimer == null || !_tickTimer!.isActive) {
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _tickTimers();
      });
    }
  }

  /// Process timer ticks
  void _tickTimers() {
    final completedTimers = <CookingTimer>[];
    final milestoneEvents = <(CookingTimer, int)>[];
    final timersToAutoDismiss = <String>[];

    for (final timer in _activeTimers) {
      if (timer.isRunning && !timer.isCompleted) {
        final milestone = timer.tick();

        if (milestone != null) {
          milestoneEvents.add((timer, milestone));
        }

        if (timer.isCompleted) {
          completedTimers.add(timer);
        }
      } else if (timer.isCompleted) {
        // Track time since completion for auto-dismiss
        final secondsSinceComplete = _completedTimerSeconds[timer.id] ?? 0;
        _completedTimerSeconds[timer.id] = secondsSinceComplete + 1;

        if (secondsSinceComplete >= _autoDismissSeconds) {
          timersToAutoDismiss.add(timer.id);
        }
      }
    }

    // Handle milestone notifications
    for (final (timer, secondsRemaining) in milestoneEvents) {
      _handleTimerMilestone(timer, secondsRemaining);
    }

    // Handle newly completed timers
    for (final timer in completedTimers) {
      _handleTimerComplete(timer);
    }

    // Auto-dismiss timed-out timers
    for (final timerId in timersToAutoDismiss) {
      debugPrint('[Timer] Auto-dismissing timer $timerId after $_autoDismissSeconds seconds');
      dismissTimer(timerId);
    }

    // Stop ticker if no active timers
    if (_activeTimers.isEmpty) {
      _tickTimer?.cancel();
      _tickTimer = null;
    }

    onTimersChanged?.call();
  }

  void _handleTimerMilestone(CookingTimer timer, int secondsRemaining) {
    debugPrint('[Timer] Milestone for ${timer.label}: $secondsRemaining seconds remaining');
    onTimerMilestone?.call(timer, secondsRemaining);

    sendContextualUpdate?.call(
      '[TIMER_MILESTONE] Timer "${timer.label}" has $secondsRemaining seconds remaining. '
      'Alert the user about this countdown milestone.',
    );
  }

  void _handleTimerComplete(CookingTimer timer) {
    debugPrint('[Timer] Completed: ${timer.label}');
    _completedTimerSeconds[timer.id] = 0;

    // Speak the completion announcement
    _speakTimerCompletion(timer);

    onTimerComplete?.call(timer);

    sendContextualUpdate?.call(
      '[TIMER_COMPLETE] Timer "${timer.label}" (id: ${timer.id}) has finished! '
      'Immediately alert the user that the timer is done. '
      'The timer will auto-dismiss after 10 seconds if not acknowledged.',
    );
  }

  /// Play timer alert sound
  Future<void> _playTimerAlert() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/timer_complete.mp3'));
    } catch (e) {
      debugPrint('[Timer] Could not play alert sound: $e');
    }
  }

  /// Speak timer completion using ElevenLabs TTS
  Future<void> _speakTimerCompletion(CookingTimer timer) async {
    final apiKey = dotenv.env['ELEVENLABS_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[TTS] No API key, falling back to beep');
      await _playTimerAlert();
      return;
    }

    // Format duration for speech
    final duration = timer.totalSeconds;
    String durationText;
    if (duration >= 60) {
      final mins = duration ~/ 60;
      durationText = '$mins ${mins == 1 ? "minute" : "minutes"}';
    } else {
      durationText = '$duration seconds';
    }

    final text = '[bell rings] ${timer.label} $durationText done!';
    debugPrint('[TTS] Speaking: "$text"');

    try {
      const voiceId = 'nPczCjzI2devNBz1zQrb'; // Brian voice

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

  /// Convert a CookingTimer to a map for tool responses
  static Map<String, dynamic> timerToMap(CookingTimer timer) {
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
      'pending_milestones': timer.pendingMilestones,
    };
  }

  /// Dispose of the manager and clean up resources
  void dispose() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _audioPlayer.dispose();
    _activeTimers.clear();
    _completedTimerSeconds.clear();
  }
}
