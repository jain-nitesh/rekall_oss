import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/content_item.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';
import '../utils/haptics.dart';
import '../providers/content_provider.dart';
import '../providers/time_based_content_provider.dart';
import 'source_app_icon.dart';
import 'share_to_space_sheet.dart';

/// Format duration for video badge. Returns null if no duration available.
String? _durationLabel(ContentItem item) {
  if (item.mediaDurationSeconds != null && item.mediaDurationSeconds! > 0) {
    final secs = item.mediaDurationSeconds!.round();
    return '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  }
  if (item.readingTimeMinutes != null && item.readingTimeMinutes! > 0) {
    return '${item.readingTimeMinutes}:00';
  }
  return null;
}

/// Content card widget for displaying content items
class ContentCard extends ConsumerWidget {
  final ContentItem item;
  final VoidCallback? onTap;
  final bool compact;
  final bool enableSwipeToDismiss;

  const ContentCard({
    super.key,
    required this.item,
    this.onTap,
    this.compact = false,
    this.enableSwipeToDismiss = true,
  });

  /// Factory for compact view (for memory feed sections)
  factory ContentCard.compact({
    required ContentItem item,
    VoidCallback? onTap,
    bool enableSwipeToDismiss = true,
  }) {
    return ContentCard(
      item: item,
      onTap: onTap,
      compact: true,
      enableSwipeToDismiss: enableSwipeToDismiss,
    );
  }

  /// Factory for full view (for lists)
  factory ContentCard.full({
    required ContentItem item,
    VoidCallback? onTap,
    bool enableSwipeToDismiss = true,
  }) {
    return ContentCard(
      item: item,
      onTap: onTap,
      compact: false,
      enableSwipeToDismiss: enableSwipeToDismiss,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = compact ? _buildCompactCard(context, ref) : _buildFullCard(context, ref);

    // Wrap with Dismissible if enabled
    if (enableSwipeToDismiss) {
      return Dismissible(
        key: Key(item.id),
        direction: DismissDirection.horizontal,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppConstants.spacingL),
          margin: compact
              ? const EdgeInsets.only(right: AppConstants.spacingS)
              : const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingM,
                  vertical: AppConstants.spacingXS,
                ),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text(
                'Done',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: AppConstants.spacingL),
          margin: compact
              ? const EdgeInsets.only(right: AppConstants.spacingS)
              : const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingM,
                  vertical: AppConstants.spacingXS,
                ),
          decoration: BoxDecoration(
            color: AppConstants.errorColor,
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart) {
            // Swipe left = Delete (medium haptic for destructive action)
            AppHaptics.destructive();
            return await _confirmDelete(context, ref);
          } else {
            // Swipe right = Mark as done (light haptic for non-destructive action)
            if (!item.isDone) {
              AppHaptics.swipe();
              await ref.read(contentProvider.notifier).markAsDone(item.id);

              // Remove from time-based feed sections immediately
              ref.read(justInContentProvider.notifier).removeItem(item.id);
              ref.read(todayContentProvider.notifier).removeItem(item.id);
              ref.read(yesterdayContentProvider.notifier).removeItem(item.id);
              ref.read(olderContentProvider.notifier).removeItem(item.id);

              // Show snackbar with undo option
              if (context.mounted) {
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Marked as done'),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () {
                        ref.read(contentProvider.notifier).undoMarkAsDone(item.id);
                        // Refresh time-based providers to restore the item
                        ref.read(justInContentProvider.notifier).refresh();
                        ref.read(todayContentProvider.notifier).refresh();
                        ref.read(yesterdayContentProvider.notifier).refresh();
                        ref.read(olderContentProvider.notifier).refresh();
                      },
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }

            return false; // Don't actually dismiss, just mark as done
          }
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.endToStart) {
            // Item was deleted
            if (context.mounted) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Content deleted'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        },
        child: card,
      );
    }

    return card;
  }

  Future<bool> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Content'),
        content: const Text('Are you sure you want to delete this content? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(contentProvider.notifier).deleteContent(item.id);
      return true;
    }

    return false;
  }

  void _showQuickActions(BuildContext context, WidgetRef ref) {
    AppHaptics.heavy();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppConstants.surfaceDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title preview
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                item.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            if (item.url != null && item.url!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('Open in Browser'),
                onTap: () {
                  Navigator.pop(context);
                  AppHaptics.buttonPress();
                  launchUrl(Uri.parse(item.url!), mode: LaunchMode.externalApplication);
                },
              ),
            ListTile(
              leading: Icon(item.isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: item.isFavorite ? Colors.red : null),
              title: Text(item.isFavorite ? 'Unfavorite' : 'Favorite'),
              onTap: () {
                Navigator.pop(context);
                ref.read(contentProvider.notifier).toggleFavorite(item.id);
                AppHaptics.success();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Add to Space'),
              onTap: () {
                Navigator.pop(context);
                showShareToSpaceSheet(
                  context,
                  contentId: item.id,
                  contentTitle: item.title,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                AppHaptics.buttonPress();
                SharePlus.instance.share(ShareParams(text: item.url ?? item.title));
              },
            ),
            if (!item.isDone)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('Mark as Done'),
                onTap: () {
                  Navigator.pop(context);
                  AppHaptics.swipe();
                  ref.read(contentProvider.notifier).markAsDone(item.id);
                  ref.read(justInContentProvider.notifier).removeItem(item.id);
                  ref.read(todayContentProvider.notifier).removeItem(item.id);
                  ref.read(yesterdayContentProvider.notifier).removeItem(item.id);
                  ref.read(olderContentProvider.notifier).removeItem(item.id);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: AppConstants.errorColor),
              title: Text('Delete', style: TextStyle(color: AppConstants.errorColor)),
              onTap: () async {
                Navigator.pop(context);
                _confirmDelete(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: item.isDone ? 0.5 : 1.0,
      child: Container(
        width: 280,
        margin: const EdgeInsets.only(right: AppConstants.spacingM),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
          color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
          boxShadow: isDarkMode ? [] : AppTheme.shadowSoftDual,
        ),
        child: InkWell(
          onTap: () {
            AppHaptics.buttonPress();
            onTap?.call();
          },
          onLongPress: () => _showQuickActions(context, ref),
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail (if available) - Top section
              if (item.effectiveThumbnailUrl != null)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppConstants.radiusXL),
                    topRight: Radius.circular(AppConstants.radiusXL),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          item.effectiveThumbnailUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: isDarkMode
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : AppConstants.borderColor.withValues(alpha: 0.3),
                              child: Center(
                                child: Icon(
                                  Icons.image,
                                  color: isDarkMode
                                      ? AppConstants.slateGray
                                      : AppConstants.textSecondary,
                                  size: 32,
                                ),
                              ),
                            );
                          },
                        ),
                        // Play overlay for videos
                        if (item.sourceApp == SourceApp.youtube || item.contentType == ContentType.video)
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.1),
                                  Colors.black.withValues(alpha: 0.3),
                                ],
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  size: 32,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        // Duration badge
                        if (item.sourceApp == SourceApp.youtube || item.contentType == ContentType.video)
                          if (_durationLabel(item) != null)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _durationLabel(item)!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),

              // Content section
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source icon and time
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: SourceAppIcon(sourceApp: item.sourceApp, size: 12),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${item.isMedia ? (item.contentType == ContentType.image ? "Photo" : "Video") : (item.sourceAppName ?? AppConstants.sourceAppNames[item.sourceApp] ?? 'Unknown')} • ${item.getRelativeTime()}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacingS),

                    // Title
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                        decoration: item.isDone ? TextDecoration.lineThrough : null,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: item.isDone ? 0.5 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingM,
          vertical: AppConstants.spacingS,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.borderColor.withValues(alpha: 0.5),
            width: 1,
          ),
          color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
          boxShadow: isDarkMode
              ? []
              : AppTheme.shadowSoftDual,
        ),
        child: InkWell(
          onTap: () {
            AppHaptics.buttonPress();
            onTap?.call();
          },
          onLongPress: () => _showQuickActions(context, ref),
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main content area
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacingM + 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: Source icon + name and Time ago + Add to Space button
                    Row(
                      children: [
                        // Source icon
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Center(
                            child: SourceAppIcon(sourceApp: item.sourceApp, size: 14),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingS),
                        Expanded(
                          child: Text(
                            '${item.isMedia ? (item.contentType == ContentType.image ? "Photo" : "Video") : (item.sourceAppName ?? AppConstants.sourceAppNames[item.sourceApp] ?? 'Unknown')} • ${item.getRelativeTime()}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Add to Space button
                        InkWell(
                          onTap: () {
                            AppHaptics.buttonPress();
                            showShareToSpaceSheet(
                              context,
                              contentId: item.id,
                              contentTitle: item.title,
                            );
                          },
                          borderRadius: BorderRadius.circular(AppConstants.radiusS),
                          child: Padding(
                            padding: const EdgeInsets.all(AppConstants.spacingXS),
                            child: Icon(
                              Icons.folder_outlined,
                              size: 20,
                              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacingM),

                    // Content row: Text content on left, thumbnail on right
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: Title, summary, and categories
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title (smaller)
                              Text(
                                item.title,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                                  decoration: item.isDone ? TextDecoration.lineThrough : null,
                                  letterSpacing: -0.2,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppConstants.spacingS),

                              // Summary
                              Text(
                                item.summary,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDarkMode
                                      ? AppConstants.slateGray.withValues(alpha: 0.9)
                                      : AppConstants.textSecondary,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              // Categories/Tags (show first 3)
                              if (item.tags.isNotEmpty) ...[
                                const SizedBox(height: AppConstants.spacingS),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: item.tags.take(3).map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDarkMode
                                            ? Colors.white.withValues(alpha: 0.08)
                                            : AppConstants.borderColor.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDarkMode
                                              ? AppConstants.slateGray
                                              : AppConstants.textSecondary,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],

                              // Connection count badge
                              if (item.connectionCount > 0) ...[
                                const SizedBox(height: AppConstants.spacingS),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.hub,
                                      size: 14,
                                      color: AppConstants.primaryBlueCyan,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${item.connectionCount} connection${item.connectionCount == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: AppConstants.primaryBlueCyan,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Right side: Thumbnail (if available)
                        if (item.effectiveThumbnailUrl != null) ...[
                          const SizedBox(width: AppConstants.spacingM),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppConstants.radiusM),
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    item.effectiveThumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        color: isDarkMode
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : AppConstants.borderColor.withValues(alpha: 0.3),
                                        child: Center(
                                          child: Icon(
                                            Icons.image,
                                            color: isDarkMode
                                                ? AppConstants.slateGray
                                                : AppConstants.textSecondary,
                                            size: 24,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Play button overlay for video content (YouTube, etc.)
                                  if (item.sourceApp == SourceApp.youtube || item.contentType == ContentType.video)
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.1),
                                            Colors.black.withValues(alpha: 0.4),
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.play_arrow,
                                            size: 20,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
