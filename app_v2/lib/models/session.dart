import 'package:freezed_annotation/freezed_annotation.dart';

part 'session.freezed.dart';
part 'session.g.dart';

@freezed
class CookingSession with _$CookingSession {
  const factory CookingSession({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required String status,
    @JsonKey(name: 'recipe_ids') @Default([]) List<String> recipeIds,
    @Default([]) List<SessionStep> steps,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'started_at') DateTime? startedAt,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
  }) = _CookingSession;

  factory CookingSession.fromJson(Map<String, dynamic> json) =>
      _$CookingSessionFromJson(json);
}

@freezed
class SessionStep with _$SessionStep {
  const factory SessionStep({
    required String id,
    @JsonKey(name: 'order_index') required int orderIndex,
    required String text,
    @JsonKey(name: 'source_dish_tag') String? sourceDishTag,
    @JsonKey(name: 'is_completed') @Default(false) bool isCompleted,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'agent_notes') String? agentNotes,
  }) = _SessionStep;

  factory SessionStep.fromJson(Map<String, dynamic> json) =>
      _$SessionStepFromJson(json);
}
