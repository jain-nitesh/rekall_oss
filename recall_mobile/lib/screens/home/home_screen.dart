import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/content_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/time_based_content_provider.dart';
import '../../utils/constants.dart';
import '../../widgets/app_logo_header.dart';
import '../../widgets/content_card.dart';
import '../../widgets/content_card_skeleton.dart';
import '../../widgets/animations.dart';
import '../../widgets/onboarding_checklist.dart';
import '../../widgets/premium_appbar.dart';
import '../../widgets/quick_capture_sheet.dart';
import '../../widgets/brain_suggestions_section.dart';
import '../../providers/onboarding_progress_provider.dart';
import '../../utils/haptics.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  bool _hasCheckedPendingShares = false;
  final ScrollController _scrollController = ScrollController();
  Timer? _pollingTimer;
  DateTime? _pollingStartTime;
  ReadStatusFilter _selectedFilter = ReadStatusFilter.unread;

  void _onFilterChanged(ReadStatusFilter filter) {
    if (_selectedFilter == filter) return;
    setState(() => _selectedFilter = filter);
    final readStatus = filter == ReadStatusFilter.all
        ? null
        : filter == ReadStatusFilter.read
            ? 'read'
            : 'unread';
    ref.read(justInContentProvider.notifier).setReadStatus(readStatus);
    ref.read(todayContentProvider.notifier).setReadStatus(readStatus);
    ref.read(yesterdayContentProvider.notifier).setReadStatus(readStatus);
    ref.read(olderContentProvider.notifier).setReadStatus(readStatus);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check for pending shares when screen first loads (only once)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasCheckedPendingShares) {
        _hasCheckedPendingShares = true;
        _checkPendingShares();
      }
      // Start polling for pending items
      _startPollingIfNeeded();
    });

    // Listen to scroll events for auto-loading
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pollingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Check if any content items are still being processed
  bool _hasPendingItems() {
    final allContent = ref.read(allContentProvider);
    return allContent.any((item) =>
      item.aiStatus == AIStatus.pending ||
      item.aiStatus == AIStatus.processing
    );
  }

  /// Start polling timer if there are pending items
  void _startPollingIfNeeded() {
    if (_hasPendingItems()) {
      _startPolling();
    }
  }

  /// Start polling timer (every 5 seconds, max 2 minutes)
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingStartTime = DateTime.now();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final timedOut = DateTime.now().difference(_pollingStartTime!).inMinutes >= 2;
      if (!_hasPendingItems() || timedOut) {
        timer.cancel();
        _pollingTimer = null;
        _pollingStartTime = null;
        return;
      }

      // Refresh all time-based sections
      ref.read(justInContentProvider.notifier).refresh();
      ref.read(todayContentProvider.notifier).refresh();
      ref.read(yesterdayContentProvider.notifier).refresh();
    });
  }

  void _onScroll() {
    // Auto-load more when user scrolls within 200px of bottom
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more for each time section if they have more content
      final justInContent = ref.read(justInContentProvider);
      final todayContent = ref.read(todayContentProvider);
      final yesterdayContent = ref.read(yesterdayContentProvider);
      final olderContent = ref.read(olderContentProvider);

      if (justInContent.hasMore && !justInContent.isLoadingMore) {
        ref.read(justInContentProvider.notifier).loadMore();
      }
      if (todayContent.hasMore && !todayContent.isLoadingMore) {
        ref.read(todayContentProvider.notifier).loadMore();
      }
      if (yesterdayContent.hasMore && !yesterdayContent.isLoadingMore) {
        ref.read(yesterdayContentProvider.notifier).loadMore();
      }
      if (olderContent.hasMore && !olderContent.isLoadingMore) {
        ref.read(olderContentProvider.notifier).loadMore();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app comes to foreground, check for pending shares and refresh feed
    if (state == AppLifecycleState.resumed) {
      debugPrint('HomeScreen: App resumed, checking for pending shares and refreshing feed...');
      _checkPendingShares();

      // Refresh main content provider to keep it in sync with time-based providers
      // This ensures content detail screen can find items by ID
      ref.read(contentProvider.notifier).refresh();

      // Refresh all time-based content sections
      ref.read(justInContentProvider.notifier).refresh();
      ref.read(todayContentProvider.notifier).refresh();
      ref.read(yesterdayContentProvider.notifier).refresh();
      ref.read(olderContentProvider.notifier).refresh();

      // Restart polling if there are pending items
      _startPollingIfNeeded();
    }
  }

  void _checkPendingShares() {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser != null) {
      debugPrint('HomeScreen: Checking for pending shares...');
      ref.read(contentProvider.notifier).processPendingSharesImmediately();
    }
  }

  @override
  Widget build(BuildContext context) {
    final justInContent = ref.watch(justInContentProvider);
    final todayContent = ref.watch(todayContentProvider);
    final yesterdayContent = ref.watch(yesterdayContentProvider);
    final olderContent = ref.watch(olderContentProvider);
    final currentUser = ref.watch(currentUserProvider);

    // Check if we have any content matching the current filter
    final hasFilteredContent = justInContent.items.isNotEmpty ||
                          todayContent.items.isNotEmpty ||
                          yesterdayContent.items.isNotEmpty ||
                          olderContent.items.isNotEmpty;

    // Check if user has ANY content at all (regardless of filter)
    // so we always show filter chips even when current filter returns empty
    final hasAnyContent = ref.watch(allContentProvider).isNotEmpty;

    return Scaffold(
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
            tooltip: 'Search',
          ),
        ],
      ),
      body: (justInContent.isLoading && justInContent.items.isEmpty &&
             todayContent.isLoading && todayContent.items.isEmpty &&
             yesterdayContent.isLoading && yesterdayContent.items.isEmpty &&
             olderContent.isLoading && olderContent.items.isEmpty)
          ? _buildLoadingSkeleton()
          : RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  ref.read(justInContentProvider.notifier).refresh(),
                  ref.read(todayContentProvider.notifier).refresh(),
                  ref.read(yesterdayContentProvider.notifier).refresh(),
                  ref.read(olderContentProvider.notifier).refresh(),
                ]);
              },
              color: AppConstants.primaryBlueCyan,
              backgroundColor: AppConstants.surfaceDark,
              displacement: 60,
              strokeWidth: 2.5,
              child: !hasAnyContent
                  ? ListView(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      children: [
                        const SizedBox(height: AppConstants.spacingS),
                        // Onboarding checklist for new users
                        if (ref.watch(onboardingVisibleProvider))
                          const OnboardingChecklist(),
                        // Capture prompt for empty feed
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spacingL,
                            vertical: 48,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.bookmark_add_outlined,
                                size: 80,
                                color: AppConstants.slateGray.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: AppConstants.spacingL),
                              Text(
                                'Your memory starts here',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? AppConstants.starlight
                                      : AppConstants.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: AppConstants.spacingM),
                              Text(
                                'Share a link from any app, paste a URL, or\ncapture a photo to get started.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: AppConstants.slateGray,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: AppConstants.spacingXXL),
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    AppHaptics.buttonPress();
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => const QuickCaptureSheet(),
                                    );
                                  },
                                  icon: const Icon(Icons.add, size: 22),
                                  label: const Text(
                                    'Add Your First Item',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppConstants.primaryBlueCyan,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      children: [
                        const SizedBox(height: AppConstants.spacingS),

                        _buildFilterChips(),
                        const SizedBox(height: AppConstants.spacingS),

                        // Onboarding checklist (also visible when content exists)
                        if (ref.watch(onboardingVisibleProvider))
                          const OnboardingChecklist(),

                        // AI-powered suggestions from Brain
                        const BrainSuggestionsSection(),

                        // Show empty filter message when content exists but current filter returns nothing
                        if (!hasFilteredContent)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.spacingM,
                              vertical: AppConstants.spacingXXL,
                            ),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    _selectedFilter == ReadStatusFilter.unread
                                        ? Icons.check_circle_outline
                                        : Icons.inbox_outlined,
                                    size: 48,
                                    color: AppConstants.slateGray,
                                  ),
                                  const SizedBox(height: AppConstants.spacingM),
                                  Text(
                                    _selectedFilter == ReadStatusFilter.unread
                                        ? 'All caught up!'
                                        : _selectedFilter == ReadStatusFilter.read
                                            ? 'No done items yet'
                                            : 'No content found',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppConstants.slateGray,
                                    ),
                                  ),
                                  const SizedBox(height: AppConstants.spacingS),
                                  Text(
                                    _selectedFilter == ReadStatusFilter.unread
                                        ? 'Try switching to "All" or "Done" to see your content'
                                        : 'Try switching to "All" to see all your content',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppConstants.slateGray.withValues(alpha: 0.7),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // JUST IN Section (last 3 hours)
                        if (justInContent.items.isNotEmpty || justInContent.isLoading)
                          _buildTimeSection(
                            context,
                            'JUST IN',
                            justInContent,
                            showPulseDot: true,
                          ),

                        // TODAY Section (midnight to now, excluding just_in)
                        if (todayContent.items.isNotEmpty || todayContent.isLoading)
                          _buildTimeSection(
                            context,
                            'TODAY',
                            todayContent,
                            showPulseDot: false,
                          ),

                        // YESTERDAY Section (previous calendar date)
                        if (yesterdayContent.items.isNotEmpty || yesterdayContent.isLoading)
                          _buildTimeSection(
                            context,
                            'YESTERDAY',
                            yesterdayContent,
                            showPulseDot: false,
                          ),

                        // OLDER Section (everything beyond yesterday)
                        if (olderContent.items.isNotEmpty || olderContent.isLoading)
                          _buildTimeSection(
                            context,
                            'OLDER',
                            olderContent,
                            showPulseDot: false,
                          ),

                        const SizedBox(height: AppConstants.spacingXXL),
                      ],
                    ),
            ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          boxShadow: [
            BoxShadow(
              color: AppConstants.primaryBlueCyan.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          heroTag: 'fab_home_add',
          onPressed: () {
            showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const QuickCaptureSheet(),
          );
          },
          backgroundColor: AppConstants.primaryBlueCyan,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingM,
      ),
      child: Row(
        children: ReadStatusFilter.values.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: AppConstants.spacingS),
            child: ChoiceChip(
              label: Text(filter.displayName),
              selected: isSelected,
              onSelected: (_) => _onFilterChanged(filter),
              selectedColor: AppConstants.primaryBlueCyan,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : AppConstants.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              backgroundColor: AppConstants.surfaceDark,
              side: BorderSide(
                color: isSelected
                    ? AppConstants.primaryBlueCyan
                    : AppConstants.borderColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusM),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeSection(
    BuildContext context,
    String title,
    TimeBasedContentState state,
    {bool showPulseDot = false}
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.spacingM,
            AppConstants.spacingL,
            AppConstants.spacingM,
            AppConstants.spacingS,
          ),
          child: Row(
            children: [
              // Pulse dot for "JUST IN"
              if (showPulseDot) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryBlueCyan,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppConstants.primaryBlueCyan.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.slateGray,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (state.isLoading && state.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppConstants.spacingL),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          )
        else if (state.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            child: Text(
              'No content for this time period',
              style: TextStyle(
                color: AppConstants.textSecondary,
                fontSize: 14,
              ),
            ),
          )
        else
          ...state.items.asMap().entries.map(
            (entry) => StaggeredListAnimation(
              key: ValueKey(entry.value.id),
              index: entry.key,
              child: ContentCard.full(
                item: entry.value,
                onTap: () {
                  context.push('/content/${entry.value.id}');
                },
              ),
            ),
          ),
        const SizedBox(height: AppConstants.spacingM),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Welcome message skeleton
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 28,
                  width: 200,
                  decoration: BoxDecoration(
                    color: AppConstants.dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingS),
                Container(
                  height: 16,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppConstants.dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),

          // Recent Saves skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
            child: Container(
              height: 24,
              width: 150,
              decoration: BoxDecoration(
                color: AppConstants.dividerColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          SizedBox(
            height: 250,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: AppConstants.spacingL),
              itemCount: 3,
              itemBuilder: (context, index) {
                return ContentCardSkeleton.compact();
              },
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),

          // Memory Feed skeletons
          ...List.generate(2, (index) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
                  child: Container(
                    height: 24,
                    width: 150,
                    decoration: BoxDecoration(
                      color: AppConstants.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: AppConstants.spacingL),
                    itemCount: 2,
                    itemBuilder: (context, index) {
                      return ContentCardSkeleton.compact();
                    },
                  ),
                ),
                const SizedBox(height: AppConstants.spacingL),
              ],
            );
          }),
        ],
      ),
    );
  }

}
