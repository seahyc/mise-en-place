import 'package:flutter/foundation.dart';
import '../models/cooking_session.dart';
import '../models/recipe.dart';
import '../models/enums.dart';
import '../data/supabase_init.dart';

/// Service for managing cooking sessions in Supabase.
///
/// A cooking session is a mutable copy of recipe instructions that can be
/// modified by the voice agent without affecting the original recipe.
class CookingSessionService {
  /// Create a new cooking session from one or more recipes.
  ///
  /// Copies all instruction steps from the source recipes into session_steps,
  /// scaling ingredients by [paxMultiplier] if provided.
  Future<CookingSession?> createSession({
    required List<Recipe> recipes,
    double paxMultiplier = 1.0,
    String? userId,
  }) async {
    try {
      // 1. Create the session record
      final sessionData = {
        'user_id': userId,
        'status': 'setup',
        'pax_multiplier': paxMultiplier,
        'current_step_index': 0,
        'source_recipe_ids': recipes.map((r) => r.id).toList(),
        'created_at': DateTime.now().toIso8601String(),
      };

      final sessionResponse = await supabase
          .from('cooking_sessions')
          .insert(sessionData)
          .select()
          .single();

      final sessionId = sessionResponse['id'] as String;

      // 2. Copy all instruction steps from recipes into session_steps
      int orderIndex = 0;
      for (final recipe in recipes) {
        for (final step in recipe.instructions) {
          // Insert session step
          final stepData = {
            'session_id': sessionId,
            'source_step_id': step.id,
            'order_index': orderIndex,
            'short_text': step.shortText,
            'detailed_description': step.detailedDescription,
            'media_url': step.mediaUrl,
            'is_completed': false,
            'is_skipped': false,
          };

          final stepResponse = await supabase
              .from('session_steps')
              .insert(stepData)
              .select()
              .single();

          final sessionStepId = stepResponse['id'] as String;

          // Copy step ingredients with scaling
          for (final ing in step.stepIngredients) {
            final scaledAmount = ing.amount != null
                ? ing.amount! * paxMultiplier
                : null;

            await supabase.from('session_step_ingredients').insert({
              'session_step_id': sessionStepId,
              'ingredient_id': ing.master.id,
              'original_amount': scaledAmount,
              'adjusted_amount': scaledAmount,
              'unit_id': null, // Would need to look up unit_id from unit name
              'placeholder_key': ing.placeholderKey,
              'is_substitution': false,
            });
          }

          // Copy step equipment
          for (final eq in step.stepEquipment) {
            await supabase.from('session_step_equipment').insert({
              'session_step_id': sessionStepId,
              'equipment_id': eq.master.id,
              'placeholder_key': eq.placeholderKey,
              'is_substitution': false,
            });
          }

          orderIndex++;
        }
      }

      // 3. Fetch the complete session with all nested data
      return await getSession(sessionId);
    } catch (e, st) {
      debugPrint('Error creating session: $e\n$st');
      return null;
    }
  }

  /// Fetch a cooking session with all steps and nested data.
  Future<CookingSession?> getSession(String sessionId) async {
    try {
      final response = await supabase
          .from('cooking_sessions')
          .select('''
            *,
            session_steps (
              *,
              session_step_ingredients (
                *,
                ingredient_master (*),
                unit_master (*)
              ),
              session_step_equipment (
                *,
                equipment_master (*)
              )
            )
          ''')
          .eq('id', sessionId)
          .single();

      // Sort steps by order_index
      final steps = response['session_steps'] as List<dynamic>? ?? [];
      steps.sort((a, b) =>
          (a['order_index'] as int).compareTo(b['order_index'] as int));
      response['session_steps'] = steps;

      return CookingSession.fromJson(response);
    } catch (e, st) {
      debugPrint('Error fetching session $sessionId: $e\n$st');
      return null;
    }
  }

  /// Update the status of a session.
  Future<bool> updateSessionStatus(
    String sessionId,
    SessionStatus status,
  ) async {
    try {
      final statusStr = _sessionStatusToString(status);
      final updates = <String, dynamic>{'status': statusStr};

      if (status == SessionStatus.inProgress) {
        updates['started_at'] = DateTime.now().toIso8601String();
      } else if (status == SessionStatus.completed) {
        updates['completed_at'] = DateTime.now().toIso8601String();
      }

      await supabase
          .from('cooking_sessions')
          .update(updates)
          .eq('id', sessionId);

      return true;
    } catch (e, st) {
      debugPrint('Error updating session status: $e\n$st');
      return false;
    }
  }

  /// Update the current step index.
  Future<bool> updateCurrentStep(String sessionId, int stepIndex) async {
    try {
      await supabase
          .from('cooking_sessions')
          .update({'current_step_index': stepIndex})
          .eq('id', sessionId);

      return true;
    } catch (e, st) {
      debugPrint('Error updating current step: $e\n$st');
      return false;
    }
  }

  /// Mark a step as completed.
  Future<bool> markStepCompleted(String sessionStepId) async {
    try {
      await supabase.from('session_steps').update({
        'is_completed': true,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionStepId);

      return true;
    } catch (e, st) {
      debugPrint('Error marking step completed: $e\n$st');
      return false;
    }
  }

  /// Mark a step as skipped.
  Future<bool> markStepSkipped(String sessionStepId) async {
    try {
      await supabase.from('session_steps').update({
        'is_skipped': true,
      }).eq('id', sessionStepId);

      return true;
    } catch (e, st) {
      debugPrint('Error marking step skipped: $e\n$st');
      return false;
    }
  }

  /// Add agent notes to a step.
  Future<bool> addAgentNotes(String sessionStepId, String notes) async {
    try {
      await supabase.from('session_steps').update({
        'agent_notes': notes,
      }).eq('id', sessionStepId);

      return true;
    } catch (e, st) {
      debugPrint('Error adding agent notes: $e\n$st');
      return false;
    }
  }

  /// Log a modification made by the agent (or n8n workflow).
  Future<bool> logModification({
    required String sessionId,
    int? stepIndex,
    required String modificationType,
    Map<String, dynamic>? requestDetails,
    Map<String, dynamic>? changesMade,
  }) async {
    try {
      await supabase.from('session_modifications').insert({
        'session_id': sessionId,
        'step_index': stepIndex,
        'modification_type': modificationType,
        'request_details': requestDetails,
        'changes_made': changesMade,
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e, st) {
      debugPrint('Error logging modification: $e\n$st');
      return false;
    }
  }

  /// Substitute an ingredient in a session step.
  Future<bool> substituteIngredient({
    required String sessionStepId,
    required String placeholderKey,
    required String newIngredientId,
    double? newAmount,
    String? note,
  }) async {
    try {
      await supabase
          .from('session_step_ingredients')
          .update({
            'ingredient_id': newIngredientId,
            'adjusted_amount': newAmount,
            'is_substitution': true,
            'substitution_note': note,
          })
          .eq('session_step_id', sessionStepId)
          .eq('placeholder_key', placeholderKey);

      return true;
    } catch (e, st) {
      debugPrint('Error substituting ingredient: $e\n$st');
      return false;
    }
  }

  /// Adjust the amount of an ingredient in a session step.
  Future<bool> adjustIngredientAmount({
    required String sessionStepId,
    required String placeholderKey,
    required double newAmount,
  }) async {
    try {
      await supabase
          .from('session_step_ingredients')
          .update({'adjusted_amount': newAmount})
          .eq('session_step_id', sessionStepId)
          .eq('placeholder_key', placeholderKey);

      return true;
    } catch (e, st) {
      debugPrint('Error adjusting ingredient amount: $e\n$st');
      return false;
    }
  }

  /// Insert a new step (created by agent/n8n) into the session.
  Future<String?> insertStep({
    required String sessionId,
    required int orderIndex,
    required String shortText,
    required String detailedDescription,
    String? mediaUrl,
  }) async {
    try {
      // First, shift all steps at or after this index
      await supabase.rpc('shift_session_steps', params: {
        'p_session_id': sessionId,
        'p_from_index': orderIndex,
      });

      // Insert the new step
      final response = await supabase
          .from('session_steps')
          .insert({
            'session_id': sessionId,
            'source_step_id': null, // Agent-created step
            'order_index': orderIndex,
            'short_text': shortText,
            'detailed_description': detailedDescription,
            'media_url': mediaUrl,
            'is_completed': false,
            'is_skipped': false,
            'agent_notes': 'Added by voice agent',
          })
          .select()
          .single();

      return response['id'] as String?;
    } catch (e, st) {
      debugPrint('Error inserting step: $e\n$st');
      return null;
    }
  }

  String _sessionStatusToString(SessionStatus status) {
    switch (status) {
      case SessionStatus.setup:
        return 'setup';
      case SessionStatus.inProgress:
        return 'in_progress';
      case SessionStatus.paused:
        return 'paused';
      case SessionStatus.completed:
        return 'completed';
      case SessionStatus.abandoned:
        return 'abandoned';
    }
  }
}
