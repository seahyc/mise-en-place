/// A cooking timer that can be created by the voice agent.
///
/// Multiple timers can run concurrently (e.g., "Simmer chili", "Rest meat").
/// When a timer completes or reaches a milestone, the app notifies the ElevenLabs
/// agent via `sendContextualUpdate()` so it can verbally alert the user.
///
/// The agent can specify milestone notifications when creating the timer
/// (e.g., notify at 60, 30, 10 seconds remaining).
class CookingTimer {
  final String id;
  final String label;
  final String? emoji; // Optional emoji/icon for the timer (e.g., "🍚", "🥘", "⏰")
  final int totalSeconds;
  int remainingSeconds;
  bool isRunning;
  DateTime? startedAt;
  DateTime? pausedAt;

  /// Seconds remaining at which to notify the agent (e.g., [60, 30, 10]).
  /// The agent specifies these when creating the timer.
  /// Milestones are removed from this set as they're triggered.
  final Set<int> _pendingMilestones;

  /// Milestones that have already been triggered (to avoid duplicates).
  final Set<int> _triggeredMilestones;

  CookingTimer({
    required this.id,
    required this.label,
    this.emoji,
    required this.totalSeconds,
    int? remainingSeconds,
    this.isRunning = true,
    this.startedAt,
    this.pausedAt,
    List<int>? notifyAtSeconds,
  }) : remainingSeconds = remainingSeconds ?? totalSeconds,
       _pendingMilestones = (notifyAtSeconds ?? []).toSet(),
       _triggeredMilestones = {};

  /// Progress from 0.0 (just started) to 1.0 (completed)
  double get progress => 1 - (remainingSeconds / totalSeconds);

  /// Whether the timer has completed
  bool get isCompleted => remainingSeconds <= 0;

  /// Whether the timer is paused
  bool get isPaused => !isRunning && remainingSeconds > 0;

  /// Formatted display time (e.g., "5:30" or "1:23:45")
  String get displayTime {
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    final seconds = remainingSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Formatted total time for display
  String get totalTimeDisplay {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
    }
    return '${seconds}s';
  }

  /// Tick the timer down by one second.
  /// Returns a milestone if one was just reached, null otherwise.
  int? tick() {
    if (isRunning && remainingSeconds > 0) {
      remainingSeconds--;
      return checkMilestone();
    }
    return null;
  }

  /// Check if current remaining time matches any pending milestone.
  /// Returns the milestone seconds if triggered, null otherwise.
  int? checkMilestone() {
    if (_pendingMilestones.contains(remainingSeconds) &&
        !_triggeredMilestones.contains(remainingSeconds)) {
      _triggeredMilestones.add(remainingSeconds);
      _pendingMilestones.remove(remainingSeconds);
      return remainingSeconds;
    }
    return null;
  }

  /// Get list of remaining milestones (for debugging/display)
  List<int> get pendingMilestones => _pendingMilestones.toList()..sort((a, b) => b.compareTo(a));

  /// Pause the timer
  void pause() {
    if (isRunning) {
      isRunning = false;
      pausedAt = DateTime.now();
    }
  }

  /// Resume the timer
  void resume() {
    if (!isRunning && remainingSeconds > 0) {
      isRunning = true;
      pausedAt = null;
    }
  }

  /// Toggle pause/resume
  void toggle() {
    if (isRunning) {
      pause();
    } else {
      resume();
    }
  }

  /// Add time to the timer (extends both remaining and total)
  void addTime(int seconds) {
    if (seconds > 0) {
      remainingSeconds += seconds;
      // Note: totalSeconds is final, so progress calculation will shift
      // This is intentional - adding time "resets" progress proportionally
    }
  }

  /// Subtract time from the timer (reduces remaining, min 0)
  void subtractTime(int seconds) {
    if (seconds > 0) {
      remainingSeconds = (remainingSeconds - seconds).clamp(0, remainingSeconds);
    }
  }

  /// Create a copy with updated values
  CookingTimer copyWith({
    String? id,
    String? label,
    String? emoji,
    int? totalSeconds,
    int? remainingSeconds,
    bool? isRunning,
    DateTime? startedAt,
    DateTime? pausedAt,
  }) {
    return CookingTimer(
      id: id ?? this.id,
      label: label ?? this.label,
      emoji: emoji ?? this.emoji,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
      startedAt: startedAt ?? this.startedAt,
      pausedAt: pausedAt ?? this.pausedAt,
    );
  }

  /// Convert to JSON for voice agent responses
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'emoji': emoji,
      'total_seconds': totalSeconds,
      'remaining_seconds': remainingSeconds,
      'is_running': isRunning,
      'is_completed': isCompleted,
      'display_time': displayTime,
      'progress': progress,
      'pending_milestones': pendingMilestones,
    };
  }

  @override
  String toString() {
    return 'CookingTimer(label: $label, remaining: $displayTime, running: $isRunning)';
  }
}
