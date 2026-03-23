import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Badge showing platform icon + @creator for imported recipes.
class SourceBadge extends StatelessWidget {
  const SourceBadge({
    super.key,
    required this.platform,
    required this.creator,
  });

  final String platform;
  final String creator;

  IconData get _platformIcon {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return Icons.music_note;
      case 'youtube':
        return Icons.play_circle_fill;
      case 'instagram':
        return Icons.camera_alt;
      default:
        return Icons.link;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.darkTextTertiary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            _platformIcon,
            size: 12,
            color: AppColors.darkTextTertiary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '@$creator',
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.darkTextTertiary,
          ),
        ),
      ],
    );
  }
}
