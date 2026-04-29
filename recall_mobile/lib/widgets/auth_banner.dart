import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/content_item.dart';

class AuthBanner extends StatelessWidget {
  final FetchErrorType errorType;

  const AuthBanner({
    super.key,
    required this.errorType,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine icon, color, and message based on error type
    IconData icon;
    Color accentColor;
    String title;
    String subtitle;

    switch (errorType) {
      case FetchErrorType.authRequired:
        icon = Icons.lock_outline;
        accentColor = Colors.amber.shade600;
        title = 'Authentication Required';
        subtitle =
            'This content requires login. Showing AI summary from your shared content.';
        break;
      case FetchErrorType.blocked:
        icon = Icons.block;
        accentColor = Colors.orange;
        title = 'Access Blocked';
        subtitle =
            'Unable to access content (rate limited or blocked). Showing AI summary from your shared content.';
        break;
      default:
        // Don't show banner for other error types
        return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
