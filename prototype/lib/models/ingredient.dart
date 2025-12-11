class IngredientMaster {
  final String id;
  final String name;
  final String? defaultImageUrl;
  final String? imageUrl;

  const IngredientMaster({
    required this.id,
    required this.name,
    this.defaultImageUrl,
    this.imageUrl,
  });

  factory IngredientMaster.fromJson(Map<String, dynamic> json) {
    return IngredientMaster(
      id: json['id'],
      name: json['name'],
      defaultImageUrl: json['default_image_url'],
      imageUrl: json['image_url'],
    );
  }
}

class RecipeIngredient {
  final IngredientMaster master;
  final double amount;
  final String unit; // "cloves", "g", "cup"
  final String displayString; // "2 cloves", "500ml"
  final String? comment; // "finely chopped", "room temp"

  const RecipeIngredient({
    required this.master,
    required this.amount,
    required this.unit,
    required this.displayString,
    this.comment,
  });

  // Example heuristic for scaling (very basic, ideally would use a unit library)
  RecipeIngredient scaled(double factor) {
    // This is a naive implementation.
    // real implementation would parse 'unit' and 'amount' to normalize first.
    final newAmount = amount * factor;
    // format to 1 decimal place if needed
    final formattedAmount = newAmount % 1 == 0 ? newAmount.toInt().toString() : newAmount.toStringAsFixed(1);

    return RecipeIngredient(
      master: master,
      amount: newAmount,
      unit: unit,
      displayString: "$formattedAmount $unit", // Regenerated display string
      comment: comment,
    );
  }

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      master: IngredientMaster.fromJson(json['master']),
      amount: (json['amount'] as num).toDouble(),
      unit: json['unit'],
      displayString: json['display_string'],
      comment: json['comment'],
    );
  }
}

/// Ingredient reference within an instruction step, with placeholder key for template interpolation.
/// Used in instruction templates like: "Heat {i:oil:qty} in the pan"
class StepIngredient {
  final String id;
  final IngredientMaster master;
  final double? amount;
  final String? unit;
  final String placeholderKey; // e.g., "oil", "onion", "garlic"

  const StepIngredient({
    required this.id,
    required this.master,
    this.amount,
    this.unit,
    required this.placeholderKey,
  });

  /// Formats as "amount unit name" for {i:key:qty} placeholder
  String get quantityDisplay {
    if (amount == null || unit == null) return master.name;
    final formattedAmount = amount! % 1 == 0
        ? amount!.toInt().toString()
        : amount!.toStringAsFixed(1);
    return '$formattedAmount $unit ${master.name}';
  }

  /// Returns scaled copy
  StepIngredient scaled(double factor) {
    return StepIngredient(
      id: id,
      master: master,
      amount: amount != null ? amount! * factor : null,
      unit: unit,
      placeholderKey: placeholderKey,
    );
  }

  factory StepIngredient.fromJson(Map<String, dynamic> json) {
    return StepIngredient(
      id: json['id'] ?? '',
      master: IngredientMaster.fromJson(json['ingredient_master'] ?? json['master'] ?? {}),
      amount: (json['amount'] as num?)?.toDouble(),
      unit: json['unit_master']?['abbreviation'] ?? json['unit_master']?['name'] ?? json['unit'],
      placeholderKey: json['placeholder_key'] ?? '',
    );
  }
}
