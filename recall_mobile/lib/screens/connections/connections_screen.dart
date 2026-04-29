import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/content_connection.dart';
import '../../models/connection_cluster.dart';
import '../../providers/connections_provider.dart';
import '../../providers/ui_providers.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/app_logo_header.dart';

class ConnectionsScreen extends ConsumerStatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  ConsumerState<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends ConsumerState<ConnectionsScreen> {
  bool _hasLoadedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadIfVisible();
    });
  }

  void _loadIfVisible() {
    final currentTab = ref.read(bottomNavProvider);
    if (currentTab == 1 && !_hasLoadedOnce) {
      _hasLoadedOnce = true;
      ref.read(clustersProvider.notifier).loadClusters(refresh: true);
    }
  }

  String _relativeTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Discovered today';
    if (diff.inDays == 1) return 'Discovered yesterday';
    if (diff.inDays < 7) return 'Discovered ${diff.inDays} days ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks == 1) return 'Discovered 1 week ago';
    if (weeks < 5) return 'Discovered $weeks weeks ago';
    final months = (diff.inDays / 30).floor();
    if (months == 1) return 'Discovered 1 month ago';
    return 'Discovered $months months ago';
  }

  String _buildSourceLine(List<String> sourceApps) {
    if (sourceApps.isEmpty) return '';
    final names = sourceApps.map(_capitalizeSource).toList();
    if (names.length == 1) return 'From ${names[0]}';
    if (names.length == 2) return 'From ${names[0]} and ${names[1]}';
    final shown = names.take(2).join(', ');
    final remaining = names.length - 2;
    return 'From $shown, and $remaining more';
  }

  String _capitalizeSource(String source) {
    if (source.isEmpty) return source;
    // Handle known names
    final lower = source.toLowerCase();
    const known = {
      'youtube': 'YouTube',
      'reddit': 'Reddit',
      'twitter': 'Twitter',
      'linkedin': 'LinkedIn',
      'medium': 'Medium',
      'github': 'GitHub',
      'hackernews': 'Hacker News',
      'hacker_news': 'Hacker News',
      'producthunt': 'Product Hunt',
      'product_hunt': 'Product Hunt',
    };
    if (known.containsKey(lower)) return known[lower]!;
    return source[0].toUpperCase() + source.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(bottomNavProvider, (previous, next) {
      if (next == 1) {
        ref.read(clustersProvider.notifier).loadClusters(refresh: true);
      }
    });

    final state = ref.watch(clustersProvider);
    final dailyAsync = ref.watch(dailyConnectionProvider);
    final currentUser = ref.watch(currentUserProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
      ),
      body: _buildBody(state, dailyAsync, isDarkMode),
    );
  }

  Widget _buildBody(ClustersState state, AsyncValue<ContentConnection?> dailyAsync, bool isDarkMode) {
    if (state.isLoading && state.clusters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final dailyConnection = dailyAsync.valueOrNull;

    if (state.clusters.isEmpty && dailyConnection == null) {
      return _buildEmptyState(isDarkMode);
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(dailyConnectionProvider);
        await ref.read(clustersProvider.notifier).loadClusters(refresh: true);
      },
      child: CustomScrollView(
        slivers: [
          // Today's Discovery section
          if (dailyConnection != null)
            SliverToBoxAdapter(
              child: _buildDailyDiscovery(dailyConnection, isDarkMode),
            ),

          // "Your Clusters" header
          if (state.clusters.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingM,
                  AppConstants.spacingM,
                  AppConstants.spacingM,
                  AppConstants.spacingS,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 18,
                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Text(
                      'Your Clusters',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Text(
                      '${state.clusters.length}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Cluster cards
          if (state.clusters.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final cluster = state.clusters[index];
                    return _buildClusterCard(context, cluster, isDarkMode);
                  },
                  childCount: state.clusters.length,
                ),
              ),
            ),

          // Empty clusters state (but daily connection exists)
          if (state.clusters.isEmpty && dailyConnection != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingXL),
                  child: Text(
                    'No topic clusters yet. Save more content to discover clusters.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDailyDiscovery(ContentConnection connection, bool isDarkMode) {
    final similarityPercent = '${(connection.similarityScore * 100).round()}%';

    return GestureDetector(
      onTap: () {
        AppHaptics.buttonPress();
        context.push('/connections/${connection.id}', extra: connection);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppConstants.spacingM,
          AppConstants.spacingS,
          AppConstants.spacingM,
          AppConstants.spacingS,
        ),
        padding: const EdgeInsets.all(AppConstants.spacingM),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppConstants.accentGradientEnhanced[0].withValues(alpha:0.15),
              AppConstants.accentGradientEnhanced[1].withValues(alpha:0.10),
              AppConstants.accentGradientEnhanced[2].withValues(alpha:0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: AppConstants.recallCyan.withValues(alpha:0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: AppConstants.recallCyan,
                ),
                const SizedBox(width: AppConstants.spacingS),
                Text(
                  "Today's Discovery",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.recallCyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),

            // Two items side by side
            Row(
              children: [
                // Source item
                Expanded(
                  child: _buildDiscoveryItem(connection.sourceItem, isDarkMode),
                ),
                // Center: link icon + similarity
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingS),
                  child: Column(
                    children: [
                      Icon(
                        Icons.link,
                        size: 20,
                        color: AppConstants.recallCyan,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        similarityPercent,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.recallCyan,
                        ),
                      ),
                    ],
                  ),
                ),
                // Target item
                Expanded(
                  child: _buildDiscoveryItem(connection.targetItem, isDarkMode),
                ),
              ],
            ),

            // AI explanation
            if (connection.aiExplanation != null) ...[
              const SizedBox(height: AppConstants.spacingM),
              Text(
                connection.aiExplanation!,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: isDarkMode
                      ? AppConstants.starlight.withValues(alpha:0.8)
                      : AppConstants.textPrimary.withValues(alpha:0.7),
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryItem(ConnectionItemSummary item, bool isDarkMode) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          child: item.thumbnailUrl != null
              ? Image.network(
                  item.thumbnailUrl!,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildDiscoveryPlaceholder(isDarkMode),
                )
              : _buildDiscoveryPlaceholder(isDarkMode),
        ),
        const SizedBox(height: AppConstants.spacingS),
        Text(
          item.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDiscoveryPlaceholder(bool isDarkMode) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppConstants.recallCyan.withValues(alpha:0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
      ),
      child: Icon(
        Icons.article_outlined,
        size: 28,
        color: AppConstants.recallCyan.withValues(alpha:0.6),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hub_outlined,
              size: 64,
              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
            ),
            const SizedBox(height: AppConstants.spacingL),
            Text(
              'No topic clusters yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacingS),
            Text(
              'Save more content and AI will discover topic clusters between your articles automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'technology':
        return Icons.computer_outlined;
      case 'business':
        return Icons.trending_up_outlined;
      case 'design':
        return Icons.palette_outlined;
      case 'science':
        return Icons.science_outlined;
      case 'culture':
        return Icons.museum_outlined;
      case 'health':
        return Icons.favorite_outline;
      default:
        return Icons.hub_outlined;
    }
  }

  String? _dominantCategory(ConnectionCluster cluster) {
    final categories = cluster.previewItems
        .where((item) => item.category != null && item.category!.isNotEmpty)
        .map((item) => item.category!)
        .toList();
    if (categories.isEmpty) return null;
    final freq = <String, int>{};
    for (final c in categories) {
      freq[c] = (freq[c] ?? 0) + 1;
    }
    return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String _synthesizeDescription(ConnectionCluster cluster) {
    final categories = cluster.previewItems
        .where((item) => item.category != null && item.category!.isNotEmpty)
        .map((item) => item.category!)
        .toSet()
        .toList();
    if (categories.length >= 2) {
      return 'Explores themes across ${categories.take(3).join(", ")}';
    }
    final titles = cluster.previewItems.map((item) => item.title).toList();
    if (titles.length >= 2) {
      return 'Connecting "${titles[0]}" with "${titles[1]}"${cluster.itemCount > 2 ? ' and ${cluster.itemCount - 2} more' : ''}';
    }
    if (titles.length == 1) {
      return 'Built around "${titles.first}"';
    }
    return '${cluster.itemCount} semantically related items';
  }

  String _resolveClusterLabel(ConnectionCluster cluster) {
    // Strip trailing " Cluster" or " Collection" from any label — redundant in this context
    String label = cluster.label.trim();
    final generic = label.toLowerCase();

    if (generic == 'related items' || generic.isEmpty) {
      // Derive from the most common non-"Other" category
      final categories = cluster.previewItems
          .where((item) =>
              item.category != null &&
              item.category!.isNotEmpty &&
              item.category!.toLowerCase() != 'other')
          .map((item) => item.category!)
          .toList();
      if (categories.isNotEmpty) {
        final freq = <String, int>{};
        for (final c in categories) {
          freq[c] = (freq[c] ?? 0) + 1;
        }
        return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      // Fall back to first preview item title
      if (cluster.previewItems.isNotEmpty) {
        final first = cluster.previewItems.first.title;
        return first.length > 40 ? '${first.substring(0, 37)}...' : first;
      }
    }

    // Remove redundant suffixes from AI-generated or fallback labels
    for (final suffix in [' Cluster', ' Collection']) {
      if (label.endsWith(suffix) && label.length > suffix.length) {
        label = label.substring(0, label.length - suffix.length);
      }
    }

    // If after stripping we're left with just "Other", try to use a title instead
    if (label.toLowerCase() == 'other' && cluster.previewItems.isNotEmpty) {
      final first = cluster.previewItems.first.title;
      return first.length > 40 ? '${first.substring(0, 37)}...' : first;
    }

    return label;
  }

  Widget _buildClusterCard(BuildContext context, ConnectionCluster cluster, bool isDarkMode) {
    final displayLabel = _resolveClusterLabel(cluster);
    final topCategory = _dominantCategory(cluster);
    final icon = _categoryIcon(topCategory);
    final categoryColor = AppConstants.clusterColorFor(topCategory);
    final description = (cluster.description != null && cluster.description!.isNotEmpty)
        ? cluster.description!
        : _synthesizeDescription(cluster);
    final sourceLine = _buildSourceLine(cluster.sourceApps);
    final timeLine = _relativeTime(cluster.createdAt);

    return Dismissible(
      key: Key(cluster.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppConstants.spacingL),
        margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
        decoration: BoxDecoration(
          color: AppConstants.errorColor,
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 28),
      ),
      onDismissed: (_) {
        AppHaptics.swipe();
        ref.read(clustersProvider.notifier).dismissCluster(cluster.id);
      },
      child: GestureDetector(
        onTap: () {
          AppHaptics.buttonPress();
          context.push('/clusters/${cluster.id}');
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
          decoration: BoxDecoration(
            color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(AppConstants.radiusXL),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withValues(alpha:0.05)
                  : AppConstants.borderColor.withValues(alpha:0.5),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: categoryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppConstants.radiusXL),
                      bottomLeft: Radius.circular(AppConstants.radiusXL),
                    ),
                  ),
                ),
                // Card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingM),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row: icon + label + chevron
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                              ),
                              child: Icon(
                                icon,
                                size: 20,
                                color: categoryColor,
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingM),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayLabel,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${cluster.itemCount} items${cluster.avgSimilarity != null ? ' · ${(cluster.avgSimilarity! * 100).round()}% similar' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                            ),
                          ],
                        ),

                        // Description
                        const SizedBox(height: AppConstants.spacingS),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Thumbnail collage + source line
                        if (cluster.previewItems.isNotEmpty) ...[
                          const SizedBox(height: AppConstants.spacingM),
                          Row(
                            children: [
                              // Overlapping circle thumbnails
                              SizedBox(
                                width: 36.0 + (cluster.previewItems.take(3).length - 1).clamp(0, 2) * 28.0,
                                height: 36,
                                child: Stack(
                                  children: [
                                    for (int i = 0; i < cluster.previewItems.take(3).length; i++)
                                      Positioned(
                                        left: i * 28.0,
                                        child: _buildCircleThumbnail(
                                          cluster.previewItems[i],
                                          categoryColor,
                                          isDarkMode,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (sourceLine.isNotEmpty) ...[
                                const SizedBox(width: AppConstants.spacingS),
                                Expanded(
                                  child: Text(
                                    sourceLine,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],

                        // Timestamp
                        const SizedBox(height: AppConstants.spacingS),
                        Text(
                          timeLine,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? AppConstants.slateGray.withValues(alpha:0.7)
                                : AppConstants.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCircleThumbnail(ClusterPreviewItem item, Color categoryColor, bool isDarkMode) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: item.thumbnailUrl != null
            ? Image.network(
                item.thumbnailUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _buildCirclePlaceholder(categoryColor),
              )
            : _buildCirclePlaceholder(categoryColor),
      ),
    );
  }

  Widget _buildCirclePlaceholder(Color color) {
    return Container(
      width: 36,
      height: 36,
      color: color.withValues(alpha:0.15),
      child: Icon(
        Icons.article_outlined,
        size: 16,
        color: color.withValues(alpha:0.6),
      ),
    );
  }
}

/// Connection detail screen showing both items with full context
class ConnectionDetailScreen extends StatelessWidget {
  final ContentConnection connection;

  const ConnectionDetailScreen({super.key, required this.connection});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connection'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Explanation (prominent)
            if (connection.aiExplanation != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spacingL),
                margin: const EdgeInsets.only(bottom: AppConstants.spacingL),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                      AppConstants.primaryColor.withValues(alpha:0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                  border: Border.all(
                    color: AppConstants.primaryBlueCyan.withValues(alpha:0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: AppConstants.primaryBlueCyan,
                      size: 24,
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      child: Text(
                        connection.aiExplanation!,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Similarity badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingM,
                  vertical: AppConstants.spacingS,
                ),
                decoration: BoxDecoration(
                  color: AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusL),
                ),
                child: Text(
                  '${connection.similarityPercent} similar',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.primaryBlueCyan,
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppConstants.spacingL),

            // Source item
            _buildItemCard(context, connection.sourceItem, isDarkMode),

            // Connection line
            Center(
              child: Container(
                height: 40,
                width: 2,
                color: AppConstants.primaryBlueCyan.withValues(alpha:0.3),
              ),
            ),

            // Target item
            _buildItemCard(context, connection.targetItem, isDarkMode),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, ConnectionItemSummary item, bool isDarkMode) {
    return GestureDetector(
      onTap: () => context.push('/content/${item.id}'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha:0.05)
                : AppConstants.borderColor.withValues(alpha:0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.thumbnailUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                child: Image.network(
                  item.thumbnailUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            if (item.thumbnailUrl != null) const SizedBox(height: AppConstants.spacingM),
            Text(
              item.title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            if (item.summary != null) ...[
              const SizedBox(height: AppConstants.spacingS),
              Text(
                item.summary!,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                  height: 1.5,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: AppConstants.spacingS),
            Row(
              children: [
                if (item.sourceApp != null) ...[
                  Text(
                    item.sourceApp!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                ],
                if (item.category != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category!,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppConstants.primaryBlueCyan,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
