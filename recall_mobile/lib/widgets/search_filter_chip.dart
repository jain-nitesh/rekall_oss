import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Custom filter chip widget for search filters.
///
/// Displays a filter option with:
/// - Label (e.g., "Technology")
/// - Count badge (e.g., "15")
/// - Selection state (checked/unchecked)
/// - Optional custom color for user categories
class SearchFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  const SearchFilterChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppConstants.electricIndigo;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingS,
        ),
        decoration: BoxDecoration(
          color: isSelected ? chipColor : AppConstants.softWhite,
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          border: Border.all(
            color: isSelected ? chipColor : AppConstants.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Checkmark icon when selected
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: AppConstants.spacingS),
                child: Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppConstants.white,
                ),
              ),

            // Label text
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppConstants.white
                    : AppConstants.textPrimary,
              ),
            ),

            const SizedBox(width: AppConstants.spacingS),

            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingS,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.white.withValues(alpha: 0.2)
                    : chipColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusS),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppConstants.white : chipColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
