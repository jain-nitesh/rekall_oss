import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/spaces_provider.dart';
import '../../models/shared_space.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/app_logo_header.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/premium_button.dart';
import '../../widgets/animations.dart';

class SpacesListScreen extends ConsumerStatefulWidget {
  const SpacesListScreen({super.key});

  @override
  ConsumerState<SpacesListScreen> createState() => _SpacesListScreenState();
}

class _SpacesListScreenState extends ConsumerState<SpacesListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SharedSpace> _filterSpaces(List<SharedSpace> spaces) {
    var filtered = spaces;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      filtered = filtered.where((space) {
        return space.name.toLowerCase().contains(_searchController.text.toLowerCase()) ||
               space.description.toLowerCase().contains(_searchController.text.toLowerCase());
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final spacesState = ref.watch(spacesProvider);
    final allSpaces = ref.watch(allSpacesProvider);
    final filteredSpaces = _filterSpaces(allSpaces);
    final pinnedSpaces = filteredSpaces.where((space) => space.isPinned).toList();
    final unpinnedSpaces = filteredSpaces.where((space) => !space.isPinned).toList();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
      ),
      floatingActionButton: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppConstants.primaryColor,
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryColor.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              AppHaptics.buttonPress();
              context.push('/spaces/create');
            },
            borderRadius: BorderRadius.circular(28),
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      ),
      body: spacesState.isLoading
          ? _buildLoadingSkeleton()
          : spacesState.errorMessage != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Error Loading Spaces',
                  message: spacesState.errorMessage!,
                  useGradientTitle: true,
                  action: PremiumButton.primary(
                    onPressed: () {
                      AppHaptics.buttonPress();
                      ref.read(spacesProvider.notifier).refresh();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 20),
                        SizedBox(width: AppConstants.spacingS),
                        Text('Retry'),
                      ],
                    ),
                  ),
                )
              : allSpaces.isEmpty
                  ? EmptyState(
                      icon: Icons.folder_outlined,
                      title: 'No Spaces Yet',
                      message: 'Create a space to collaborate and organize content with others',
                      useGradientTitle: true,
                      action: PremiumButton.primary(
                        onPressed: () {
                          AppHaptics.buttonPress();
                          context.push('/spaces/create');
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 20),
                            SizedBox(width: AppConstants.spacingS),
                            Text('Create Space'),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // Search bar
                        _buildSearchBar(),

                        // Spaces list
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () => ref.read(spacesProvider.notifier).refresh(),
                            color: AppConstants.primaryColor,
                            child: filteredSpaces.isEmpty
                                ? ListView(
                                    children: [
                                      const SizedBox(height: AppConstants.spacingXXL),
                                      EmptyState(
                                        icon: Icons.search_off,
                                        title: 'No Spaces Found',
                                        message: 'Try different search terms or filters',
                                      ),
                                    ],
                                  )
                                : ListView(
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
                                    children: [
                                      // Pinned section
                                      if (pinnedSpaces.isNotEmpty) ...[
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            AppConstants.spacingL,
                                            AppConstants.spacingM,
                                            AppConstants.spacingL,
                                            AppConstants.spacingS,
                                          ),
                                          child: Text(
                                            'Pinned',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        ...pinnedSpaces.asMap().entries.map(
                                          (entry) => StaggeredListAnimation(
                                            index: entry.key,
                                            child: _buildSpaceCard(context, entry.value),
                                          ),
                                        ),
                                      ],

                                      // Recent Spaces section
                                      if (unpinnedSpaces.isNotEmpty) ...[
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            AppConstants.spacingL,
                                            AppConstants.spacingM,
                                            AppConstants.spacingL,
                                            AppConstants.spacingS,
                                          ),
                                          child: Text(
                                            'Recent Spaces',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        ...unpinnedSpaces.asMap().entries.map(
                                          (entry) => StaggeredListAnimation(
                                            index: entry.key + pinnedSpaces.length,
                                            child: _buildSpaceCard(context, entry.value),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {}); // Rebuild to apply filter
        },
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Search your spaces...',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            size: 22,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingL,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Color _parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) buffer.write('FF');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }

  Widget _buildSpaceCard(BuildContext context, SharedSpace space) {
    // Use accent color from model, or fall back to hash-based color
    final Color spaceColor;
    if (space.accentColor != null && space.accentColor!.isNotEmpty) {
      spaceColor = _parseHexColor(space.accentColor!);
    } else {
      final colorIndex = space.id.hashCode % AppConstants.primaryGradient.length;
      spaceColor = AppConstants.primaryGradient[colorIndex];
    }

    // Use different card layouts for pinned vs recent
    if (space.isPinned) {
      return _buildPinnedCard(context, space, spaceColor);
    } else {
      return _buildRecentCard(context, space, spaceColor);
    }
  }

  // Large pinned card with full details
  Widget _buildPinnedCard(BuildContext context, SharedSpace space, Color spaceColor) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: AppConstants.spacingS,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.buttonPress();
            context.push('/spaces/${space.id}');
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with icon, title, and pin
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        // Icon
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                spaceColor.withValues(alpha: 0.9),
                                spaceColor,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: space.emoji != null && space.emoji!.isNotEmpty
                                ? Text(space.emoji!, style: const TextStyle(fontSize: 24))
                                : const Icon(Icons.campaign, size: 24, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              space.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              space.getRelativeTime(),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Icon(
                      Icons.push_pin,
                      size: 20,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Divider
                Container(
                  height: 1,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                // Footer with avatars and item count
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Collaborator avatars
                    Row(
                      children: [
                        ...List.generate(
                          (space.memberCount > 2 ? 2 : space.memberCount).toInt(),
                          (index) => Container(
                            margin: EdgeInsets.only(right: index < 1 ? 0 : 8),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppConstants.primaryGradient[index % AppConstants.primaryGradient.length].withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.colorScheme.surface, width: 2),
                            ),
                            child: const Icon(
                              Icons.person,
                              size: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        if (space.memberCount > 2)
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outline,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.colorScheme.surface, width: 2),
                            ),
                            child: Center(
                              child: Text(
                                '+${space.memberCount - 2}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Item count badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.description,
                            size: 14,
                            color: AppConstants.primaryColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${space.contentCount} items',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Compact recent card with horizontal layout
  Widget _buildRecentCard(BuildContext context, SharedSpace space, Color spaceColor) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingL,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            AppHaptics.buttonPress();
            context.push('/spaces/${space.id}');
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        spaceColor.withValues(alpha: 0.9),
                        spaceColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: space.emoji != null && space.emoji!.isNotEmpty
                        ? Text(space.emoji!, style: const TextStyle(fontSize: 26))
                        : Icon(_getSpaceIcon(space), size: 24, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              space.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // AI Ready badge
                          if (space.aiReady)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 16,
                                  color: AppConstants.primaryColor,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'READY',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppConstants.primaryColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Metadata row
                      Row(
                        children: [
                          // Privacy badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.outline,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              space.isPublic ? 'Shared' : 'Private',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Metadata
                          Expanded(
                            child: Text(
                              _getSpaceMetadata(space),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Chevron
                Icon(
                  Icons.chevron_right,
                  size: 24,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getSpaceIcon(SharedSpace space) {
    // Simple logic to assign icons based on space name or type
    final name = space.name.toLowerCase();
    if (name.contains('read')) return Icons.menu_book;
    if (name.contains('financial') || name.contains('q3')) return Icons.bar_chart;
    if (name.contains('trip') || name.contains('travel')) return Icons.landscape;
    if (name.contains('recipe') || name.contains('food')) return Icons.restaurant;
    return Icons.folder;
  }

  String _getSpaceMetadata(SharedSpace space) {
    if (space.memberCount > 1) {
      return '${space.memberCount} collaborators • ${space.contentCount} items';
    } else {
      return '${space.contentCount} items saved';
    }
  }

  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingM,
            vertical: AppConstants.spacingS,
          ),
          height: 200,
          decoration: BoxDecoration(
            color: AppConstants.dividerColor,
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
          ),
        );
      },
    );
  }
}
