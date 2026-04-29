import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/public_collection.dart';
import '../../providers/collections_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class ExploreCollectionsScreen extends ConsumerWidget {
  const ExploreCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(exploreCollectionsProvider(1));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Collections'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: collectionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppConstants.errorColor),
              const SizedBox(height: 12),
              Text('Failed to load collections', style: TextStyle(color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary)),
            ],
          ),
        ),
        data: (collections) {
          if (collections.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.explore_outlined, size: 64, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No public collections yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Be the first to publish a collection!',
                    style: TextStyle(fontSize: 14, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            itemCount: collections.length,
            itemBuilder: (context, index) => _buildExploreCard(context, collections[index], isDarkMode),
          );
        },
      ),
    );
  }

  Widget _buildExploreCard(BuildContext context, PublicCollection collection, bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        AppHaptics.buttonPress();
        context.push('/collections/${collection.slug}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isDarkMode ? Colors.white.withValues(alpha:0.05) : AppConstants.borderColor.withValues(alpha:0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              collection.title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            if (collection.creatorName != null) ...[
              const SizedBox(height: 4),
              Text(
                'by ${collection.creatorName}',
                style: TextStyle(fontSize: 13, color: AppConstants.primaryBlueCyan),
              ),
            ],
            if (collection.description != null) ...[
              const SizedBox(height: 8),
              Text(
                collection.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat(Icons.article_outlined, '${collection.itemCount}', isDarkMode),
                const SizedBox(width: 16),
                _buildStat(Icons.visibility_outlined, '${collection.viewCount}', isDarkMode),
                const SizedBox(width: 16),
                _buildStat(Icons.fork_right, '${collection.forkCount}', isDarkMode),
                const Spacer(),
                Icon(Icons.chevron_right, size: 20, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String text, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary)),
      ],
    );
  }
}
