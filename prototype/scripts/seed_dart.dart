// ignore_for_file: avoid_print
import 'package:supabase/supabase.dart';

// HARDCODED CREDENTIALS for Seeding Script
const supabaseUrl = 'https://dmhhglsaeqxzwtjaqtdo.supabase.co';
const supabaseKey = 'SPkg09h9subx1aUY'; 

final supabase = SupabaseClient(supabaseUrl, supabaseKey);

Future<void> main() async {
  print('Seeding data via Supabase API (Full 6 Recipes)...');

  // 1. Clean
  print('Cleaning old data...');
  try {
     // Order matters for FKs if cascading isn't set, but API might fail. 
     // We will try deleting children first.
     await supabase.from('recipe_ingredients').delete().neq('id', 0);
     await supabase.from('recipe_equipment').delete().neq('id', 0);
     await supabase.from('instruction_steps').delete().neq('id', 'x');
     await supabase.from('recipes').delete().neq('id', 'x');
     await supabase.from('ingredient_master').delete().neq('id', 'x');
     await supabase.from('equipment_master').delete().neq('id', 'x');
  } catch (e) {
     print('Cleanup warning: $e');
  }

  // 2. Masters
  print('Inserting Masters...');
  
  final ingredients = [
    // Risotto
    {'id': 'ing_rice', 'name': 'Arborio Rice'}, {'id': 'ing_mushrooms', 'name': 'Mixed Mushrooms'}, 
    {'id': 'ing_stock', 'name': 'Vegetable Stock'}, {'id': 'ing_onion', 'name': 'Onion'},
    {'id': 'ing_garlic', 'name': 'Garlic'}, {'id': 'ing_wine', 'name': 'White Wine'}, 
    {'id': 'ing_yeast', 'name': 'Nutritional Yeast'}, {'id': 'ing_butter_v', 'name': 'Vegan Butter'},
    {'id': 'ing_parsley', 'name': 'Parsley'}, {'id': 'ing_oil', 'name': 'Olive Oil'},
    {'id': 'ing_salt', 'name': 'Salt'}, {'id': 'ing_pepper', 'name': 'Black Pepper'},
    
    // Quinoa Salad
    {'id': 'ing_sweet_potato', 'name': 'Sweet Potato'}, {'id': 'ing_quinoa', 'name': 'Quinoa'},
    {'id': 'ing_avo', 'name': 'Avocado'}, {'id': 'ing_black_beans', 'name': 'Black Beans'},
    {'id': 'ing_pepitas', 'name': 'Pumpkin Seeds'}, {'id': 'ing_spinach', 'name': 'Baby Spinach'},
    {'id': 'ing_maple', 'name': 'Maple Syrup'}, {'id': 'ing_lemon', 'name': 'Lemon Juice'},
    {'id': 'ing_cumin', 'name': 'Cumin'},
    
    // Pad Thai
    {'id': 'ing_noodles', 'name': 'Rice Noodles'}, {'id': 'ing_tofu', 'name': 'Firm Tofu'},
    {'id': 'ing_egg', 'name': 'Eggs'}, {'id': 'ing_sprouts', 'name': 'Bean Sprouts'},
    {'id': 'ing_peanuts', 'name': 'Roasted Peanuts'}, {'id': 'ing_scallion', 'name': 'Green Onions'},
    {'id': 'ing_tamarind', 'name': 'Tamarind Paste'}, {'id': 'ing_fish_sauce', 'name': 'Fish Sauce'},
    {'id': 'ing_chili_flakes', 'name': 'Chili Flakes'}, {'id': 'ing_lime', 'name': 'Lime'},
    
    // Green Curry
    {'id': 'ing_chicken_thigh', 'name': 'Chicken Thighs'}, {'id': 'ing_green_curry', 'name': 'Green Curry Paste'},
    {'id': 'ing_coconut_milk', 'name': 'Coconut Milk'}, {'id': 'ing_bamboo', 'name': 'Bamboo Shoots'},
    {'id': 'ing_red_pepper', 'name': 'Red Bell Pepper'}, {'id': 'ing_kaffir', 'name': 'Kaffir Lime Leaves'},
    {'id': 'ing_basil', 'name': 'Thai Basil'}, {'id': 'ing_sugar', 'name': 'Palm Sugar'},
    
    // Tacos
    {'id': 'ing_pork', 'name': 'Pork Shoulder'}, {'id': 'ing_achiote', 'name': 'Achiote Paste'},
    {'id': 'ing_pineapple_juice', 'name': 'Pineapple Juice'}, {'id': 'ing_vinegar', 'name': 'Vinegar'},
    {'id': 'ing_oregano', 'name': 'Oregano'}, {'id': 'ing_pineapple', 'name': 'Pineapple'},
    {'id': 'ing_tortilla_corn', 'name': 'Corn Tortillas'}, {'id': 'ing_cilantro', 'name': 'Cilantro'},
    
    // Enchiladas
    {'id': 'ing_chicken_cooked', 'name': 'Cooked Chicken'}, {'id': 'ing_cheese', 'name': 'Cheddar Cheese'},
    {'id': 'ing_tortilla_flour', 'name': 'Flour Tortillas'}, {'id': 'ing_passata', 'name': 'Tomato Passata'},
    {'id': 'ing_chili_powder', 'name': 'Chili Powder'}, {'id': 'ing_garlic_powder', 'name': 'Garlic Powder'},
    {'id': 'ing_sour_cream', 'name': 'Sour Cream'}, {'id': 'i_bread', 'name': 'Sourdough Bread'},
  ];
  await supabase.from('ingredient_master').upsert(ingredients);

  final equipment = [
    {'id': 'eq_pot', 'name': 'Large Pot'}, {'id': 'eq_pan', 'name': 'Frying Pan'},
    {'id': 'eq_knife', 'name': 'Knife'}, {'id': 'eq_board', 'name': 'Cutting Board'},
    {'id': 'eq_ladle', 'name': 'Ladle'}, {'id': 'eq_whisk', 'name': 'Whisk'},
    {'id': 'eq_baking_sheet', 'name': 'Baking Sheet'}, {'id': 'eq_bowl', 'name': 'Mixing Bowl'},
    {'id': 'eq_wok', 'name': 'Wok'}, {'id': 'eq_tongs', 'name': 'Tongs'},
    {'id': 'eq_blender', 'name': 'Blender'}, {'id': 'eq_baking_dish', 'name': 'Baking Dish'},
    {'id': 'eq_oven', 'name': 'Oven'}
  ];
  await supabase.from('equipment_master').upsert(equipment);

  // 3. Recipes & Logic
  final recipes = [
    {
       'id': 'recipe_001', 'title': 'Creamy Mushroom Risotto', 'description': 'Rich and creamy vegan risotto.',
       'main_image_url': 'https://images.unsplash.com/photo-1476124369491-e7addf5db371',
       'prep_time_minutes': 15, 'cook_time_minutes': 40, 'cuisine': 'vegan'
    },
    {
       'id': 'recipe_002', 'title': 'Quinoa Power Salad', 'description': 'Roasted sweet potato and black bean salad.',
       'main_image_url': 'https://images.unsplash.com/photo-1543339308-43e59d6b73a6',
       'prep_time_minutes': 15, 'cook_time_minutes': 25, 'cuisine': 'vegan'
    },
    {
       'id': 'recipe_003', 'title': 'Classic Pad Thai', 'description': 'Stir-fried noodles with tofu.',
       'main_image_url': 'https://images.unsplash.com/photo-1559314809-0d155014e29e',
       'prep_time_minutes': 20, 'cook_time_minutes': 10, 'cuisine': 'thai'
    },
    {
       'id': 'recipe_004', 'title': 'Thai Green Curry', 'description': 'Spicy coconut curry with chicken.',
       'main_image_url': 'https://images.unsplash.com/photo-1626804475297-411db7438133',
       'prep_time_minutes': 20, 'cook_time_minutes': 20, 'cuisine': 'thai'
    },
    {
       'id': 'recipe_005', 'title': 'Tacos al Pastor', 'description': 'Marinated pork with pineapple.',
       'main_image_url': 'https://images.unsplash.com/photo-1551504734-5ee1c4a1479b',
       'prep_time_minutes': 30, 'cook_time_minutes': 15, 'cuisine': 'mexican'
    },
    {
       'id': 'recipe_006', 'title': 'Chicken Enchiladas', 'description': 'Baked tortillas with red sauce.',
       'main_image_url': 'https://images.unsplash.com/photo-1534352956036-c01ac18bd982',
       'prep_time_minutes': 20, 'cook_time_minutes': 25, 'cuisine': 'mexican'
    }
  ];
  await supabase.from('recipes').upsert(recipes);

  // Ingredients and Steps Mapping
  // (Simplified helpers to avoid 500 lines of code in one file, but covering all key data points)
  
  await _addRecipeData(
      'recipe_001', 
      [
        {'ingredient_id': 'ing_rice', 'amount': 300, 'unit': 'g', 'display_string': '300g Rice'},
        {'ingredient_id': 'ing_mushrooms', 'amount': 400, 'unit': 'g', 'display_string': '400g Mushrooms'},
        {'ingredient_id': 'ing_stock', 'amount': 1.2, 'unit': 'L', 'display_string': '1.2L Stock'},
        {'ingredient_id': 'ing_wine', 'amount': 120, 'unit': 'ml', 'display_string': '120ml Wine'},
      ],
      [
        {'order_index': 0, 'short_text': 'Prep', 'detailed_description': 'Chop veg and heat stock.'},
        {'order_index': 1, 'short_text': 'Sauté', 'detailed_description': 'Cook base.'},
        {'order_index': 2, 'short_text': 'Rice', 'detailed_description': 'Toast rice.'},
        {'order_index': 3, 'short_text': 'Simmer', 'detailed_description': 'Add stock slowly.'},
      ]
  );
  
  await _addRecipeData(
      'recipe_002', 
      [
        {'ingredient_id': 'ing_sweet_potato', 'amount': 1, 'unit': 'piece', 'display_string': '1 Sweet Potato'},
        {'ingredient_id': 'ing_quinoa', 'amount': 150, 'unit': 'g', 'display_string': '150g Quinoa'},
        {'ingredient_id': 'ing_avo', 'amount': 1, 'unit': 'piece', 'display_string': '1 Avocado'},
      ],
      [
        {'order_index': 0, 'short_text': 'Roast', 'detailed_description': 'Roast potato 200C.'},
        {'order_index': 1, 'short_text': 'Boil', 'detailed_description': 'Cook quinoa.'},
        {'order_index': 2, 'short_text': 'Mix', 'detailed_description': 'Combine all.'},
      ]
  );
  
  await _addRecipeData(
      'recipe_003', // Pad Thai
      [
        {'ingredient_id': 'ing_noodles', 'amount': 200, 'unit': 'g', 'display_string': '200g Rice Noodles'},
        {'ingredient_id': 'ing_tofu', 'amount': 150, 'unit': 'g', 'display_string': '150g Tofu'},
        {'ingredient_id': 'ing_tamarind', 'amount': 3, 'unit': 'tbsp', 'display_string': '3 tbsp Tamarind'},
      ],
      [
        {'order_index': 0, 'short_text': 'Soak', 'detailed_description': 'Soak noodles.'},
        {'order_index': 1, 'short_text': 'Fry', 'detailed_description': 'Fry tofu and eggs.'},
        {'order_index': 2, 'short_text': 'Toss', 'detailed_description': 'Add noodles and sauce.'},
      ]
  );

  await _addRecipeData(
      'recipe_004', // Green Curry
      [
        {'ingredient_id': 'ing_chicken_thigh', 'amount': 400, 'unit': 'g', 'display_string': '400g Chicken'},
        {'ingredient_id': 'ing_green_curry', 'amount': 4, 'unit': 'tbsp', 'display_string': '4 tbsp Paste'},
        {'ingredient_id': 'ing_coconut_milk', 'amount': 400, 'unit': 'ml', 'display_string': '400ml Coconut Milk'},
      ],
      [
        {'order_index': 0, 'short_text': 'Fry Paste', 'detailed_description': 'Fry paste in oil.'},
        {'order_index': 1, 'short_text': 'Meat', 'detailed_description': 'Add chicken.'},
        {'order_index': 2, 'short_text': 'Simmer', 'detailed_description': 'Add liquid and veg.'},
      ]
  );

  await _addRecipeData(
      'recipe_005', // Tacos
      [
         {'ingredient_id': 'ing_pork', 'amount': 500, 'unit': 'g', 'display_string': '500g Pork'},
         {'ingredient_id': 'ing_achiote', 'amount': 3, 'unit': 'tbsp', 'display_string': '3 tbsp Achiote'},
         {'ingredient_id': 'ing_pineapple', 'amount': 0.25, 'unit': 'piece', 'display_string': '1/4 Pineapple'},
         {'ingredient_id': 'ing_tortilla_corn', 'amount': 12, 'unit': 'piece', 'display_string': '12 Tortillas'},
      ],
      [
         {'order_index': 0, 'short_text': 'Marinate', 'detailed_description': 'Marinade pork 1hr.'},
         {'order_index': 1, 'short_text': 'Cook', 'detailed_description': 'Sear pork.'},
         {'order_index': 2, 'short_text': 'Serve', 'detailed_description': 'Assemble atop tortillas.'},
      ]
  );

  await _addRecipeData(
      'recipe_006', // Enchiladas
      [
         {'ingredient_id': 'ing_chicken_cooked', 'amount': 300, 'unit': 'g', 'display_string': '300g Chicken'},
         {'ingredient_id': 'ing_cheese', 'amount': 200, 'unit': 'g', 'display_string': '200g Cheese'},
         {'ingredient_id': 'ing_passata', 'amount': 400, 'unit': 'ml', 'display_string': '400ml Passata'},
      ],
      [
         {'order_index': 0, 'short_text': 'Filling', 'detailed_description': 'Mix chicken and cheese.'},
         {'order_index': 1, 'short_text': 'Roll', 'detailed_description': 'Roll into tortillas.'},
         {'order_index': 2, 'short_text': 'Bake', 'detailed_description': 'Bake with sauce.'},
      ]
  );


  print('Fully Seeded!');
}

Future<void> _addRecipeData(String recipeId, List<Map<String, dynamic>> ingredients, List<Map<String, dynamic>> steps) async {
  for (var i in ingredients) {
    await supabase.from('recipe_ingredients').insert({
      'recipe_id': recipeId,
      'ingredient_id': i['ingredient_id'],
      'amount': i['amount'],
      'unit': i['unit'],
      'display_string': i['display_string']
    });
  }
  for (var s in steps) {
    await supabase.from('instruction_steps').insert({
       'id': '${recipeId}_s${s['order_index']}',
       'recipe_id': recipeId,
       'order_index': s['order_index'],
       'short_text': s['short_text'],
       'detailed_description': s['detailed_description']
    });
  }
}
