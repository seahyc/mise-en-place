// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CookingSessionImpl _$$CookingSessionImplFromJson(Map<String, dynamic> json) =>
    _$CookingSessionImpl(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      recipeIds:
          (json['recipe_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      steps:
          (json['steps'] as List<dynamic>?)
              ?.map((e) => SessionStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );

Map<String, dynamic> _$$CookingSessionImplToJson(
  _$CookingSessionImpl instance,
) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'status': instance.status,
  'recipe_ids': instance.recipeIds,
  'steps': instance.steps,
  'created_at': instance.createdAt?.toIso8601String(),
  'started_at': instance.startedAt?.toIso8601String(),
  'completed_at': instance.completedAt?.toIso8601String(),
};

_$SessionStepImpl _$$SessionStepImplFromJson(Map<String, dynamic> json) =>
    _$SessionStepImpl(
      id: json['id'] as String,
      orderIndex: (json['order_index'] as num).toInt(),
      text: json['text'] as String,
      sourceDishTag: json['source_dish_tag'] as String?,
      isCompleted: json['is_completed'] as bool? ?? false,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      agentNotes: json['agent_notes'] as String?,
    );

Map<String, dynamic> _$$SessionStepImplToJson(_$SessionStepImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'order_index': instance.orderIndex,
      'text': instance.text,
      'source_dish_tag': instance.sourceDishTag,
      'is_completed': instance.isCompleted,
      'completed_at': instance.completedAt?.toIso8601String(),
      'agent_notes': instance.agentNotes,
    };
