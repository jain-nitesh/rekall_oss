import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/trending_news_item.dart';
import '../providers/trending_news_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';

/// Displays trending news cards on the empty home feed.
/// Each card has a [+ Save] button that ingests the URL into the user's feed.
class TrendingNewsSection extends ConsumerStatefulWidget {
  const TrendingNewsSection({super.key});

  @override
  ConsumerState<TrendingNewsSection> createState() =>
      _TrendingNewsSectionState();
}

class _TrendingNewsSectionState extends ConsumerState<TrendingNewsSection> {
  final Set<String> _savingUrls = {};
  final Set<String> _savedUrls = {};

  Future<void> _saveItem(TrendingNewsItem item) async {
    if (!item.isSaveable || _savingUrls.contains(item.url)) return;

    AppHaptics.light();
    setState(() => _savingUrls.add(item.url));

    bool success = false;
    try {
      await ApiService().ingestContent(
        url: item.url,
        title: item.title,
        sourceAppName: 'trending',
        sharedText: '${item.title}\n\n${item.summary}\n\nSource: ${item.source}',
      );
      success = true;
    } catch (_) {
      success = false;
    }

    if (!mounted) return;

    setState(() {
      _savingUrls.remove(item.url);
      if (success) _savedUrls.add(item.url);
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${item.title}"'),
          backgroundColor: AppConstants.successColor,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save article'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final newsAsync = ref.watch(trendingNewsProvider);

    return newsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spacingM),
              // Section header
              Row(
                children: [
                  Icon(
                    Icons.trending_up,
                    size: 20,
                    color: isDarkMode
                        ? AppConstants.primaryBlueCyan
                        : AppConstants.synapseIndigo,
                  ),
                  const SizedBox(width: AppConstants.spacingS),
                  Text(
                    'Trending Now',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDarkMode
                          ? AppConstants.starlight
                          : AppConstants.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Save articles to build your personal feed',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: isDarkMode
                      ? AppConstants.slateGray
                      : AppConstants.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingM),

              // News cards
              ...items.map((item) => _buildNewsCard(item, isDarkMode)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNewsCard(TrendingNewsItem item, bool isDarkMode) {
    final isSaving = _savingUrls.contains(item.url);
    final isSaved = _savedUrls.contains(item.url);

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingS),
      padding: const EdgeInsets.all(AppConstants.spacingM),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : AppConstants.softWhite,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.06)
              : AppConstants.borderColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode
                        ? AppConstants.starlight
                        : AppConstants.textPrimary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.summary,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDarkMode
                        ? AppConstants.slateGray
                        : AppConstants.textSecondary,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.source,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode
                        ? AppConstants.primaryBlueCyan.withValues(alpha: 0.7)
                        : AppConstants.synapseIndigo.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppConstants.spacingM),

          // Save button
          if (item.isSaveable)
            GestureDetector(
              onTap: isSaved || isSaving ? null : () => _saveItem(item),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSaved
                      ? (isDarkMode
                          ? AppConstants.successColor.withValues(alpha: 0.15)
                          : AppConstants.successColor.withValues(alpha: 0.1))
                      : (isDarkMode
                          ? AppConstants.primaryBlueCyan.withValues(alpha: 0.15)
                          : AppConstants.synapseIndigo.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                ),
                child: isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isDarkMode
                              ? AppConstants.primaryBlueCyan
                              : AppConstants.synapseIndigo,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSaved ? Icons.check : Icons.add,
                            size: 16,
                            color: isSaved
                                ? AppConstants.successColor
                                : (isDarkMode
                                    ? AppConstants.primaryBlueCyan
                                    : AppConstants.synapseIndigo),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isSaved ? 'Saved' : 'Save',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSaved
                                  ? AppConstants.successColor
                                  : (isDarkMode
                                      ? AppConstants.primaryBlueCyan
                                      : AppConstants.synapseIndigo),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
