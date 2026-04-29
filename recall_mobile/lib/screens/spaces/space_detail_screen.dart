import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/spaces_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/animations.dart';
import '../../widgets/content_card.dart';

class SpaceDetailScreen extends ConsumerStatefulWidget {
  final String spaceId;

  const SpaceDetailScreen({
    super.key,
    required this.spaceId,
  });

  @override
  ConsumerState<SpaceDetailScreen> createState() => _SpaceDetailScreenState();
}

class _SpaceDetailScreenState extends ConsumerState<SpaceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final space = ref.watch(spaceByIdProvider(widget.spaceId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Load space details if not already loaded or if content items are empty
    if (space == null || (space.contentItems.isEmpty && space.contentCount > 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (space == null) {
          ref.read(spacesProvider.notifier).loadSpaceDetails(widget.spaceId);
        } else if (space.contentItems.isEmpty && space.contentCount > 0) {
          ref.read(spacesProvider.notifier).loadSpaceDetails(widget.spaceId);
        }
      });
    }

    if (space == null) {
      return Scaffold(
        backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.backgroundColor,
        body: _buildLoadingSkeleton(isDark),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.backgroundColor,
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(spacesProvider.notifier).refreshSpaceContent(widget.spaceId);
        },
        child: CustomScrollView(
              slivers: [
                // Custom App Bar
                SliverAppBar(
                  floating: true,
                  pinned: true,
                  backgroundColor: isDark
                      ? AppConstants.backgroundDark.withValues(alpha: 0.95)
                      : AppConstants.backgroundColor.withValues(alpha: 0.95),
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      AppHaptics.buttonPress();
                      // If there's a route to pop (came from within app), pop it
                      // Otherwise (came from deep link), go to home/feed
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                  ),
                  title: Text(
                    space.name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                  ),
                  centerTitle: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'Manage Space',
                      onPressed: () {
                        AppHaptics.buttonPress();
                        context.push('/spaces/${widget.spaceId}/info');
                      },
                    ),
                  ],
                ),

                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildCollaboratorsSection(space, isDark),
                      const SizedBox(height: 16),
                      Divider(
                        color: isDark
                            ? AppConstants.starlight.withValues(alpha: 0.1)
                            : AppConstants.textPrimary.withValues(alpha: 0.1),
                        height: 1,
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'RECENT CONTENT',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: isDark
                                ? AppConstants.starlight.withValues(alpha: 0.8)
                                : AppConstants.textPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                // Content list
                if (space.contentItems.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.bookmark_outline,
                      title: 'No Content Yet',
                      message: 'Add content to this space using the share button',
                      useGradientTitle: true,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= space.contentItems.length) return null;

                          final spaceItem = space.contentItems[index];
                          final contentItem = spaceItem.toContentItem();

                          return StaggeredListAnimation(
                            index: index,
                            child: ContentCard.full(
                              item: contentItem,
                              onTap: () {
                                context.push('/content/${contentItem.id}');
                              },
                              enableSwipeToDismiss: false,
                            ),
                          );
                        },
                        childCount: space.contentItems.length,
                      ),
                    ),
                  ),

              ],
          ),
        ),
    );
  }

  Widget _buildCollaboratorsSection(dynamic space, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COLLABORATORS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: isDark
                  ? AppConstants.starlight.withValues(alpha: 0.8)
                  : AppConstants.textPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Avatar stack
              ...List.generate(
                space.members.length > 3 ? 3 : space.members.length,
                (index) {
                  final member = space.members[index];
                  return Transform.translate(
                    offset: Offset(-index * 12.0, 0),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppConstants.backgroundDark : Colors.white,
                          width: 2,
                        ),
                        gradient: const LinearGradient(
                          colors: AppConstants.primaryGradient,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          member.name[0].toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              // Add button
              Transform.translate(
                offset: Offset(-space.members.length.toDouble() * 12.0, 0),
                child: GestureDetector(
                  onTap: () {
                    AppHaptics.buttonPress();
                    context.push('/spaces/${widget.spaceId}/info');
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppConstants.primaryColor.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppConstants.primaryColor.withValues(alpha: 0.5),
                        width: 1,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Icon(
                      Icons.add,
                      color: AppConstants.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildLoadingSkeleton(bool isDark) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          pinned: true,
          backgroundColor: isDark
              ? AppConstants.backgroundDark.withValues(alpha: 0.95)
              : AppConstants.backgroundColor.withValues(alpha: 0.95),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: Container(
            width: 150,
            height: 20,
            decoration: BoxDecoration(
              color: isDark
                  ? AppConstants.starlight.withValues(alpha: 0.1)
                  : AppConstants.textPrimary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          centerTitle: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  height: 120,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppConstants.starlight.withValues(alpha: 0.05)
                        : AppConstants.textPrimary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              },
              childCount: 5,
            ),
          ),
        ),
      ],
    );
  }

}
