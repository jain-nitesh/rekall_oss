import 'package:flutter/material.dart';
import '../models/content_item.dart';
import '../utils/constants.dart';

/// Icon widget for displaying source app with color and icon
class SourceAppIcon extends StatelessWidget {
  final SourceApp sourceApp;
  final double size;
  final bool showBackground;

  const SourceAppIcon({
    super.key,
    required this.sourceApp,
    this.size = 24.0,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppConstants.sourceAppColors[sourceApp] ?? AppConstants.sourceAppColors[SourceApp.other]!;
    final icon = AppConstants.sourceAppIcons[sourceApp] ?? AppConstants.sourceAppIcons[SourceApp.other]!;

    if (showBackground) {
      return Container(
        width: size + 8,
        height: size + 8,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
        ),
        child: Icon(
          icon,
          size: size * 0.7,
          color: color,
        ),
      );
    } else {
      return Icon(
        icon,
        size: size,
        color: color,
      );
    }
  }
}
