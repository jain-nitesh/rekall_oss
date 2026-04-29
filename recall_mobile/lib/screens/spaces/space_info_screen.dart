import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/shared_space.dart';
import '../../providers/spaces_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';

class SpaceInfoScreen extends ConsumerWidget {
  final String spaceId;

  const SpaceInfoScreen({
    super.key,
    required this.spaceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref.watch(spaceByIdProvider(spaceId));
    final currentUser = ref.watch(currentUserProvider);

    if (space == null) {
      return Scaffold(
        appBar: PremiumAppBar.glassmorphic(
          title: 'Loading...',
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: PremiumAppBar.glassmorphic(
        title: space.name,
        actions: [
          if (space.canUpdateSpace)
            PremiumIconButton(
              icon: Icons.edit,
              tooltip: 'Edit Space',
              onPressed: () {
                AppHaptics.buttonPress();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edit space feature coming soon')),
                );
              },
            ),
          const SizedBox(width: AppConstants.spacingS),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDescriptionSection(space),
            const Divider(),
            _buildMembersSection(context, ref, space, currentUser),
            const Divider(),
            _buildInviteSection(context, ref, space),
            const SizedBox(height: AppConstants.spacingXL),
            if (space.canDeleteSpace)
              _buildDangerZone(context, ref, spaceId, space.name),
            const SizedBox(height: AppConstants.spacingXXL),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection(SharedSpace space) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Description',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppConstants.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              border: Border.all(
                color: AppConstants.borderColor,
                width: AppConstants.borderWidthThin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  space.description,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: AppConstants.textPrimary,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                Row(
                  children: [
                    _buildStatChip(
                      icon: Icons.people,
                      label: '${space.memberCount} Members',
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    _buildStatChip(
                      icon: Icons.bookmark,
                      label: '${space.contentCount} Items',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection(
    BuildContext context,
    WidgetRef ref,
    SharedSpace space,
    currentUser,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Members',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppConstants.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(width: AppConstants.spacingS),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingS,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusL),
                ),
                child: Text(
                  '${space.members.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingM),
          ...space.members.map((member) {
            final canRemove = space.canRemoveMembers &&
                            member.role != SpaceMemberRole.owner &&
                            member.userId != currentUser?.id;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: AppConstants.primaryGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        member.name[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppConstants.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member.email,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppConstants.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  GestureDetector(
                    onTap: space.currentUserRole == SpaceMemberRole.owner &&
                            member.role != SpaceMemberRole.owner &&
                            member.userId != currentUser?.id
                        ? () {
                            AppHaptics.light();
                            _showRoleSelectionDialog(
                              context,
                              ref,
                              spaceId,
                              member.userId,
                              member.name,
                              member.role,
                            );
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingS,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppConstants.primaryColor.withValues(alpha: 0.15),
                            AppConstants.primaryColor.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(AppConstants.radiusM),
                        border: Border.all(
                          color: AppConstants.primaryColor.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            member.role.displayName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppConstants.primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (space.currentUserRole == SpaceMemberRole.owner &&
                              member.role != SpaceMemberRole.owner &&
                              member.userId != currentUser?.id) ...[
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: AppConstants.primaryColor,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (canRemove) ...[
                    const SizedBox(width: AppConstants.spacingS),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        size: 20,
                        color: AppConstants.errorColor,
                      ),
                      onPressed: () {
                        AppHaptics.warning();
                        _removeMember(
                          context,
                          ref,
                          spaceId,
                          member.userId,
                          member.name,
                        );
                      },
                      tooltip: 'Remove member',
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInviteSection(BuildContext context, WidgetRef ref, SharedSpace space) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invite Link',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppConstants.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppConstants.surfaceColor,
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              border: Border.all(
                color: AppConstants.borderColor,
                width: AppConstants.borderWidthThin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.link,
                      size: 20,
                      color: AppConstants.textSecondary,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Expanded(
                      child: Text(
                        '${AppConstants.appDeepLinkUrl}/invite/${space.inviteToken}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppConstants.textPrimary,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingM),
                Row(
                  children: [
                    Expanded(
                      child: PremiumButton.secondary(
                        onPressed: () {
                          AppHaptics.buttonPress();
                          _copyInviteLink(context, space.inviteToken);
                        },
                        fullWidth: true,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.copy, size: 18),
                            SizedBox(width: AppConstants.spacingS),
                            Text('Copy'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Expanded(
                      child: PremiumButton.secondary(
                        onPressed: () {
                          AppHaptics.buttonPress();
                          _shareInviteLink(context, ref, space);
                        },
                        fullWidth: true,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share, size: 18),
                            SizedBox(width: AppConstants.spacingS),
                            Text('Share'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (space.canInviteMembers) ...[
                  const SizedBox(height: AppConstants.spacingS),
                  PremiumButton(
                    onPressed: () {
                      AppHaptics.warning();
                      _confirmRegenerateInviteLink(context, ref, space);
                    },
                    backgroundColor: AppConstants.errorColor.withValues(alpha: 0.1),
                    foregroundColor: AppConstants.errorColor,
                    fullWidth: true,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.refresh, size: 18),
                        SizedBox(width: AppConstants.spacingS),
                        Text('Regenerate Link'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone(
    BuildContext context,
    WidgetRef ref,
    String spaceId,
    String spaceName,
  ) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Danger Zone',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppConstants.errorColor,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            decoration: BoxDecoration(
              color: AppConstants.errorColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
              border: Border.all(
                color: AppConstants.errorColor.withValues(alpha: 0.3),
                width: AppConstants.borderWidthThin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_outlined,
                      color: AppConstants.errorColor,
                      size: 20,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Expanded(
                      child: const Text(
                        'Deleting a space is permanent and cannot be undone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppConstants.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingM),
                PremiumButton(
                  onPressed: () {
                    AppHaptics.warning();
                    _deleteSpace(context, ref, spaceId, spaceName);
                  },
                  backgroundColor: AppConstants.errorColor,
                  foregroundColor: AppConstants.white,
                  fullWidth: true,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_forever, size: 20),
                      SizedBox(width: AppConstants.spacingS),
                      Text('Delete Space'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
        vertical: AppConstants.spacingS,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: AppConstants.dividerColor,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppConstants.textSecondary),
          const SizedBox(width: AppConstants.spacingS),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _copyInviteLink(BuildContext context, String token) {
    Clipboard.setData(ClipboardData(text: '${AppConstants.appDeepLinkUrl}/invite/$token'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied to clipboard')),
    );
  }

  void _removeMember(
    BuildContext context,
    WidgetRef ref,
    String spaceId,
    String userId,
    String userName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $userName from this space?'),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              AppHaptics.heavy();
              final success = await ref
                  .read(spacesProvider.notifier)
                  .removeMember(spaceId, userId);
              if (context.mounted) {
                Navigator.of(context).pop();
                if (success) {
                  AppHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$userName removed from space'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                } else {
                  AppHaptics.error();
                  final errorMessage = ref.read(spacesProvider).errorMessage ??
                      'Failed to remove member';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _deleteSpace(
    BuildContext context,
    WidgetRef ref,
    String spaceId,
    String spaceName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Space'),
        content: Text(
          'Are you sure you want to delete "$spaceName"?\n\nThis action cannot be undone and will remove all content associations.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              AppHaptics.heavy();

              // Capture outer (page-level) scaffold context before closing dialog
              final outerContext = Navigator.of(context, rootNavigator: true).context;
              final scaffoldMessenger = ScaffoldMessenger.of(context);

              final success = await ref.read(spacesProvider.notifier).deleteSpace(spaceId);

              // Close dialog first
              if (context.mounted) {
                Navigator.of(context).pop();
              }

              if (success) {
                AppHaptics.success();
                // Use rootNavigator context for go_router navigation after dialog is closed
                if (outerContext.mounted) {
                  GoRouter.of(outerContext).go('/spaces');
                }
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Space deleted successfully'),
                    backgroundColor: AppConstants.successColor,
                  ),
                );
              } else {
                AppHaptics.error();
                final errorMessage = ref.read(spacesProvider).errorMessage ??
                    'Failed to delete space';
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(errorMessage),
                    backgroundColor: AppConstants.errorColor,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRoleSelectionDialog(
    BuildContext context,
    WidgetRef ref,
    String spaceId,
    String userId,
    String userName,
    SpaceMemberRole currentRole,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change role for $userName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRoleOption(
              context,
              ref,
              spaceId,
              userId,
              userName,
              SpaceMemberRole.viewer,
              currentRole,
              'Viewer',
              'Read-only access to space content',
            ),
            const SizedBox(height: AppConstants.spacingS),
            _buildRoleOption(
              context,
              ref,
              spaceId,
              userId,
              userName,
              SpaceMemberRole.member,
              currentRole,
              'Member',
              'Can view and add content to space',
            ),
            const SizedBox(height: AppConstants.spacingS),
            _buildRoleOption(
              context,
              ref,
              spaceId,
              userId,
              userName,
              SpaceMemberRole.admin,
              currentRole,
              'Admin',
              'Can manage members and content',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleOption(
    BuildContext context,
    WidgetRef ref,
    String spaceId,
    String userId,
    String userName,
    SpaceMemberRole role,
    SpaceMemberRole currentRole,
    String title,
    String description,
  ) {
    final isSelected = role == currentRole;

    return InkWell(
      onTap: isSelected
          ? null
          : () async {
              AppHaptics.light();
              Navigator.of(context).pop(); // Close dialog first

              final success = await ref
                  .read(spacesProvider.notifier)
                  .updateMemberRole(spaceId, userId, role.name);

              if (context.mounted) {
                if (success) {
                  AppHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$userName promoted to ${role.displayName}'),
                      backgroundColor: AppConstants.successColor,
                    ),
                  );
                } else {
                  AppHaptics.error();
                  final errorMessage = ref.read(spacesProvider).errorMessage ??
                      'Failed to update role';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: AppConstants.errorColor,
                    ),
                  );
                }
              }
            },
      borderRadius: BorderRadius.circular(AppConstants.radiusM),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingM),
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          border: Border.all(
            color: isSelected
                ? AppConstants.primaryColor
                : AppConstants.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppConstants.primaryColor
                          : AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppConstants.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppConstants.primaryColor,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareInviteLink(BuildContext context, WidgetRef ref, SharedSpace space) async {
    try {
      // Get current user name
      final currentUser = ref.read(currentUserProvider);
      final userName = currentUser?.name ?? 'Someone';

      // Build custom message template
      final message = '$userName is inviting you to join ${space.name} on ReKall\n\n'
                      'Click the link below to join:\n'
                      '${AppConstants.appDeepLinkUrl}/invite/${space.inviteToken}';

      // Trigger native share sheet
      await SharePlus.instance.share(
        ShareParams(
          text: message,
          subject: 'Join ${space.name} on ReKall',
        ),
      );

      AppHaptics.success();
    } catch (e) {
      AppHaptics.error();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to share invite link'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _confirmRegenerateInviteLink(BuildContext context, WidgetRef ref, SharedSpace space) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Invite Link?'),
        content: const Text(
          'This will invalidate all existing invite links. '
          'Anyone with the old link will no longer be able to join.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              AppHaptics.buttonPress();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(
              foregroundColor: AppConstants.errorColor,
            ),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _regenerateInviteLink(context, ref, space.id);
    }
  }

  Future<void> _regenerateInviteLink(BuildContext context, WidgetRef ref, String spaceId) async {
    AppHaptics.light();

    final success = await ref.read(spacesProvider.notifier).regenerateInviteLink(spaceId);

    if (context.mounted) {
      if (success) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite link regenerated successfully'),
            backgroundColor: AppConstants.successColor,
          ),
        );
      } else {
        AppHaptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to regenerate invite link'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }
}
