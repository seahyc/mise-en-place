import 'enums.dart';
import 'ingredient.dart';
import 'equipment.dart';
import 'instruction.dart';

class Recipe {
  final String id;
  final String title;
  final String description;
  final String mainImageUrl;
  final String sourceLink;
  final int prepTimeMinutes;
  final int cookTimeMinutes;
  final int basePax;
  final Cuisine cuisine;
  
  final List<RecipeIngredient> ingredients;
  final List<EquipmentMaster> equipmentNeeded;
  final List<InstructionStep> instructions;

  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.mainImageUrl,
    required this.sourceLink,
    required this.prepTimeMinutes,
    required this.cookTimeMinutes,
    required this.basePax,
    required this.cuisine,
    required this.ingredients,
    required this.equipmentNeeded,
    required this.instructions,
  });
}
