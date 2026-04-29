import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/search_provider.dart';
import '../../models/content_item.dart';
import '../../services/analytics_service.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/content_card.dart';
import '../../widgets/content_card_skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_bottom_sheet.dart';
import '../../widgets/animations.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final searchResults = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        title: 'Search',
      ),
      body: Column(
        children: [
          // Search bar with gradient border
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            color: AppConstants.white,
            child: _SearchBar(
              focusNode: _searchFocusNode,
              isFocused: _isSearchFocused,
              onChanged: (query) => ref.read(searchProvider.notifier).setQuery(query),
              onClear: () {
                AppHaptics.buttonPress();
                ref.read(searchProvider.notifier).clearQuery();
              },
              hasQuery: searchState.hasQuery,
            ),
          ),

          // Filters
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Category filter
                _buildFilterChip(
                  context,
                  ref,
                  label: searchState.categoryFilters.isNotEmpty ||
                          searchState.userCategoryFilters.isNotEmpty
                      ? (searchState.categoryFilters.length +
                                  searchState.userCategoryFilters.length >
                              1)
                          ? 'Categories (${searchState.categoryFilters.length + searchState.userCategoryFilters.length})'
                          : searchState.categoryFilters.isNotEmpty
                              ? _capitalize(searchState.categoryFilters.first)
                              : 'User Category'
                      : 'Category',
                  isActive: searchState.categoryFilters.isNotEmpty ||
                      searchState.userCategoryFilters.isNotEmpty,
                  onTap: () => _showCategoryFilter(context, ref),
                ),
                const SizedBox(width: AppConstants.spacingS),

                // Date range filter
                _buildFilterChip(
                  context,
                  ref,
                  label: searchState.dateRangeFilter.displayName,
                  isActive: searchState.dateRangeFilter != DateRange.allTime,
                  onTap: () => _showDateRangeFilter(context, ref),
                ),
                const SizedBox(width: AppConstants.spacingS),

                // Source app filter
                _buildFilterChip(
                  context,
                  ref,
                  label: searchState.sourceAppFilters.isNotEmpty
                      ? searchState.sourceAppFilters.length > 1
                          ? 'Sources (${searchState.sourceAppFilters.length})'
                          : _capitalize(searchState.sourceAppFilters.first)
                      : 'Source',
                  isActive: searchState.sourceAppFilters.isNotEmpty,
                  onTap: () => _showSourceAppFilter(context, ref),
                ),
                const SizedBox(width: AppConstants.spacingS),

                // Clear filters
                if (searchState.hasFilters)
                  _buildFilterChip(
                    context,
                    ref,
                    label: 'Clear',
                    isActive: false,
                    icon: Icons.clear,
                    onTap: () {
                      ref.read(searchProvider.notifier).clearFilters();
                    },
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Results
          Expanded(
            child: searchResults.when(
              data: (results) => results.isEmpty
                  ? EmptyState(
                      icon: searchState.hasQuery || searchState.hasFilters
                          ? Icons.search_off
                          : Icons.search,
                      title: searchState.hasQuery || searchState.hasFilters
                          ? 'No Results Found'
                          : 'Search Your Content',
                      message: searchState.hasQuery || searchState.hasFilters
                          ? 'Try different keywords or filters'
                          : 'Enter keywords to search your saved content',
                      useGradientTitle: true,
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final item = results[index];
                        return StaggeredListAnimation(
                          index: index,
                          child: ContentCard.full(
                            item: item,
                            onTap: () {
                              AppHaptics.buttonPress();
                              // Log analytics event
                              AnalyticsService().logSearchResultClicked(item.id, index);

                              context.push('/content/${item.id}');
                            },
                          ),
                        );
                      },
                    ),
              loading: () => ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 5,
                itemBuilder: (context, index) {
                  return ContentCardSkeleton.full();
                },
              ),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Search Error',
                message: error.toString(),
                useGradientTitle: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required bool isActive,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: isActive
            ? const LinearGradient(
                colors: AppConstants.primaryGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: isActive
            ? null
            : Border.all(
                color: AppConstants.borderColor,
                width: AppConstants.borderWidthThin,
              ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.selection();
            onTap();
          },
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: AppConstants.spacingS,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: AppConstants.iconTiny,
                    color: isActive ? Colors.white : AppConstants.textPrimary,
                  ),
                  const SizedBox(width: AppConstants.spacingXS),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? Colors.white : AppConstants.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryFilter(BuildContext context, WidgetRef ref) {
    AppHaptics.buttonPress();
    showPremiumBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Category',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            ...ContentCategory.values.map((category) {
              return ListTile(
                title: Text(AppConstants.categoryNames[category]!),
                leading: Icon(
                  AppConstants.categoryIcons[category],
                  color: AppConstants.categoryColors[category],
                ),
                onTap: () {
                  AppHaptics.selection();
                  ref.read(searchProvider.notifier).toggleCategoryFilter(category.name);
                  Navigator.pop(context);
                },
              );
            }),
            ListTile(
              title: const Text('Clear Filter'),
              leading: const Icon(Icons.clear),
              onTap: () {
                AppHaptics.buttonPress();
                ref.read(searchProvider.notifier).clearFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDateRangeFilter(BuildContext context, WidgetRef ref) {
    AppHaptics.buttonPress();
    showPremiumBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Date',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            ...DateRange.values.map((range) {
              return ListTile(
                title: Text(range.displayName),
                onTap: () {
                  AppHaptics.selection();
                  ref.read(searchProvider.notifier).setDateRangeFilter(range);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSourceAppFilter(BuildContext context, WidgetRef ref) {
    AppHaptics.buttonPress();
    showPremiumBottomSheet(
      context: context,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter by Source',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            ...SourceApp.values.map((source) {
              return ListTile(
                title: Text(AppConstants.sourceAppNames[source]!),
                leading: Icon(
                  AppConstants.sourceAppIcons[source],
                  color: AppConstants.sourceAppColors[source],
                ),
                onTap: () {
                  AppHaptics.selection();
                  ref.read(searchProvider.notifier).toggleSourceAppFilter(source.name);
                  Navigator.pop(context);
                },
              );
            }),
            ListTile(
              title: const Text('Clear Filter'),
              leading: const Icon(Icons.clear),
              onTap: () {
                AppHaptics.buttonPress();
                ref.read(searchProvider.notifier).clearFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to capitalize first letter
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

/// Search bar widget with gradient border animation
class _SearchBar extends StatelessWidget {
  final FocusNode focusNode;
  final bool isFocused;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasQuery;

  const _SearchBar({
    required this.focusNode,
    required this.isFocused,
    required this.onChanged,
    required this.onClear,
    required this.hasQuery,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: isFocused
            ? const LinearGradient(
                colors: AppConstants.primaryGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
      ),
      padding: EdgeInsets.all(isFocused ? 2 : 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : AppConstants.white,
          borderRadius: BorderRadius.circular(
            isFocused ? AppConstants.radiusL - 2 : AppConstants.radiusL,
          ),
        ),
        child: TextField(
          focusNode: focusNode,
          onChanged: onChanged,
          style: TextStyle(
            color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            fontSize: 15,
          ),
          cursorColor: AppConstants.primaryBlueCyan,
          decoration: InputDecoration(
            hintText: 'Search your saved content...',
            hintStyle: TextStyle(
              color: AppConstants.textSecondary.withValues(alpha: 0.6),
            ),
            prefixIcon: Icon(
              Icons.search,
              color: isFocused ? AppConstants.primaryColor : AppConstants.textSecondary,
            ),
            suffixIcon: hasQuery
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: onClear,
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusL),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusL),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusL - 2),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: isDarkMode ? AppConstants.backgroundDark : AppConstants.backgroundColor,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: AppConstants.spacingM,
            ),
          ),
        ),
      ),
    );
  }
}
