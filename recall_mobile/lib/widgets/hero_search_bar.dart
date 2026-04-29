import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Hero-animated search bar for premium search experience
class HeroSearchBar extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isCollapsed;

  const HeroSearchBar({
    super.key,
    this.onTap,
    this.isCollapsed = true,
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'search_bar',
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCollapsed ? AppConstants.spacingM : 0,
            vertical: isCollapsed ? AppConstants.spacingS : 0,
          ),
          decoration: BoxDecoration(
            color: AppConstants.white,
            borderRadius: BorderRadius.circular(
              isCollapsed ? AppConstants.radiusL : 0,
            ),
            border: Border.all(
              color: AppConstants.borderColor,
              width: AppConstants.borderWidthThin,
            ),
            boxShadow: isCollapsed
                ? []
                : [
                    BoxShadow(
                      color: AppConstants.deepCharcoal.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: InkWell(
            onTap: isCollapsed ? onTap : null,
            borderRadius: BorderRadius.circular(
              isCollapsed ? AppConstants.radiusL : 0,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingM,
                vertical: AppConstants.spacingM,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    color: AppConstants.textSecondary,
                    size: isCollapsed ? 20 : 24,
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Text(
                    'Search your saved content...',
                    style: TextStyle(
                      fontSize: isCollapsed ? 14 : 16,
                      color: AppConstants.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
