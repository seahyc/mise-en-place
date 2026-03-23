import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/recipe.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cuisine_tag.dart';
import '../../widgets/source_badge.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
  });

  final Recipe recipe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recipe.imageUrl != null)
              CachedNetworkImage(
                imageUrl: recipe.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(color: AppColors.darkSurface),
                ),
                errorWidget: (_, __, ___) => AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Container(
                    color: AppColors.darkSurface,
                    child: const Icon(
                      Icons.restaurant,
                      color: AppColors.darkTextTertiary,
                      size: 32,
                    ),
                  ),
                ),
              )
            else
              AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  color: AppColors.darkSurface,
                  child: const Icon(
                    Icons.restaurant,
                    color: AppColors.darkTextTertiary,
                    size: 32,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _buildMetaRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow() {
    return Row(
      children: [
        if (recipe.cuisine != null) ...[
          CuisineTag(cuisine: recipe.cuisine!),
          const SizedBox(width: 6),
        ],
        if (recipe.sourceType == 'tiktok' || recipe.sourceType == 'youtube')
          SourceBadge(
            platform: recipe.sourceType,
            creator: _extractCreator(),
          ),
      ],
    );
  }

  String _extractCreator() {
    final url = recipe.sourceUrl;
    if (url == null) return 'unknown';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'unknown';
    final segments = uri.pathSegments;
    for (final seg in segments) {
      if (seg.startsWith('@')) return seg.substring(1);
    }
    return 'imported';
  }
}
