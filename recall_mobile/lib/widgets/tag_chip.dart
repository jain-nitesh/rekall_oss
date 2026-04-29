import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Chip widget for displaying tags
class TagChip extends StatelessWidget {
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  final bool small;

  const TagChip({
    super.key,
    required this.label,
    this.color,
    this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppConstants.secondaryColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? AppConstants.spacingS : AppConstants.spacingM,
          vertical: small ? AppConstants.spacingXS : AppConstants.spacingS,
        ),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          border: Border.all(
            color: chipColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: chipColor,
            fontSize: small ? 11 : 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
