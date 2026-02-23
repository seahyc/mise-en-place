import 'ingredient.dart';
import 'equipment.dart';

class InstructionStep {
  final String id;
  final int orderIndex;
  final String shortText; // "Chop Onions"
  final String detailedDescription; // Template with placeholders: "Heat {i:oil:qty} in the {e:pan}"
  final String? mediaUrl; // Video or Image
  final Duration? estimatedDuration;

  // What is used IN THIS STEP? (with placeholder keys for interpolation)
  final List<StepIngredient> stepIngredients;
  final List<StepEquipment> stepEquipment;

  const InstructionStep({
    required this.id,
    required this.orderIndex,
    required this.shortText,
    required this.detailedDescription,
    this.mediaUrl,
    this.estimatedDuration,
    this.stepIngredients = const [],
    this.stepEquipment = const [],
  });

  /// Interpolates placeholders in detailedDescription with actual values.
  /// - {i:key} → ingredient name
  /// - {i:key:qty} → "amount unit name"
  /// - {e:key} → equipment name
  String get interpolatedDescription {
    return interpolateTemplate(detailedDescription);
  }

  /// Interpolates a template string with this step's ingredients and equipment.
  String interpolateTemplate(String template) {
    var result = template;

    // Build lookup maps
    final ingredientMap = {for (var i in stepIngredients) i.placeholderKey: i};
    final equipmentMap = {for (var e in stepEquipment) e.placeholderKey: e};

    // Replace {i:key:qty} first (more specific)
    result = result.replaceAllMapped(
      RegExp(r'\{i:(\w+):qty\}'),
      (match) {
        final key = match.group(1)!;
        final ing = ingredientMap[key];
        return ing?.quantityDisplay ?? match.group(0)!;
      },
    );

    // Replace {i:key} (ingredient name only)
    result = result.replaceAllMapped(
      RegExp(r'\{i:(\w+)\}'),
      (match) {
        final key = match.group(1)!;
        final ing = ingredientMap[key];
        return ing?.master.name ?? match.group(0)!;
      },
    );

    // Replace {e:key} (equipment name)
    result = result.replaceAllMapped(
      RegExp(r'\{e:(\w+)\}'),
      (match) {
        final key = match.group(1)!;
        final equip = equipmentMap[key];
        return equip?.master.name ?? match.group(0)!;
      },
    );

    return result;
  }

  /// Returns a copy with scaled ingredient amounts.
  InstructionStep scaled(double factor) {
    return InstructionStep(
      id: id,
      orderIndex: orderIndex,
      shortText: shortText,
      detailedDescription: detailedDescription,
      mediaUrl: mediaUrl,
      estimatedDuration: estimatedDuration,
      stepIngredients: stepIngredients.map((i) => i.scaled(factor)).toList(),
      stepEquipment: stepEquipment,
    );
  }
}
