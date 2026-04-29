import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/public_collection.dart';
import '../../providers/collections_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import 'package:url_launcher/url_launcher.dart';

class CollectionDetailScreen extends ConsumerWidget {
  final String slug;

  const CollectionDetailScreen({super.key, required this.slug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionAsync = ref.watch(collectionDetailProvider(slug));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Collection'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          collectionAsync.whenOrNull(
                data: (collection) => IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: () {
                    AppHaptics.buttonPress();
                    SharePlus.instance.share(
                      ShareParams(text: 'Check out "${collection.title}" on ReKall!\nhttps://YOUR_BACKEND_DOMAIN/c/${collection.slug}'),
                    );
                  },
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: collectionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppConstants.errorColor),
              const SizedBox(height: 12),
              Text('Collection not found', style: TextStyle(color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary)),
            ],
          ),
        ),
        data: (collection) => _buildContent(context, ref, collection, isDarkMode),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, PublicCollection collection, bool isDarkMode) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            collection.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
          ),

          if (collection.creatorName != null) ...[
            const SizedBox(height: 6),
            Text(
              'by ${collection.creatorName}',
              style: TextStyle(fontSize: 14, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
            ),
          ],

          if (collection.description != null) ...[
            const SizedBox(height: 12),
            Text(
              collection.description!,
              style: TextStyle(
                fontSize: 15,
                color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                height: 1.5,
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _buildStat(Icons.article_outlined, '${collection.items.length} items', isDarkMode),
              const SizedBox(width: 20),
              _buildStat(Icons.visibility_outlined, '${collection.viewCount} views', isDarkMode),
              const SizedBox(width: 20),
              _buildStat(Icons.fork_right, '${collection.forkCount} forks', isDarkMode),
            ],
          ),

          const SizedBox(height: 16),

          // Fork button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                AppHaptics.buttonPress();
                final result = await ref.read(myCollectionsNotifierProvider.notifier).forkCollection(collection.id);
                if (result != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Forked ${result['forked_items']} items to your library!')),
                  );
                }
              },
              icon: const Icon(Icons.fork_right),
              label: const Text('Fork to My Library'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryBlueCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusM)),
              ),
            ),
          ),

          const SizedBox(height: AppConstants.spacingXL),

          // Items
          Text(
            'Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),

          if (collection.items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No items in this collection yet',
                  style: TextStyle(color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                ),
              ),
            )
          else
            ...collection.items.map((item) => _buildItemCard(context, item, isDarkMode)),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, CollectionItem item, bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        AppHaptics.buttonPress();
        if (item.url != null) {
          launchUrl(Uri.parse(item.url!), mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          border: Border.all(
            color: isDarkMode ? AppConstants.starlight.withValues(alpha:0.05) : AppConstants.borderColor.withValues(alpha:0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.thumbnailUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  item.thumbnailUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 60,
                    height: 60,
                    color: AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                    child: Icon(Icons.article, color: AppConstants.primaryBlueCyan),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? 'Untitled',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                  ),
                  if (item.summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                      ),
                    ),
                  ],
                  if (item.curatorNote != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryBlueCyan.withValues(alpha:0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.format_quote, size: 14, color: AppConstants.primaryBlueCyan),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.curatorNote!,
                              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (item.sourceApp != null || item.category != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.sourceApp != null)
                          Text(item.sourceApp!, style: TextStyle(fontSize: 11, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary)),
                        if (item.sourceApp != null && item.category != null)
                          Text(' · ', style: TextStyle(color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary)),
                        if (item.category != null)
                          Text(item.category!, style: TextStyle(fontSize: 11, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String text, bool isDarkMode) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 13, color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary)),
      ],
    );
  }
}
