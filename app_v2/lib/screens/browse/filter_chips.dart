import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class FilterChipData {
  const FilterChipData({
    required this.label,
    this.emoji,
    this.isActive = false,
  });

  final String label;
  final String? emoji;
  final bool isActive;
}

class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({
    super.key,
    required this.chips,
    required this.onChipTapped,
  });

  final List<FilterChipData> chips;
  final ValueChanged<int> onChipTapped;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          return GestureDetector(
            onTap: () => onChipTapped(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: chip.isActive
                    ? AppColors.amber
                    : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(18),
                border: chip.isActive
                    ? null
                    : Border.all(color: AppColors.darkBorder),
              ),
              child: Text(
                chip.emoji != null ? '${chip.emoji} ${chip.label}' : chip.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: chip.isActive ? Colors.black : Colors.white,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
