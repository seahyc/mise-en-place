import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/supabase_init.dart';
import '../models/cooking_session.dart';

/// Types of changes that can occur to session steps.
enum StepChangeType { insert, update, delete }

/// Represents a change to a session step from Supabase Realtime.
class SessionStepChange {
  final StepChangeType type;
  final Map<String, dynamic>? oldRecord;
  final Map<String, dynamic>? newRecord;

  /// The step ID affected by this change.
  String? get stepId => newRecord?['id'] ?? oldRecord?['id'];

  /// The order index of the affected step.
  int? get orderIndex =>
      newRecord?['order_index'] ?? oldRecord?['order_index'];

  /// For updates, returns fields that changed.
  Map<String, dynamic> get changedFields {
    if (type != StepChangeType.update ||
        oldRecord == null ||
        newRecord == null) {
      return {};
    }

    final changes = <String, dynamic>{};
    for (final key in newRecord!.keys) {
      if (oldRecord![key] != newRecord![key]) {
        changes[key] = {
          'old': oldRecord![key],
          'new': newRecord![key],
        };
      }
    }
    return changes;
  }

  /// Check if detailed_description changed (for text streaming).
  bool get descriptionChanged =>
      changedFields.containsKey('detailed_description');

  /// Check if short_text changed.
  bool get shortTextChanged => changedFields.containsKey('short_text');

  const SessionStepChange({
    required this.type,
    this.oldRecord,
    this.newRecord,
  });

  @override
  String toString() =>
      'SessionStepChange($type, stepId: $stepId, changes: ${changedFields.keys})';
}

/// Service for subscribing to realtime changes on cooking sessions.
///
/// Uses Supabase Realtime Postgres Changes to push updates when:
/// - Steps are modified (text changes from agent)
/// - Steps are inserted (new steps added by agent)
/// - Steps are deleted or reordered
class RealtimeSessionService {
  RealtimeChannel? _stepsChannel;
  RealtimeChannel? _sessionChannel;
  final _stepChangesController =
      StreamController<SessionStepChange>.broadcast();
  final _sessionChangesController =
      StreamController<Map<String, dynamic>>.broadcast();

  String? _currentSessionId;

  /// Stream of step changes for the subscribed session.
  Stream<SessionStepChange> get stepChanges => _stepChangesController.stream;

  /// Stream of session-level changes (status, current_step_index, etc).
  Stream<Map<String, dynamic>> get sessionChanges =>
      _sessionChangesController.stream;

  /// Whether currently subscribed to a session.
  bool get isSubscribed => _currentSessionId != null;

  /// The session ID currently being watched.
  String? get currentSessionId => _currentSessionId;

  /// Subscribe to realtime changes for a cooking session.
  ///
  /// Listens to both `session_steps` and `cooking_sessions` tables.
  Future<void> subscribe(String sessionId) async {
    // Unsubscribe from any existing subscription first
    await unsubscribe();

    _currentSessionId = sessionId;
    debugPrint('[Realtime] Subscribing to session: $sessionId');

    // Subscribe to session_steps changes
    _stepsChannel = supabase
        .channel('session_steps:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'session_steps',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            debugPrint('[Realtime] Step INSERT: ${payload.newRecord}');
            _stepChangesController.add(SessionStepChange(
              type: StepChangeType.insert,
              newRecord: payload.newRecord,
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'session_steps',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            debugPrint('[Realtime] Step UPDATE: ${payload.newRecord['id']}');
            debugPrint('[Realtime]   old: ${payload.oldRecord}');
            debugPrint('[Realtime]   new: ${payload.newRecord}');
            _stepChangesController.add(SessionStepChange(
              type: StepChangeType.update,
              oldRecord: payload.oldRecord,
              newRecord: payload.newRecord,
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'session_steps',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            debugPrint('[Realtime] Step DELETE: ${payload.oldRecord}');
            _stepChangesController.add(SessionStepChange(
              type: StepChangeType.delete,
              oldRecord: payload.oldRecord,
            ));
          },
        )
        .subscribe((status, error) {
          debugPrint('[Realtime] Steps channel status: $status');
          if (error != null) {
            debugPrint('[Realtime] Steps channel error: $error');
          }
        });

    // Subscribe to cooking_sessions changes (for status, current_step_index)
    _sessionChannel = supabase
        .channel('cooking_sessions:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'cooking_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: sessionId,
          ),
          callback: (payload) {
            debugPrint('[Realtime] Session UPDATE: ${payload.newRecord}');
            _sessionChangesController.add(payload.newRecord);
          },
        )
        .subscribe((status, error) {
          debugPrint('[Realtime] Session channel status: $status');
          if (error != null) {
            debugPrint('[Realtime] Session channel error: $error');
          }
        });
  }

  /// Unsubscribe from all realtime channels.
  Future<void> unsubscribe() async {
    if (_currentSessionId != null) {
      debugPrint('[Realtime] Unsubscribing from session: $_currentSessionId');
    }

    await _stepsChannel?.unsubscribe();
    await _sessionChannel?.unsubscribe();
    _stepsChannel = null;
    _sessionChannel = null;
    _currentSessionId = null;
  }

  /// Dispose of the service and clean up resources.
  Future<void> dispose() async {
    await unsubscribe();
    await _stepChangesController.close();
    await _sessionChangesController.close();
  }
}

/// Extension to apply realtime changes to a CookingSession.
extension CookingSessionRealtime on CookingSession {
  /// Apply a step change to this session, returning an updated copy.
  CookingSession applyStepChange(SessionStepChange change) {
    final updatedSteps = List<SessionStep>.from(steps);

    switch (change.type) {
      case StepChangeType.insert:
        if (change.newRecord != null) {
          final newStep = SessionStep.fromJson(change.newRecord!);
          // Insert at correct position based on order_index
          final insertIndex = updatedSteps.indexWhere(
            (s) => s.orderIndex > newStep.orderIndex,
          );
          if (insertIndex == -1) {
            updatedSteps.add(newStep);
          } else {
            updatedSteps.insert(insertIndex, newStep);
          }
          debugPrint(
              '[Realtime] Inserted step at index ${newStep.orderIndex}');
        }
        break;

      case StepChangeType.update:
        if (change.newRecord != null) {
          final stepId = change.stepId;
          final index = updatedSteps.indexWhere((s) => s.id == stepId);
          if (index != -1) {
            // Merge new data with existing step to preserve nested data
            // that might not be in the realtime payload
            final existingStep = updatedSteps[index];
            final updatedStep = _mergeStepUpdate(existingStep, change.newRecord!);
            updatedSteps[index] = updatedStep;
            debugPrint('[Realtime] Updated step at index $index');
          }
        }
        break;

      case StepChangeType.delete:
        if (change.oldRecord != null) {
          final stepId = change.stepId;
          updatedSteps.removeWhere((s) => s.id == stepId);
          debugPrint('[Realtime] Deleted step $stepId');
        }
        break;
    }

    // Re-sort by order_index to ensure correct order after changes
    updatedSteps.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    return copyWith(steps: updatedSteps);
  }

  /// Merge an update payload into an existing step.
  /// Preserves nested data (ingredients, equipment) that aren't in payload.
  SessionStep _mergeStepUpdate(
      SessionStep existing, Map<String, dynamic> update) {
    return existing.copyWith(
      orderIndex: update['order_index'] ?? existing.orderIndex,
      shortText: update['short_text'] ?? existing.shortText,
      detailedDescription:
          update['detailed_description'] ?? existing.detailedDescription,
      mediaUrl: update['media_url'] ?? existing.mediaUrl,
      isCompleted: update['is_completed'] ?? existing.isCompleted,
      isSkipped: update['is_skipped'] ?? existing.isSkipped,
      agentNotes: update['agent_notes'] ?? existing.agentNotes,
      completedAt: update['completed_at'] != null
          ? DateTime.tryParse(update['completed_at'])
          : existing.completedAt,
      // Keep existing nested data - these require separate queries
      stepIngredients: existing.stepIngredients,
      stepEquipment: existing.stepEquipment,
    );
  }
}
