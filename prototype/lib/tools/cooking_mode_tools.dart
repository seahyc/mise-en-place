import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:elevenlabs_agents/elevenlabs_agents.dart';
import '../models/cooking_timer.dart';

/// Tool for navigating between cooking steps
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
    debugPrint('[Tool] navigate_to_step called with: $parameters');
    try {
      final rawTarget = parameters['target'];
      final currentIndex = getCurrentIndex();
      final totalSteps = getTotalSteps();
      int stepIndex;

      if (rawTarget == null) {
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
            stepIndex = int.tryParse(rawTarget) ?? currentIndex;
        }
      } else if (rawTarget is num) {
        stepIndex = rawTarget.toInt();
      } else {
        stepIndex = currentIndex;
      }

      stepIndex = stepIndex.clamp(0, totalSteps - 1);
      onNavigate(stepIndex);

      debugPrint('[Tool] navigate_to_step success: $stepIndex');
      return ClientToolResult.success(jsonEncode({
        'navigated_to': stepIndex,
        'is_first': stepIndex == 0,
        'is_last': stepIndex == totalSteps - 1,
      }));
    } catch (e, stack) {
      debugPrint('[Tool] navigate_to_step ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

/// Tool for marking steps as complete
class MarkStepCompleteTool implements ClientTool {
  final void Function(int stepIndex) onComplete;
  final int Function() getCurrentIndex;

  MarkStepCompleteTool({
    required this.onComplete,
    required this.getCurrentIndex,
  });

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    debugPrint('[Tool] mark_step_complete called with: $parameters');
    try {
      final rawIndex = parameters['step_index'];
      final stepIndex = rawIndex != null
          ? (rawIndex is int ? rawIndex : (rawIndex is num ? rawIndex.toInt() : int.tryParse(rawIndex.toString()) ?? getCurrentIndex()))
          : getCurrentIndex();

      onComplete(stepIndex);
      debugPrint('[Tool] mark_step_complete success: $stepIndex');
      return ClientToolResult.success(jsonEncode({'completed': stepIndex}));
    } catch (e, stack) {
      debugPrint('[Tool] mark_step_complete ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

/// Tool for getting the current cooking state
class GetCookingStateTool implements ClientTool {
  final Map<String, dynamic> Function() getState;
  DateTime? _lastCall;

  GetCookingStateTool({required this.getState});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    // Deduplicate: skip if called within 500ms
    final now = DateTime.now();
    if (_lastCall != null && now.difference(_lastCall!).inMilliseconds < 500) {
      debugPrint('[Tool] get_cooking_state SKIPPED (duplicate within 500ms)');
      return null;
    }
    _lastCall = now;

    debugPrint('[Tool] get_cooking_state called');
    try {
      final result = getState();
      final jsonTest = jsonEncode(result);
      debugPrint('[Tool] get_cooking_state success, json length: ${jsonTest.length}');
      return ClientToolResult.success(result);
    } catch (e, stack) {
      debugPrint('[Tool] get_cooking_state ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}

/// Tool for getting full recipe details
class GetFullRecipeDetailsTool implements ClientTool {
  final Map<String, dynamic> Function() getRecipeDetails;
  GetFullRecipeDetailsTool({required this.getRecipeDetails});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    debugPrint('[Tool] get_full_recipe_details called');
    try {
      final result = getRecipeDetails();
      final jsonString = jsonEncode(result);
      debugPrint('[Tool] get_full_recipe_details success, json length: ${jsonString.length}');
      return ClientToolResult.success(jsonString);
    } catch (e, stack) {
      debugPrint('[Tool] get_full_recipe_details ERROR: $e\n$stack');
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
    debugPrint('[ManageTimerTool] execute called with: $parameters');

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
      debugPrint('[ManageTimerTool] ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }

  ClientToolResult _handleSetTimer(Map<String, dynamic> parameters) {
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

    if (seconds == null) return ClientToolResult.failure('duration_seconds is required for set action');
    if (label == null || label.isEmpty) return ClientToolResult.failure('label is required for set action');
    if (seconds <= 0) return ClientToolResult.failure('duration_seconds must be positive');
    if (seconds > 86400) return ClientToolResult.failure('duration_seconds cannot exceed 24 hours');

    List<int>? notifyAtSeconds;
    if (rawMilestones != null) {
      notifyAtSeconds = _parseMilestones(rawMilestones, seconds);
    }

    if ((notifyAtSeconds == null || notifyAtSeconds.isEmpty) && seconds > 10) {
      notifyAtSeconds = [10];
    }

    onSetTimer(seconds, label, emoji: emoji, notifyAtSeconds: notifyAtSeconds);
    debugPrint('[ManageTimerTool] set success: $label for $seconds seconds');
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

    if ((timerId == null || timerId.isEmpty) && label != null && label.isNotEmpty) {
      final timer = timers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
      if (timer != null) timerId = timer.id;
    }

    if (timerId == null || timerId.isEmpty) {
      if (timers.isEmpty) {
        return ClientToolResult.failure('No active timers to update');
      }
      timerId = timers.last.id;
    }

    final timer = timers.where((t) => t.id == timerId).firstOrNull;
    if (timer == null) {
      return ClientToolResult.failure('Timer not found: $timerId');
    }

    final hasTimeChange = (addSeconds != null && addSeconds > 0) || (subtractSeconds != null && subtractSeconds > 0);
    final hasLabelChange = newLabel != null && newLabel.isNotEmpty;
    final hasEmojiChange = emoji != null && emoji.isNotEmpty;

    if (!hasTimeChange && !hasLabelChange && !hasEmojiChange) {
      return ClientToolResult.failure('Update requires at least one of: new_label, emoji, add_seconds, subtract_seconds');
    }

    onUpdateTimer(timerId, newLabel: newLabel, emoji: emoji, addSeconds: addSeconds, subtractSeconds: subtractSeconds);

    final changes = <String>[];
    if (hasLabelChange) changes.add('label: $newLabel');
    if (hasEmojiChange) changes.add('emoji: $emoji');
    if (addSeconds != null && addSeconds > 0) changes.add('added ${addSeconds}s');
    if (subtractSeconds != null && subtractSeconds > 0) changes.add('subtracted ${subtractSeconds}s');

    debugPrint('[ManageTimerTool] update success: $timerId -> ${changes.join(', ')}');
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

    if ((timerId == null || timerId.isEmpty) && label != null && label.isNotEmpty) {
      final timer = timers.where((t) => t.label.toLowerCase() == label.toLowerCase()).firstOrNull;
      if (timer != null) timerId = timer.id;
    }

    if (timerId == null || timerId.isEmpty) {
      if (timers.isEmpty) {
        return ClientToolResult.failure('No active timers to dismiss');
      }
      final completed = timers.where((t) => t.isCompleted).toList();
      timerId = completed.isNotEmpty ? completed.first.id : timers.first.id;
      debugPrint('[ManageTimerTool] dismiss auto-selected: $timerId');
    }

    if (!timers.any((t) => t.id == timerId)) {
      return ClientToolResult.failure('Timer not found: $timerId');
    }

    onDismissTimer(timerId);
    debugPrint('[ManageTimerTool] dismiss success: $timerId');
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
      'pending_milestones': timer.pendingMilestones,
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

/// Tool for switching unit systems
class SwitchUnitsTool implements ClientTool {
  final String Function(String unitSystem) onSwitchUnits;
  SwitchUnitsTool({required this.onSwitchUnits});

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    debugPrint('[Tool] switch_units called with: $parameters');
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
      debugPrint('[Tool] switch_units success: $newSystem');
      return ClientToolResult.success('{"switched": true, "unit_system": "$newSystem"}');
    } catch (e, stack) {
      debugPrint('[Tool] switch_units ERROR: $e\n$stack');
      return ClientToolResult.failure(e.toString());
    }
  }
}
