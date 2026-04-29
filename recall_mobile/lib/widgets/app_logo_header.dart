import 'package:flutter/material.dart';
import '../models/user.dart';
import '../utils/constants.dart';

/// Reusable app logo header with user avatar and "ReKall" text
/// Used consistently across all screen AppBars
class AppLogoHeader extends StatelessWidget {
  final User? currentUser;

  const AppLogoHeader({
    super.key,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildAvatar(context),
        const SizedBox(width: AppConstants.spacingM),
        Text(
          'ReKall',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppConstants.starlight
                : AppConstants.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final hasAvatarUrl = currentUser != null &&
                         currentUser!.avatarUrl != null &&
                         currentUser!.avatarUrl!.isNotEmpty;
    final initial = currentUser?.name.substring(0, 1).toUpperCase() ?? 'U';

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
          width: 2,
        ),
        gradient: const LinearGradient(
          colors: [
            AppConstants.primaryBlueCyan,
            AppConstants.synapseIndigo,
          ],
        ),
      ),
      child: hasAvatarUrl
          ? ClipOval(
              child: Image.network(
                currentUser!.avatarUrl!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
