import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise_en_place/models/recipe.dart';
import 'package:mise_en_place/models/user.dart';
import 'package:mise_en_place/models/session.dart';
import 'package:mise_en_place/models/job.dart';

void main() {
  group('Recipe', () {
    test('JSON round-trip', () {
      const recipe = Recipe(
        id: 'r1',
        title: 'Pasta Carbonara',
        description: 'Classic Italian pasta',
        sourceType: 'manual',
        cuisine: 'Italian',
        ingredients: ['spaghetti', 'eggs', 'pecorino', 'guanciale'],
        steps: [
          RecipeStep(orderIndex: 0, text: 'Boil water'),
          RecipeStep(orderIndex: 1, text: 'Cook pasta'),
        ],
      );

      final json = jsonDecode(jsonEncode(recipe.toJson())) as Map<String, dynamic>;
      final restored = Recipe.fromJson(json);

      expect(restored.id, 'r1');
      expect(restored.title, 'Pasta Carbonara');
      expect(restored.description, 'Classic Italian pasta');
      expect(restored.sourceType, 'manual');
      expect(restored.cuisine, 'Italian');
      expect(restored.ingredients, hasLength(4));
      expect(restored.steps, hasLength(2));
      expect(restored.steps[0].text, 'Boil water');
      expect(restored.steps[1].orderIndex, 1);
    });

    test('JSON with snake_case keys', () {
      final json = {
        'id': 'r2',
        'title': 'Test',
        'source_url': 'https://example.com',
        'source_type': 'url',
        'image_url': 'https://img.com/photo.jpg',
        'ingredients': <String>[],
        'steps': <Map<String, dynamic>>[],
      };

      final recipe = Recipe.fromJson(json);
      expect(recipe.sourceUrl, 'https://example.com');
      expect(recipe.sourceType, 'url');
      expect(recipe.imageUrl, 'https://img.com/photo.jpg');
    });

    test('defaults', () {
      const recipe = Recipe(id: 'r3', title: 'Minimal');
      expect(recipe.description, '');
      expect(recipe.sourceType, 'manual');
      expect(recipe.ingredients, isEmpty);
      expect(recipe.steps, isEmpty);
    });
  });

  group('RecipeStep', () {
    test('JSON round-trip', () {
      const step = RecipeStep(
        orderIndex: 0,
        text: 'Chop onions',
        imageUrl: 'https://img.com/step1.jpg',
      );

      final json = step.toJson();
      expect(json['order_index'], 0);
      expect(json['image_url'], 'https://img.com/step1.jpg');

      final restored = RecipeStep.fromJson(json);
      expect(restored.text, 'Chop onions');
    });
  });

  group('User', () {
    test('JSON round-trip', () {
      final json = {
        'id': 'u1',
        'email': 'test@example.com',
        'display_name': 'Test User',
      };

      final user = User.fromJson(json);
      expect(user.displayName, 'Test User');

      final output = user.toJson();
      expect(output['display_name'], 'Test User');
    });
  });

  group('TokenPair', () {
    test('JSON round-trip', () {
      final json = {
        'access_token': 'abc123',
        'refresh_token': 'def456',
        'expires_in': 3600,
      };

      final pair = TokenPair.fromJson(json);
      expect(pair.accessToken, 'abc123');
      expect(pair.refreshToken, 'def456');
      expect(pair.expiresIn, 3600);
    });
  });

  group('CookingSession', () {
    test('JSON round-trip', () {
      final json = {
        'id': 's1',
        'user_id': 'u1',
        'status': 'planning',
        'recipe_ids': ['r1', 'r2'],
        'steps': [
          {
            'id': 'st1',
            'order_index': 0,
            'text': 'Prep ingredients',
            'is_completed': false,
          }
        ],
      };

      final session = CookingSession.fromJson(json);
      expect(session.userId, 'u1');
      expect(session.recipeIds, ['r1', 'r2']);
      expect(session.steps, hasLength(1));
      expect(session.steps[0].isCompleted, false);
    });
  });

  group('Job', () {
    test('JSON round-trip', () {
      final json = {
        'id': 'j1',
        'type': 'ingest_url',
        'status': 'pending',
        'payload': {'url': 'https://example.com/recipe'},
      };

      final job = Job.fromJson(json);
      expect(job.type, 'ingest_url');
      expect(job.payload['url'], 'https://example.com/recipe');
      expect(job.result, isNull);
    });
  });
}
