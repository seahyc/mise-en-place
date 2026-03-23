// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recipe.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$RecipeImpl _$$RecipeImplFromJson(Map<String, dynamic> json) => _$RecipeImpl(
  id: json['id'] as String,
  title: json['title'] as String,
  description: json['description'] as String? ?? '',
  sourceUrl: json['source_url'] as String?,
  sourceType: json['source_type'] as String? ?? 'manual',
  cuisine: json['cuisine'] as String?,
  imageUrl: json['image_url'] as String?,
  ingredients:
      (json['ingredients'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  steps:
      (json['steps'] as List<dynamic>?)
          ?.map((e) => RecipeStep.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  createdAt: json['created_at'] == null
      ? null
      : DateTime.parse(json['created_at'] as String),
  updatedAt: json['updated_at'] == null
      ? null
      : DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$$RecipeImplToJson(_$RecipeImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'source_url': instance.sourceUrl,
      'source_type': instance.sourceType,
      'cuisine': instance.cuisine,
      'image_url': instance.imageUrl,
      'ingredients': instance.ingredients,
      'steps': instance.steps,
      'created_at': instance.createdAt?.toIso8601String(),
      'updated_at': instance.updatedAt?.toIso8601String(),
    };

_$RecipeStepImpl _$$RecipeStepImplFromJson(Map<String, dynamic> json) =>
    _$RecipeStepImpl(
      orderIndex: (json['order_index'] as num).toInt(),
      text: json['text'] as String,
      imageUrl: json['image_url'] as String?,
    );

Map<String, dynamic> _$$RecipeStepImplToJson(_$RecipeStepImpl instance) =>
    <String, dynamic>{
      'order_index': instance.orderIndex,
      'text': instance.text,
      'image_url': instance.imageUrl,
    };
