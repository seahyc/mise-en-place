import 'package:flutter/foundation.dart'; // For debugPrint
import '../models/recipe.dart';
import '../models/ingredient.dart';
import '../models/equipment.dart';
import '../models/instruction.dart';
import '../models/enums.dart';
import '../data/supabase_init.dart'; // Fixed path

class RecipeService {

  // Fetch all recipes (Home Screen)
  Future<List<Recipe>> getRecipes() async {
    try {
      final response = await supabase
          .from('recipes')
          .select('''
            *,
            recipe_ingredients (
              *,
              ingredient_master (*),
              unit_master (*)
            ),
            recipe_equipment (
              *,
              equipment_master (*)
            ),
            instruction_steps (
              *,
              step_ingredients (
                *,
                ingredient_master (*),
                unit_master (*)
              ),
              step_equipment (
                *,
                equipment_master (*)
              )
            )
          '''); // Fetching everything eagerly for prototype simplicity

      return (response as List).map<Recipe>((json) => _mapJsonToRecipe(json as Map<String, dynamic>)).toList();
    } catch (e, st) {
      debugPrint("Error fetching recipes: $e\n$st");
      rethrow;
    }
  }

  // Fetch single recipe by ID
  Future<Recipe?> getRecipeById(String id) async {
    try {
      final response = await supabase
          .from('recipes')
          .select('''
            *,
            recipe_ingredients (
              *,
              ingredient_master (*),
              unit_master (*)
            ),
            recipe_equipment (
              *,
              equipment_master (*)
            ),
            instruction_steps (
              *,
              step_ingredients (
                *,
                ingredient_master (*),
                unit_master (*)
              ),
              step_equipment (
                *,
                equipment_master (*)
              )
            )
          ''')
          .eq('id', id)
          .single();

      return _mapJsonToRecipe(response);
    } catch (e, st) {
      debugPrint("Error fetching recipe $id: $e\n$st");
      return null;
    }
  }

  Recipe _mapJsonToRecipe(Map<String, dynamic> json) {
    // 1. Ingredients
    final List<dynamic> ingredientsJson = json['recipe_ingredients'] ?? [];
    final ingredients = ingredientsJson.map<RecipeIngredient>((i) {
        final master = i['ingredient_master'] as Map<String, dynamic>? ?? {};
        final unitMaster = i['unit_master'] as Map<String, dynamic>?;
        return RecipeIngredient(
          master: IngredientMaster(
            id: master['id'] ?? '',
            name: master['name'] ?? '',
            defaultImageUrl: master['default_image_url']
          ),
          amount: (i['amount'] as num?)?.toDouble() ?? 0,
          unit: unitMaster?['name'] ?? unitMaster?['abbreviation'] ?? '',
          displayString: i['display_string'] ?? '',
          comment: i['comment']
        );
    }).toList();

    // 2. Equipment
    final List<dynamic> equipmentJson = json['recipe_equipment'] ?? [];
    final equipment = equipmentJson.map<EquipmentMaster>((e) {
      final master = e['equipment_master'] as Map<String, dynamic>? ?? {};
      return EquipmentMaster(
        id: master['id'] ?? '',
        name: master['name'] ?? '',
        iconUrl: master['icon_url']
      );
    }).toList();

    // 3. Instructions with step-level ingredients and equipment
    final List<dynamic> stepsJson = json['instruction_steps'] ?? [];
    // Sort by order_index
    stepsJson.sort((a, b) => ((a['order_index'] ?? 0) as int).compareTo((b['order_index'] ?? 0) as int));

    final instructions = stepsJson.map<InstructionStep>((s) {
      // Parse step ingredients
      final List<dynamic> stepIngredientsJson = s['step_ingredients'] ?? [];
      final stepIngredients = stepIngredientsJson.map<StepIngredient>((si) {
        final master = si['ingredient_master'] as Map<String, dynamic>? ?? {};
        final unitMaster = si['unit_master'] as Map<String, dynamic>?;
        return StepIngredient(
          id: si['id'] ?? '',
          master: IngredientMaster(
            id: master['id'] ?? '',
            name: master['name'] ?? '',
            defaultImageUrl: master['default_image_url'],
          ),
          amount: (si['amount'] as num?)?.toDouble(),
          unit: unitMaster?['abbreviation'] ?? unitMaster?['name'],
          placeholderKey: si['placeholder_key'] ?? '',
        );
      }).toList();

      // Parse step equipment
      final List<dynamic> stepEquipmentJson = s['step_equipment'] ?? [];
      final stepEquipment = stepEquipmentJson.map<StepEquipment>((se) {
        final master = se['equipment_master'] as Map<String, dynamic>? ?? {};
        return StepEquipment(
          id: se['id'] ?? '',
          master: EquipmentMaster(
            id: master['id'] ?? '',
            name: master['name'] ?? '',
            iconUrl: master['icon_url'],
          ),
          placeholderKey: se['placeholder_key'] ?? '',
        );
      }).toList();

      return InstructionStep(
        id: s['id'],
        orderIndex: s['order_index'] ?? 0,
        shortText: s['short_text'] ?? '',
        detailedDescription: s['detailed_description'] ?? '',
        mediaUrl: s['media_url'],
        stepIngredients: stepIngredients,
        stepEquipment: stepEquipment,
      );
    }).toList();

    return Recipe(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      mainImageUrl: json['main_image_url'] ?? '',
      sourceLink: json['source_link'] ?? '',
      prepTimeMinutes: json['prep_time_minutes'] ?? 0,
      cookTimeMinutes: json['cook_time_minutes'] ?? 0,
      basePax: json['base_pax'] ?? 4,
      cuisine: _parseCuisine(json['cuisine']),
      ingredients: ingredients,
      equipmentNeeded: equipment,
      instructions: instructions
    );
  }

  Cuisine _parseCuisine(String? val) {
    try {
      return Cuisine.values.firstWhere((e) => e.name == val?.toLowerCase());
    } catch (_) {
      return Cuisine.other;
    }
  }

}
