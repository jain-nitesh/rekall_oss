import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/connection_cluster.dart';
import '../providers/connections_provider.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';

/// Horizontal carousel showing AI-discovered content clusters in the feed.
/// Surfaces the Brain's intelligence on the main screen.
class BrainSuggestionsSection extends ConsumerStatefulWidget {
  const BrainSuggestionsSection({super.key});

  @override
  ConsumerState<BrainSuggestionsSection> createState() => _BrainSuggestionsSectionState();
}

class _BrainSuggestionsSectionState extends ConsumerState<BrainSuggestionsSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // Always reload clusters to pick up login changes
      ref.read(clustersProvider.notifier).loadClusters(refresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clustersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Don't show if no clusters or still loading for first time
    if (state.clusters.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              Icon(
                Icons.psychology,
                size: 20,
                color: AppConstants.synapseIndigo,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your Brain Suggests',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  AppHaptics.buttonPress();
                  context.push('/connections');
                },
                child: Text(
                  'See all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppConstants.primaryBlueCyan,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal cluster carousel
        SizedBox(
          height: 130,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.clusters.length > 8 ? 8 : state.clusters.length,
            itemBuilder: (context, index) {
              final cluster = state.clusters[index];
              return _ClusterCard(
                cluster: cluster,
                isDark: isDark,
                onTap: () {
                  AppHaptics.buttonPress();
                  context.push('/clusters/${cluster.id}');
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ClusterCard extends StatelessWidget {
  final ConnectionCluster cluster;
  final bool isDark;
  final VoidCallback onTap;

  const _ClusterCard({
    required this.cluster,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? AppConstants.synapseIndigo.withValues(alpha: 0.2)
                : AppConstants.synapseIndigo.withValues(alpha: 0.1),
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: AppConstants.synapseIndigo.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cluster label
            Text(
              cluster.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Description or item count
            if (cluster.description != null && cluster.description!.isNotEmpty)
              Text(
                cluster.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.slateGray,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            else
              Text(
                '${cluster.itemCount} related items',
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.slateGray,
                ),
              ),

            const Spacer(),

            // Bottom row: source apps + similarity
            Row(
              children: [
                // Source app indicators
                if (cluster.sourceApps.isNotEmpty) ...[
                  ...cluster.sourceApps.take(3).map((source) {
                    return Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppConstants.borderColor.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _capitalize(source),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.slateGray,
                        ),
                      ),
                    );
                  }),
                ],
                const Spacer(),
                Icon(Icons.arrow_forward_ios, size: 12, color: AppConstants.slateGray),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    const known = {
      'youtube': 'YT',
      'reddit': 'Reddit',
      'twitter': 'X',
      'linkedin': 'LI',
      'medium': 'Medium',
      'github': 'GH',
    };
    return known[lower] ?? (s[0].toUpperCase() + s.substring(1));
  }
}
