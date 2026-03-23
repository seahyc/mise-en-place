import 'package:freezed_annotation/freezed_annotation.dart';

part 'recipe.freezed.dart';
part 'recipe.g.dart';

@freezed
class Recipe with _$Recipe {
  const factory Recipe({
    required String id,
    required String title,
    @Default('') String description,
    @JsonKey(name: 'source_url') String? sourceUrl,
    @JsonKey(name: 'source_type') @Default('manual') String sourceType,
    String? cuisine,
    @JsonKey(name: 'image_url') String? imageUrl,
    @Default([]) List<String> ingredients,
    @Default([]) List<RecipeStep> steps,
    @JsonKey(name: 'created_at') DateTime? createdAt,
    @JsonKey(name: 'updated_at') DateTime? updatedAt,
  }) = _Recipe;

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);
}

@freezed
class RecipeStep with _$RecipeStep {
  const factory RecipeStep({
    @JsonKey(name: 'order_index') required int orderIndex,
    required String text,
    @JsonKey(name: 'image_url') String? imageUrl,
  }) = _RecipeStep;

  factory RecipeStep.fromJson(Map<String, dynamic> json) =>
      _$RecipeStepFromJson(json);
}
