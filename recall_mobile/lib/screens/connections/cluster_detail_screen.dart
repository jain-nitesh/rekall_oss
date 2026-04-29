import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/connection_cluster.dart';
import '../../providers/connections_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class ClusterDetailScreen extends ConsumerStatefulWidget {
  final String clusterId;

  const ClusterDetailScreen({super.key, required this.clusterId});

  @override
  ConsumerState<ClusterDetailScreen> createState() => _ClusterDetailScreenState();
}

class _ClusterDetailScreenState extends ConsumerState<ClusterDetailScreen> {
  String? _selectedItemId;

  String _resolveDetailLabel(ConnectionClusterDetail detail) {
    String label = detail.label.trim();
    final generic = label.toLowerCase();

    if (generic == 'related items' || generic.isEmpty) {
      final categories = detail.items
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
      if (detail.items.isNotEmpty) {
        final first = detail.items.first.title;
        return first.length > 40 ? '${first.substring(0, 37)}...' : first;
      }
    }

    // Remove redundant suffixes
    for (final suffix in [' Cluster', ' Collection']) {
      if (label.endsWith(suffix) && label.length > suffix.length) {
        label = label.substring(0, label.length - suffix.length);
      }
    }

    if (label.toLowerCase() == 'other' && detail.items.isNotEmpty) {
      final first = detail.items.first.title;
      return first.length > 40 ? '${first.substring(0, 37)}...' : first;
    }

    return label;
  }

  String _synthesizeDetailDescription(ConnectionClusterDetail detail) {
    final categories = detail.items
        .where((item) => item.category != null && item.category!.isNotEmpty)
        .map((item) => item.category!)
        .toSet()
        .toList();
    if (categories.length >= 2) {
      return 'A collection spanning ${categories.take(3).join(", ")}';
    }
    final titles = detail.items.map((item) => item.title).toList();
    if (titles.length >= 2) {
      final shown = titles.take(2).join(', ');
      final remaining = detail.items.length - 2;
      return remaining > 0 ? 'Includes $shown, and $remaining more' : 'Includes $shown';
    }
    if (titles.length == 1) {
      return 'Includes ${titles.first}';
    }
    return '${detail.items.length} related items';
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(clusterDetailProvider(widget.clusterId));
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: detailAsync.whenOrNull(
          data: (detail) => detail != null
              ? Text(_resolveDetailLabel(detail))
              : const Text('Cluster'),
        ) ?? const Text('Cluster'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Failed to load cluster',
            style: TextStyle(
              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
            ),
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return Center(
              child: Text(
                'Cluster not found',
                style: TextStyle(
                  color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                ),
              ),
            );
          }
          return _buildContent(context, detail, isDarkMode);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ConnectionClusterDetail detail, bool isDarkMode) {
    // Find connections for selected item
    final selectedConnections = _selectedItemId != null
        ? detail.connections.where(
            (c) => c.sourceItemId == _selectedItemId || c.targetItemId == _selectedItemId,
          ).toList()
        : <ClusterConnection>[];

    // Top 3 connections by similarity for "Key Connections" section
    final topConnections = List<ClusterConnection>.from(detail.connections)
      ..sort((a, b) => b.similarityScore.compareTo(a.similarityScore));
    final keyConnections = topConnections.take(3).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI description container
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
                    (detail.description != null && detail.description!.isNotEmpty)
                        ? detail.description!
                        : _synthesizeDetailDescription(detail),
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

          // Key Connections section
          if (keyConnections.isNotEmpty) ...[
            _buildKeyConnections(context, detail, keyConnections, isDarkMode),
            const SizedBox(height: AppConstants.spacingL),
          ],

          // 2-column grid of items
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: detail.items.length,
            itemBuilder: (context, index) {
              final item = detail.items[index];
              final isSelected = _selectedItemId == item.id;
              return _buildGridItem(context, item, isSelected, isDarkMode);
            },
          ),

          // Connections panel for selected item
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            height: _selectedItemId != null && selectedConnections.isNotEmpty ? null : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: _selectedItemId != null && selectedConnections.isNotEmpty
                ? _buildConnectionsPanel(
                    context, detail, selectedConnections, isDarkMode)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyConnections(
    BuildContext context,
    ConnectionClusterDetail detail,
    List<ClusterConnection> connections,
    bool isDarkMode,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(
              Icons.hub_outlined,
              size: 18,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
            const SizedBox(width: AppConstants.spacingS),
            Text(
              'Key Connections',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingS),

        // Connection rows
        ...connections.map((conn) {
          final sourceItem = detail.items.where((i) => i.id == conn.sourceItemId).firstOrNull;
          final targetItem = detail.items.where((i) => i.id == conn.targetItemId).firstOrNull;
          if (sourceItem == null || targetItem == null) return const SizedBox.shrink();

          final similarityPercent = '${(conn.similarityScore * 100).round()}%';

          return GestureDetector(
            onTap: () {
              AppHaptics.buttonPress();
              setState(() {
                _selectedItemId = conn.sourceItemId;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
              padding: const EdgeInsets.all(AppConstants.spacingM),
              decoration: BoxDecoration(
                color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(AppConstants.radiusM),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha:0.05)
                      : AppConstants.borderColor.withValues(alpha:0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row: source <-> target + similarity
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: sourceItem.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: '  ↔  ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppConstants.primaryBlueCyan,
                                ),
                              ),
                              TextSpan(
                                text: targetItem.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          similarityPercent,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppConstants.primaryBlueCyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // AI explanation
                  if (conn.aiExplanation != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      conn.aiExplanation!,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGridItem(
      BuildContext context, ClusterDetailItem item, bool isSelected, bool isDarkMode) {
    final categoryColor = AppConstants.clusterColorFor(item.category);

    return GestureDetector(
      onTap: () {
        AppHaptics.buttonPress();
        setState(() {
          _selectedItemId = _selectedItemId == item.id ? null : item.id;
        });
      },
      onLongPress: () {
        AppHaptics.buttonPress();
        context.push('/content/${item.id}');
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isSelected
                ? categoryColor
                : (isDarkMode
                    ? Colors.white.withValues(alpha:0.05)
                    : AppConstants.borderColor.withValues(alpha:0.5)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail or placeholder
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusXL),
              ),
              child: item.thumbnailUrl != null
                  ? Image.network(
                      item.thumbnailUrl!,
                      height: 80,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildColoredPlaceholder(item.category, isDarkMode),
                    )
                  : _buildColoredPlaceholder(item.category, isDarkMode),
            ),

            // Title, category, and source app
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacingS),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    if (item.category != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha:0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.category!,
                          style: TextStyle(
                            fontSize: 11,
                            color: categoryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (item.sourceApp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.sourceApp!,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDarkMode ? AppConstants.slateGray : AppConstants.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColoredPlaceholder(String? category, bool isDarkMode) {
    final color = AppConstants.clusterColorFor(category);
    return Container(
      height: 80,
      width: double.infinity,
      color: color.withValues(alpha:0.15),
      child: Center(
        child: Icon(
          Icons.article_outlined,
          size: 32,
          color: color.withValues(alpha:0.5),
        ),
      ),
    );
  }

  Widget _buildConnectionsPanel(
    BuildContext context,
    ConnectionClusterDetail detail,
    List<ClusterConnection> connections,
    bool isDarkMode,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppConstants.spacingM),
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: isDarkMode ? AppConstants.surfaceDark : const Color(0xFFFAFAFA),
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
          Text(
            'Connected to:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingS),
          ...connections.map((conn) {
            // Find the other item in this connection
            final otherItemId = conn.sourceItemId == _selectedItemId
                ? conn.targetItemId
                : conn.sourceItemId;
            final otherItem = detail.items.where((i) => i.id == otherItemId).firstOrNull;
            if (otherItem == null) return const SizedBox.shrink();

            final similarityPercent = '${(conn.similarityScore * 100).round()}%';
            final categoryColor = AppConstants.clusterColorFor(otherItem.category);

            return GestureDetector(
              onTap: () {
                AppHaptics.buttonPress();
                context.push('/content/${otherItem.id}');
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
                padding: const EdgeInsets.all(AppConstants.spacingS),
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? AppConstants.backgroundDark
                      : Colors.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  border: Border.all(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha:0.05)
                        : AppConstants.borderColor.withValues(alpha:0.3),
                  ),
                ),
                child: Row(
                  children: [
                    // Thumbnail or placeholder
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppConstants.radiusS),
                      child: otherItem.thumbnailUrl != null
                          ? Image.network(
                              otherItem.thumbnailUrl!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 40,
                                height: 40,
                                color: categoryColor.withValues(alpha:0.15),
                                child: Icon(
                                  Icons.article_outlined,
                                  size: 20,
                                  color: categoryColor,
                                ),
                              ),
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha:0.15),
                                borderRadius: BorderRadius.circular(AppConstants.radiusS),
                              ),
                              child: Icon(
                                Icons.article_outlined,
                                size: 20,
                                color: categoryColor,
                              ),
                            ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            otherItem.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? AppConstants.starlight
                                  : AppConstants.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (conn.aiExplanation != null)
                            Text(
                              conn.aiExplanation!,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDarkMode
                                    ? AppConstants.slateGray
                                    : AppConstants.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryBlueCyan.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        similarityPercent,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppConstants.primaryBlueCyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
