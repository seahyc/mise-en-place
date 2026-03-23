import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/frosted_glass.dart';

/// Frosted ingredient panel anchored at the bottom-left of the image side.
///
/// Parses ingredient strings to extract emoji, amount, and name.
/// Format: "emoji amount name" (e.g., "🥚 2 eggs, beaten").
/// Falls back to 🥘 if no emoji prefix is detected.
class IngredientPanel extends StatelessWidget {
  const IngredientPanel({super.key, required this.ingredients});

  final List<String> ingredients;

  @override
  Widget build(BuildContext context) {
    if (ingredients.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: FrostedGlass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 10,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: ingredients
              .map((ingredient) => _IngredientRow(text: ingredient))
              .toList(),
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final parsed = _parseIngredient(text);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(parsed.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          if (parsed.amount.isNotEmpty)
            Text(
              parsed.amount,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.amber,
              ),
            ),
          if (parsed.amount.isNotEmpty) const SizedBox(width: 5),
          Flexible(
            child: Text(
              parsed.name,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0x99FFFFFF), // rgba(255,255,255,0.6)
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ingredient Parsing ────────────────────────────────────────────────────────

class _ParsedIngredient {
  const _ParsedIngredient(this.emoji, this.amount, this.name);
  final String emoji;
  final String amount;
  final String name;
}

_ParsedIngredient _parseIngredient(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const _ParsedIngredient('\u{1F958}', '', ''); // 🥘
  }

  String emoji;
  String rest;

  // Check if the first character is an emoji (codepoint > 0x1F000)
  final firstRune = trimmed.runes.first;
  if (firstRune > 0x1F000) {
    // Simple approach: take chars until we hit a space
    final spaceIdx = trimmed.indexOf(' ');
    if (spaceIdx > 0) {
      emoji = trimmed.substring(0, spaceIdx);
      rest = trimmed.substring(spaceIdx + 1).trim();
    } else {
      emoji = trimmed;
      rest = '';
    }
  } else {
    emoji = '\u{1F958}'; // 🥘
    rest = trimmed;
  }

  // Parse amount and name from rest
  // Amount is leading numeric/fraction text: "2 tbsp", "400ml", "1/2 cup"
  final amountMatch = RegExp(r'^([\d/½¼¾⅓⅔]+\s*(?:tbsp|tsp|cup|cups|ml|g|kg|oz|lb|lbs|cloves?|stalks?|heads?|bunche?s?|slices?|pieces?|cans?)?)\s+(.+)$', caseSensitive: false).firstMatch(rest);
  if (amountMatch != null) {
    return _ParsedIngredient(emoji, amountMatch.group(1)!, amountMatch.group(2)!);
  }

  // Try simpler: just a number at the start
  final simpleNum = RegExp(r'^([\d/½¼¾⅓⅔]+)\s+(.+)$').firstMatch(rest);
  if (simpleNum != null) {
    return _ParsedIngredient(emoji, simpleNum.group(1)!, simpleNum.group(2)!);
  }

  // No amount parseable
  return _ParsedIngredient(emoji, '', rest);
}
