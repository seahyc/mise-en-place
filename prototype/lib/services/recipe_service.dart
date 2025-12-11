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

  /// Create a minimal recipe entry and return its generated ID.
  /// Inserts only top-level recipe fields; ingredient/equipment steps are optional.
  Future<String?> createRecipeBasic({
    required String title,
    String description = '',
    String mainImageUrl = '',
    String sourceLink = '',
    int prepTimeMinutes = 0,
    int cookTimeMinutes = 0,
    int basePax = 1,
    String cuisine = 'other',
  }) async {
    try {
      final payload = {
        'title': title,
        'description': description,
        'main_image_url': mainImageUrl,
        'source_link': sourceLink,
        'prep_time_minutes': prepTimeMinutes,
        'cook_time_minutes': cookTimeMinutes,
        'base_pax': basePax,
        'cuisine': cuisine,
      };

      debugPrint('[RecipeService] createRecipeBasic payload=$payload');

      final response = await supabase
          .from('recipes')
          .insert(payload)
          .select('id')
          .single();

      final id = response['id']?.toString();
      debugPrint('[RecipeService] created recipe id=$id response=$response');
      if (id == null || id.isEmpty) {
        throw Exception('Supabase insert returned no id. Response: $response');
      }
      return id;
    } catch (e, st) {
      debugPrint("[RecipeService] Error creating recipe: $e\n$st");
      return null;
    }
  }

  Future<String?> createIngredientMaster({
    required String name,
    String? defaultImageUrl,
  }) async {
    try {
      final payload = {
        'name': name,
        if (defaultImageUrl != null && defaultImageUrl.isNotEmpty) 'default_image_url': defaultImageUrl,
      };
      debugPrint('[RecipeService] createIngredientMaster payload=$payload');
      final response = await supabase.from('ingredient_master').insert(payload).select('id').single();
      final id = response['id']?.toString();
      debugPrint('[RecipeService] created ingredient_master id=$id response=$response');
      if (id == null || id.isEmpty) throw Exception('No id returned for ingredient_master');
      return id;
    } catch (e, st) {
      debugPrint('[RecipeService] Error creating ingredient_master: $e\n$st');
      return null;
    }
  }

  Future<String?> createEquipmentMaster({
    required String name,
    String? iconUrl,
  }) async {
    try {
      final payload = {
        'name': name,
        if (iconUrl != null && iconUrl.isNotEmpty) 'icon_url': iconUrl,
      };
      debugPrint('[RecipeService] createEquipmentMaster payload=$payload');
      final response = await supabase.from('equipment_master').insert(payload).select('id').single();
      final id = response['id']?.toString();
      debugPrint('[RecipeService] created equipment_master id=$id response=$response');
      if (id == null || id.isEmpty) throw Exception('No id returned for equipment_master');
      return id;
    } catch (e, st) {
      debugPrint('[RecipeService] Error creating equipment_master: $e\n$st');
      return null;
    }
  }

  Future<String?> addRecipeIngredient({
    required String recipeId,
    required String ingredientMasterId,
    double? amount,
    String? unit,
    String? displayString,
    String? comment,
  }) async {
    try {
      final payload = {
        'recipe_id': recipeId,
        'ingredient_id': ingredientMasterId,
        if (amount != null) 'amount': amount,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        if (displayString != null && displayString.isNotEmpty) 'display_string': displayString,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      };
      debugPrint('[RecipeService] addRecipeIngredient payload=$payload');
      final response = await supabase.from('recipe_ingredients').insert(payload).select('id').single();
      final id = response['id']?.toString();
      debugPrint('[RecipeService] created recipe_ingredient id=$id response=$response');
      if (id == null || id.isEmpty) throw Exception('No id returned for recipe_ingredients');
      return id;
    } catch (e, st) {
      debugPrint('[RecipeService] Error adding recipe_ingredient: $e\n$st');
      return null;
    }
  }

  Future<String?> addRecipeEquipment({
    required String recipeId,
    required String equipmentMasterId,
    String? placeholderKey,
  }) async {
    try {
      final payload = {
        'recipe_id': recipeId,
        'equipment_id': equipmentMasterId,
        if (placeholderKey != null && placeholderKey.isNotEmpty) 'placeholder_key': placeholderKey,
      };
      debugPrint('[RecipeService] addRecipeEquipment payload=$payload');
      final response = await supabase.from('recipe_equipment').insert(payload).select('id').single();
      final id = response['id']?.toString();
      debugPrint('[RecipeService] created recipe_equipment id=$id response=$response');
      if (id == null || id.isEmpty) throw Exception('No id returned for recipe_equipment');
      return id;
    } catch (e, st) {
      debugPrint('[RecipeService] Error adding recipe_equipment: $e\n$st');
      return null;
    }
  }

  Future<String?> addInstructionStep({
    required String recipeId,
    required int orderIndex,
    required String shortText,
    String? detailedDescription,
    String? mediaUrl,
  }) async {
    try {
      final payload = {
        'recipe_id': recipeId,
        'order_index': orderIndex,
        'short_text': shortText,
        if (detailedDescription != null && detailedDescription.isNotEmpty) 'detailed_description': detailedDescription,
        if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
      };
      debugPrint('[RecipeService] addInstructionStep payload=$payload');
      final response = await supabase.from('instruction_steps').insert(payload).select('id').single();
      final id = response['id']?.toString();
      debugPrint('[RecipeService] created instruction_step id=$id response=$response');
      if (id == null || id.isEmpty) throw Exception('No id returned for instruction_steps');
      return id;
    } catch (e, st) {
      debugPrint('[RecipeService] Error adding instruction_step: $e\n$st');
      return null;
    }
  }
}
