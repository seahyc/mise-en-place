import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/models/ingredient.dart';

void main() {
  test('RecipeIngredient.scaled multiplies and formats amounts', () {
    const ingredient = RecipeIngredient(
      master: IngredientMaster(id: '1', name: 'Onion'),
      amount: 1.5,
      unit: 'cup',
      displayString: '1.5 cup',
      comment: 'diced',
    );

    final scaled = ingredient.scaled(2);

    expect(scaled.amount, 3);
    expect(scaled.displayString, '3 cup');
    expect(scaled.comment, 'diced');
    expect(scaled.master.name, 'Onion');
  });
}
