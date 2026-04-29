import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/public_collection.dart';
import '../../providers/collections_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class MyCollectionsScreen extends ConsumerWidget {
  const MyCollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(myCollectionsNotifierProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Collections'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.explore),
            onPressed: () => context.push('/collections/explore'),
            tooltip: 'Explore',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_collections_create',
        onPressed: () => context.push('/collections/create'),
        backgroundColor: AppConstants.primaryBlueCyan,
        child: const Icon(Icons.add, color: Colors.white),
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
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(myCollectionsNotifierProvider.notifier).loadCollections(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (collections) {
          if (collections.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.collections_bookmark_outlined, size: 64, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No collections yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a collection to curate and share\nyour favorite content',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(myCollectionsNotifierProvider.notifier).loadCollections(),
            child: ListView.builder(
              padding: const EdgeInsets.all(AppConstants.spacingL),
              itemCount: collections.length,
              itemBuilder: (context, index) => _buildCollectionCard(context, collections[index], isDarkMode),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCollectionCard(BuildContext context, PublicCollection collection, bool isDarkMode) {
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    collection.title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: collection.isPublished
                        ? Colors.green.withValues(alpha:0.1)
                        : (isDarkMode ? Colors.white.withValues(alpha:0.05) : AppConstants.borderColor.withValues(alpha:0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    collection.isPublished ? 'Published' : 'Draft',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: collection.isPublished ? Colors.green : (isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
            if (collection.description != null) ...[
              const SizedBox(height: 6),
              Text(
                collection.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat(Icons.article_outlined, '${collection.itemCount} items', isDarkMode),
                const SizedBox(width: 16),
                _buildStat(Icons.visibility_outlined, '${collection.viewCount}', isDarkMode),
                const SizedBox(width: 16),
                _buildStat(Icons.fork_right, '${collection.forkCount}', isDarkMode),
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
