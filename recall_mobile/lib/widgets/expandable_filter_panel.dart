import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/filter_option.dart';
import '../providers/search_provider.dart';
import '../utils/constants.dart';
import 'search_filter_chip.dart';

/// Expandable filter panel for search page.
///
/// Shows two collapsible sections:
/// 1. Categories (fixed + user-created categories)
/// 2. Sources (source apps)
///
/// Each section displays filter chips with counts and supports multi-select.
class ExpandableFilterPanel extends ConsumerStatefulWidget {
  final FilterOptions filterOptions;

  const ExpandableFilterPanel({
    required this.filterOptions,
    super.key,
  });

  @override
  ConsumerState<ExpandableFilterPanel> createState() =>
      _ExpandableFilterPanelState();
}

class _ExpandableFilterPanelState
    extends ConsumerState<ExpandableFilterPanel> {
  bool _categoriesExpanded = false;
  bool _sourcesExpanded = false;

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
      decoration: BoxDecoration(
        color: AppConstants.white,
        borderRadius: BorderRadius.circular(AppConstants.radiusL),
        border: Border.all(color: AppConstants.borderColor),
      ),
      child: Column(
        children: [
          // Categories section
          _buildFilterSection(
            title: 'Categories',
            icon: Icons.category,
            isExpanded: _categoriesExpanded,
            onToggle: () =>
                setState(() => _categoriesExpanded = !_categoriesExpanded),
            activeCount: searchState.categoryFilters.length +
                searchState.userCategoryFilters.length,
            child: _buildCategoryFilters(),
          ),

          // Divider between sections
          Divider(height: 1, color: AppConstants.borderColor),

          // Sources section
          _buildFilterSection(
            title: 'Sources',
            icon: Icons.apps,
            isExpanded: _sourcesExpanded,
            onToggle: () =>
                setState(() => _sourcesExpanded = !_sourcesExpanded),
            activeCount: searchState.sourceAppFilters.length,
            child: _buildSourceFilters(),
          ),
        ],
      ),
    );
  }

  /// Build a filter section with header and collapsible content
  Widget _buildFilterSection({
    required String title,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required int activeCount,
    required Widget child,
  }) {
    return Column(
      children: [
        // Section header
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            child: Row(
              children: [
                // Icon
                Icon(icon, size: 20, color: AppConstants.electricIndigo),
                const SizedBox(width: AppConstants.spacingM),

                // Title
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppConstants.textPrimary,
                  ),
                ),

                // Active count badge
                if (activeCount > 0) ...[
                  const SizedBox(width: AppConstants.spacingS),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingS,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.electricIndigo,
                      borderRadius:
                          BorderRadius.circular(AppConstants.radiusS),
                    ),
                    child: Text(
                      activeCount.toString(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppConstants.white,
                      ),
                    ),
                  ),
                ],

                const Spacer(),

                // Expand/collapse arrow
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppConstants.textSecondary,
                ),
              ],
            ),
          ),
        ),

        // Section content (shown when expanded)
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: AppConstants.spacingM,
              right: AppConstants.spacingM,
              bottom: AppConstants.spacingM,
            ),
            child: child,
          ),
      ],
    );
  }

  /// Build category filters (fixed + user categories)
  Widget _buildCategoryFilters() {
    final searchState = ref.watch(searchProvider);

    // Combine fixed categories and user categories
    final allCategoryOptions = [
      ...widget.filterOptions.categories,
      ...widget.filterOptions.userCategories,
    ];

    if (allCategoryOptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
        child: Text(
          'No categories available',
          style: TextStyle(
            fontSize: 14,
            color: AppConstants.textSecondary,
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppConstants.spacingS,
      runSpacing: AppConstants.spacingS,
      children: [
        // Fixed categories
        ...widget.filterOptions.categories.map((option) {
          return SearchFilterChip(
            label: option.displayName,
            count: option.count,
            isSelected: searchState.categoryFilters.contains(option.value),
            onTap: () => ref
                .read(searchProvider.notifier)
                .toggleCategoryFilter(option.value),
          );
        }),

        // User categories (with custom colors)
        ...widget.filterOptions.userCategories.map((option) {
          Color? chipColor;
          if (option.color != null) {
            try {
              // Parse color hex string (e.g., "#FF5733" -> Color)
              chipColor = Color(
                int.parse(option.color!.replaceFirst('#', '0xFF')),
              );
            } catch (e) {
              // If color parsing fails, use default
              chipColor = null;
            }
          }

          return SearchFilterChip(
            label: option.displayName,
            count: option.count,
            isSelected:
                searchState.userCategoryFilters.contains(option.value),
            onTap: () => ref
                .read(searchProvider.notifier)
                .toggleUserCategoryFilter(option.value),
            color: chipColor,
          );
        }),
      ],
    );
  }

  /// Build source app filters
  Widget _buildSourceFilters() {
    final searchState = ref.watch(searchProvider);

    if (widget.filterOptions.sources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppConstants.spacingM),
        child: Text(
          'No sources available',
          style: TextStyle(
            fontSize: 14,
            color: AppConstants.textSecondary,
          ),
        ),
      );
    }

    return Wrap(
      spacing: AppConstants.spacingS,
      runSpacing: AppConstants.spacingS,
      children: widget.filterOptions.sources.map((option) {
        return SearchFilterChip(
          label: option.displayName,
          count: option.count,
          isSelected: searchState.sourceAppFilters.contains(option.value),
          onTap: () => ref
              .read(searchProvider.notifier)
              .toggleSourceAppFilter(option.value),
        );
      }).toList(),
    );
  }
}
