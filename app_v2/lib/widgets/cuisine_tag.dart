import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Small pill widget: flag emoji + cuisine name.
class CuisineTag extends StatelessWidget {
  const CuisineTag({
    super.key,
    required this.cuisine,
    this.flagEmoji,
  });

  final String cuisine;
  final String? flagEmoji;

  static const _cuisineFlags = <String, String>{
    'thai': '\u{1F1F9}\u{1F1ED}',
    'mexican': '\u{1F1F2}\u{1F1FD}',
    'italian': '\u{1F1EE}\u{1F1F9}',
    'japanese': '\u{1F1EF}\u{1F1F5}',
    'chinese': '\u{1F1E8}\u{1F1F3}',
    'indian': '\u{1F1EE}\u{1F1F3}',
    'french': '\u{1F1EB}\u{1F1F7}',
    'korean': '\u{1F1F0}\u{1F1F7}',
    'vietnamese': '\u{1F1FB}\u{1F1F3}',
    'american': '\u{1F1FA}\u{1F1F8}',
    'greek': '\u{1F1EC}\u{1F1F7}',
    'spanish': '\u{1F1EA}\u{1F1F8}',
    'turkish': '\u{1F1F9}\u{1F1F7}',
    'ethiopian': '\u{1F1EA}\u{1F1F9}',
    'brazilian': '\u{1F1E7}\u{1F1F7}',
  };

  String get _flag {
    if (flagEmoji != null) return flagEmoji!;
    return _cuisineFlags[cuisine.toLowerCase()] ?? '\u{1F3F3}\u{FE0F}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        '$_flag $cuisine',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.amber,
        ),
      ),
    );
  }
}
