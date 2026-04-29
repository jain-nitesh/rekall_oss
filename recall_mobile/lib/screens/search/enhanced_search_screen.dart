import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/search_provider.dart';
import '../../providers/search_history_provider.dart';
import '../../models/content_item.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/content_card.dart';
import '../../widgets/empty_state.dart';
import '../../providers/onboarding_progress_provider.dart';

/// Enhanced search screen with filter chips and smart suggestions
class EnhancedSearchScreen extends ConsumerStatefulWidget {
  const EnhancedSearchScreen({super.key});

  @override
  ConsumerState<EnhancedSearchScreen> createState() => _EnhancedSearchScreenState();
}

class _EnhancedSearchScreenState extends ConsumerState<EnhancedSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus search bar when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _performSearch() {
    if (_searchController.text.trim().isEmpty) return;

    AppHaptics.light();
    ref.read(searchProvider.notifier).setQuery(_searchController.text);
    ref.read(searchHistoryProvider.notifier).saveSearch(_searchController.text);
    ref.read(onboardingProgressProvider.notifier).markSearchUsed();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final searchResults = ref.watch(searchResultsProvider);
    final searchHistoryState = ref.watch(searchHistoryProvider);
    final hasQuery = _searchController.text.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Search',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(isDark),

          // Filter chips (always visible)
          _buildCategoryFilters(isDark, searchState),
          const SizedBox(height: 4),
          _buildSourceFilters(isDark, searchState),
          const SizedBox(height: 8),

          // Content area
          Expanded(
            child: (hasQuery || searchState.hasFilters)
                ? _buildSearchResults(searchResults)
                : _buildEmptyState(searchHistoryState, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _performSearch(),
        onChanged: (query) {
          setState(() {}); // Rebuild to show/hide clear button
          if (query.isNotEmpty) {
            ref.read(searchProvider.notifier).setQuery(query);
          } else {
            ref.read(searchProvider.notifier).clearQuery();
          }
        },
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
        ),
        cursorColor: AppConstants.primaryBlueCyan,
        decoration: InputDecoration(
          hintText: 'Search your saved content...',
          hintStyle: TextStyle(
            color: AppConstants.slateGray,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: AppConstants.slateGray,
            size: 22,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: AppConstants.slateGray),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                    });
                    ref.read(searchProvider.notifier).clearQuery();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilters(bool isDark, SearchState searchState) {
    final categories = [
      ('Technology', Icons.computer),
      ('Design', Icons.palette),
      ('Business', Icons.business),
      ('Science', Icons.science),
      ('Productivity', Icons.rocket_launch),
      ('Education', Icons.school),
      ('Entertainment', Icons.movie),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, icon) = categories[index];
          final isSelected = searchState.categoryFilters.contains(label.toLowerCase());

          return GestureDetector(
            onTap: () {
              AppHaptics.selection();
              ref.read(searchProvider.notifier).toggleCategoryFilter(label.toLowerCase());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.primaryBlueCyan
                    : (isDark ? AppConstants.surfaceDark : AppConstants.dividerColor),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppConstants.primaryBlueCyan
                      : (isDark ? AppConstants.starlight.withValues(alpha: 0.1) : AppConstants.borderColor),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppConstants.slateGray : AppConstants.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? AppConstants.slateGray : AppConstants.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSourceFilters(bool isDark, SearchState searchState) {
    final sources = [
      ('YouTube', Icons.play_circle_outline),
      ('Reddit', Icons.forum_outlined),
      ('Twitter', Icons.tag),
      ('LinkedIn', Icons.work_outline),
      ('GitHub', Icons.code),
      ('Medium', Icons.article_outlined),
      ('News', Icons.newspaper),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sources.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, icon) = sources[index];
          final isSelected = searchState.sourceAppFilters.contains(label.toLowerCase());

          return GestureDetector(
            onTap: () {
              AppHaptics.selection();
              ref.read(searchProvider.notifier).toggleSourceAppFilter(label.toLowerCase());
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppConstants.synapseIndigo
                    : (isDark ? AppConstants.surfaceDark : AppConstants.dividerColor),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppConstants.synapseIndigo
                      : (isDark ? AppConstants.starlight.withValues(alpha: 0.1) : AppConstants.borderColor),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppConstants.slateGray : AppConstants.textSecondary),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? AppConstants.slateGray : AppConstants.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchResults(AsyncValue<List<ContentItem>> searchResults) {
    return searchResults.when(
      data: (results) => results.isEmpty
          ? const EmptyState(
              icon: Icons.search_off,
              title: 'No Results Found',
              message: 'Try different keywords or filters',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppConstants.spacingM),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final item = results[index];
                return ContentCard.full(
                  item: item,
                  onTap: () {
                    context.push('/content/${item.id}');
                  },
                );
              },
            ),
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Search Error',
        message: error.toString(),
      ),
    );
  }

  Widget _buildEmptyState(SearchHistoryState searchHistoryState, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Searches section
          if (searchHistoryState.items.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(searchHistoryProvider.notifier).clearHistory();
                  },
                  child: Text(
                    'Clear',
                    style: TextStyle(color: AppConstants.primaryBlueCyan),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingS),
            ...searchHistoryState.items.map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.history,
                color: AppConstants.slateGray,
              ),
              title: Text(
                item.query,
                style: TextStyle(
                  color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                ),
              ),
              trailing: Text(
                item.getRelativeTime(),
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.slateGray,
                ),
              ),
              onTap: () {
                _searchController.text = item.query;
                _performSearch();
              },
            )),
          ] else ...[
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.search,
                    size: 64,
                    color: AppConstants.slateGray.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Search your memory',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search by keywords or use the filters\nabove to browse by category or source.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppConstants.slateGray,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
