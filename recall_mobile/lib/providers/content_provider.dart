import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/content_item.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';
import '../services/pending_shares_service.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';
import 'spaces_provider.dart';

/// Filter for content read/done status
enum ReadStatusFilter {
  all,
  unread,
  read;

  String get displayName {
    switch (this) {
      case ReadStatusFilter.all:
        return 'All';
      case ReadStatusFilter.unread:
        return 'Unread';
      case ReadStatusFilter.read:
        return 'Done';
    }
  }
}

/// Content state
class ContentState {
  final List<ContentItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final int currentPage;
  final bool hasMore;
  final int totalItems;
  final ReadStatusFilter readStatusFilter;

  const ContentState({
    required this.items,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.currentPage = 1,
    this.hasMore = false,
    this.totalItems = 0,
    this.readStatusFilter = ReadStatusFilter.unread,
  });

  ContentState copyWith({
    List<ContentItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    int? currentPage,
    bool? hasMore,
    int? totalItems,
    ReadStatusFilter? readStatusFilter,
  }) {
    return ContentState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage ?? this.errorMessage,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      totalItems: totalItems ?? this.totalItems,
      readStatusFilter: readStatusFilter ?? this.readStatusFilter,
    );
  }

  factory ContentState.initial() {
    return const ContentState(items: [], isLoading: true);
  }

  factory ContentState.loading() {
    return const ContentState(items: [], isLoading: true);
  }

  factory ContentState.loaded({
    required List<ContentItem> items,
    required int currentPage,
    required bool hasMore,
    required int totalItems,
    ReadStatusFilter readStatusFilter = ReadStatusFilter.unread,
  }) {
    return ContentState(
      items: items,
      isLoading: false,
      currentPage: currentPage,
      hasMore: hasMore,
      totalItems: totalItems,
      readStatusFilter: readStatusFilter,
    );
  }

  factory ContentState.error(String message) {
    return ContentState(
      items: const [],
      isLoading: false,
      errorMessage: message,
    );
  }
}

/// Content provider notifier
class ContentNotifier extends StateNotifier<ContentState> {
  final Ref ref;
  final _pendingSharesService = PendingSharesService();
  
  // Operation locking flags to prevent concurrent operations
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isProcessingPendingShares = false;
  
  // Track uploaded URLs to prevent duplicates
  final Set<String> _uploadedUrls = <String>{};
  static const String _keyUploadedUrls = 'uploaded_urls';

  ContentNotifier(this.ref) : super(ContentState.initial()) {
    // Load persisted uploaded URLs on initialization
    _loadUploadedUrls();

    // Load content once auth is ready (instead of arbitrary delay)
    _loadContentWhenAuthReady();

    // Listen for auth state changes
    ref.listen<AuthState>(authProvider, (previous, next) {
      // User just logged in - load content and process pending shares
      if (next.status == AuthStatus.authenticated &&
          (previous == null || previous.status != AuthStatus.authenticated)) {
        debugPrint('User authenticated, loading content and checking for pending shares...');
        loadContent();
        _processPendingShares();
      }

      // User just logged out - clear uploaded URLs tracking and reset state
      if (next.status == AuthStatus.unauthenticated &&
          previous != null && previous.status == AuthStatus.authenticated) {
        debugPrint('User logged out, clearing uploaded URLs tracking...');
        clearUploadedUrls(); // Fire and forget - async operation
        state = ContentState.initial();
      }
    });
  }

  /// Load content once auth state is determined (not stuck in loading).
  /// Replaces arbitrary 500ms delay with a check that works on both Android and iOS.
  Future<void> _loadContentWhenAuthReady() async {
    final authState = ref.read(authProvider);
    if (authState.status == AuthStatus.authenticated) {
      // Auth already ready, load immediately
      loadContent();
      return;
    }
    if (authState.status == AuthStatus.unauthenticated) {
      // Not logged in, nothing to load
      state = ContentState.initial().copyWith(isLoading: false);
      return;
    }
    // Auth is still loading — wait with increasing backoff (max ~3s total)
    for (final delay in [300, 500, 700, 1000]) {
      await Future.delayed(Duration(milliseconds: delay));
      final currentAuth = ref.read(authProvider);
      if (currentAuth.status == AuthStatus.authenticated) {
        loadContent();
        return;
      }
      if (currentAuth.status == AuthStatus.unauthenticated) {
        state = ContentState.initial().copyWith(isLoading: false);
        return;
      }
    }
    // If still loading after ~2.5s, stop showing loading spinner
    debugPrint('[ContentProvider] Auth still loading after backoff, stopping loading state');
    state = ContentState.initial().copyWith(isLoading: false);
  }

  /// Load uploaded URLs from SharedPreferences
  Future<void> _loadUploadedUrls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uploadedUrlsJson = prefs.getString(_keyUploadedUrls);
      
      if (uploadedUrlsJson != null && uploadedUrlsJson.isNotEmpty) {
        final List<dynamic> urlsList = json.decode(uploadedUrlsJson);
        _uploadedUrls.addAll(urlsList.map((url) => url.toString()).toSet());
        debugPrint('Loaded ${_uploadedUrls.length} persisted uploaded URLs');
      }
    } catch (e) {
      debugPrint('Error loading uploaded URLs: $e');
    }
  }

  /// Save uploaded URLs to SharedPreferences
  Future<void> _saveUploadedUrls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final urlsList = _uploadedUrls.toList();
      final uploadedUrlsJson = json.encode(urlsList);
      await prefs.setString(_keyUploadedUrls, uploadedUrlsJson);
      debugPrint('Saved ${_uploadedUrls.length} uploaded URLs to persistence');
    } catch (e) {
      debugPrint('Error saving uploaded URLs: $e');
    }
  }

  /// Process pending shares (single consolidated method with locking)
  Future<void> _processPendingShares() async {
    debugPrint('╔═══════════════════════════════════════════════════╗');
    debugPrint('║  PROCESSING PENDING SHARES                        ║');
    debugPrint('╚═══════════════════════════════════════════════════╝');
    debugPrint('Timestamp: ${DateTime.now().toIso8601String()}');

    // Prevent concurrent processing
    if (_isProcessingPendingShares) {
      debugPrint('⚠️  Pending shares processing already in progress, skipping...');
      debugPrint('This is expected if multiple triggers fire rapidly.');
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      debugPrint('❌ No user available for processing pending shares');
      debugPrint('User must be logged in to upload shares.');
      return;
    }

    debugPrint('✓ Current user: ${currentUser.id} (${currentUser.email})');

    _isProcessingPendingShares = true;
    try {
      debugPrint('Calling PendingSharesService.processPendingShares()...');
      final pendingShares = await _pendingSharesService.processPendingShares(currentUser.id);

      if (pendingShares.isEmpty) {
        debugPrint('✓ No pending shares found in SharedPreferences');
        debugPrint('This is normal if no shares were saved while app was closed.');
        return;
      }

      debugPrint('✓ Found ${pendingShares.length} pending share(s) in SharedPreferences:');
      for (int i = 0; i < pendingShares.length; i++) {
        debugPrint('  ${i + 1}. ${pendingShares[i].url}');
      }

      int successCount = 0;
      int failCount = 0;
      int skippedCount = 0;

      // Send each pending share to backend (with deduplication)
      for (int i = 0; i < pendingShares.length; i++) {
        final share = pendingShares[i];
        debugPrint('───────────────────────────────────────────────────');
        debugPrint('Processing share ${i + 1}/${pendingShares.length}: ${share.url}');

        // Check if URL was already uploaded or exists in current state
        if (_uploadedUrls.contains(share.url)) {
          debugPrint('⊘ Skipping - URL already uploaded (in memory cache)');
          skippedCount++;
          continue;
        }

        if (state.items.any((item) => item.url == share.url)) {
          debugPrint('⊘ Skipping - URL already exists in current state');
          skippedCount++;
          continue;
        }

        final isMedia = share.tags.contains('Media');
        final isValidUrl = share.url?.startsWith('http://') == true ||
            share.url?.startsWith('https://') == true;

        // Validate: must be either a proper URL or a media file path
        if (share.url == null || share.url!.isEmpty || (!isValidUrl && !isMedia)) {
          debugPrint('❌ Invalid URL format, skipping: ${share.url}');
          failCount++;
          continue;
        }

        try {
          debugPrint('⟳ Uploading to backend...');
          debugPrint('  ${isMedia ? 'File' : 'URL'}: ${share.url}');
          debugPrint('  Title: ${share.title}');

          final ContentItem savedItem;
          if (isMedia) {
            // iOS media share — upload file via multipart
            final isVideo = share.tags.contains('video') ||
                (share.url?.endsWith('.mp4') == true) ||
                (share.url?.endsWith('.mov') == true);
            savedItem = await ApiService().uploadMedia(
              filePath: share.url ?? '',
              contentType: isVideo ? 'video' : 'image',
            );
          } else {
            // URL/text share — ingest via URL endpoint
            savedItem = await ApiService().ingestContent(
              url: share.url ?? '',
              title: share.title,
              sourceAppName: share.sourceAppName,
              sourceAppPackage: share.sourceAppPackage,
              sharedText: share.summary,
            );
          }

          debugPrint('✓ Backend upload successful!');
          debugPrint('  Backend ID: ${savedItem.id}');
          debugPrint('  Backend created_at: ${savedItem.createdAt}');

          // Track uploaded URL in memory and persist it
          _uploadedUrls.add(share.url ?? '');
          await _saveUploadedUrls();

          // Use backend's ContentItem (which has correct created_at timestamp) instead of optimistic one
          final updatedItems = [savedItem, ...state.items];
          state = state.copyWith(
            items: updatedItems,
            totalItems: state.totalItems + 1,
          );

          debugPrint('✓ Added to state (total items: ${state.totalItems})');
          successCount++;
        } catch (e, stackTrace) {
          debugPrint('❌ Failed to upload to backend!');
          debugPrint('  Error type: ${e.runtimeType}');
          debugPrint('  Error message: $e');
          if (e.toString().contains('SocketException') || e.toString().contains('TimeoutException')) {
            debugPrint('  Likely cause: Network connectivity issue');
          } else if (e.toString().contains('401') || e.toString().contains('403')) {
            debugPrint('  Likely cause: Authentication issue');
          }
          debugPrint('  Stack trace (first 3 lines):');
          final stackLines = stackTrace.toString().split('\n').take(3);
          for (final line in stackLines) {
            debugPrint('    $line');
          }

          failCount++;
          // Re-save failed shares for retry later
          debugPrint('  ⟳ Re-saving to SharedPreferences for retry...');
          await _pendingSharesService.savePendingShare(share.url ?? '', share.createdAt.millisecondsSinceEpoch);
        }
      }

      debugPrint('───────────────────────────────────────────────────');
      debugPrint('SUMMARY:');
      debugPrint('  ✓ Successful uploads: $successCount');
      debugPrint('  ❌ Failed uploads: $failCount');
      debugPrint('  ⊘ Skipped (duplicates): $skippedCount');
      debugPrint('  Total processed: ${pendingShares.length}');

      // Clear persisted uploaded URLs after successful sync
      // Backend is now the source of truth for deduplication
      if (successCount > 0) {
        debugPrint('✓ Clearing persisted uploaded_urls cache (backend is now source of truth)...');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_keyUploadedUrls);
        debugPrint('✓ Cleared uploaded_urls from SharedPreferences');

        // Note: Keep in-memory _uploadedUrls intact - it will be refreshed from backend on next loadContent()
      }



      // Show toast notification
      if (successCount > 0) {
        final message = successCount == 1
            ? '✓ Uploaded 1 pending share'
            : '✓ Uploaded $successCount pending shares';
        ToastHelper.showSuccess(message);
        debugPrint('Showing success toast: $message');
      }

      if (failCount > 0) {
        ToastHelper.showError('Failed to upload $failCount share(s). Will retry later.');
        debugPrint('Showing error toast for $failCount failed uploads');
      }

      debugPrint('╚═══════════════════════════════════════════════════╝');
    } catch (e, stackTrace) {
      debugPrint('❌ CRITICAL ERROR processing pending shares: $e');
      debugPrint('Stack trace:');
      debugPrint(stackTrace.toString());
      ToastHelper.showError('Error processing pending shares');
    } finally {
      _isProcessingPendingShares = false;
      debugPrint('Released processing lock (_isProcessingPendingShares = false)');
    }
  }

  /// Load first page of content from backend API
  Future<void> loadContent() async {
    // Prevent concurrent loading
    if (_isLoading) {
      debugPrint('Content loading already in progress, skipping...');
      return;
    }

    _isLoading = true;
    // Keep existing items visible during refresh (don't flash empty) so
    // contentByIdProvider continues to resolve while the API call is in-flight.
    // Items are replaced atomically when the response arrives.
    final isInitialLoad = state.items.isEmpty;
    state = state.copyWith(isLoading: true, items: isInitialLoad ? [] : null);

    try {
      debugPrint('📡 Calling API: getAllContent(page: 1, pageSize: 20)');

      // Build filters based on read status
      final filters = <String, dynamic>{};
      if (state.readStatusFilter != ReadStatusFilter.all) {
        filters['read_status'] = state.readStatusFilter == ReadStatusFilter.read
            ? 'read'
            : 'unread';
      }

      // Call real API to get first page (20 items)
      final response = await ApiService().getAllContent(
        page: 1,
        pageSize: 20,
        filters: filters.isNotEmpty ? filters : null,
      );
      debugPrint('✅ API Response received: ${response.keys}');
      debugPrint('   - Items count: ${(response['content'] as List).length}');
      debugPrint('   - Total: ${response['total']}');
      debugPrint('   - Has more: ${response['has_more']}');

      final items = response['content'] as List<ContentItem>;
      final total = response['total'] as int;
      final hasMore = response['has_more'] as bool;

      // Update uploaded URLs set with current items to prevent duplicates
      _uploadedUrls.addAll(items.where((item) => item.url != null).map((item) => item.url!));
      // Persist the updated URLs
      await _saveUploadedUrls();

      state = ContentState.loaded(
        items: items,
        currentPage: 1,
        hasMore: hasMore,
        totalItems: total,
        readStatusFilter: state.readStatusFilter,
      );

      debugPrint('✅ Content state updated: ${items.length} items loaded');

      // After loading content, check for pending shares immediately
      // This handles the case when app is launched fresh (not resumed) and user is already authenticated
      // The auth listener only fires on state change, not initial state
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        debugPrint('Content loaded, checking for pending shares on initialization...');
        // Process in background without blocking
        _processPendingShares();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR loading content: $e');
      debugPrint('Stack trace: $stackTrace');
      state = ContentState.error('Failed to load content: $e');
    } finally {
      _isLoading = false;
      debugPrint('🔓 Content loading completed (_isLoading = false)');
    }
  }

  /// Load more content (next page)
  Future<void> loadMoreContent() async {
    // Prevent concurrent loading more
    if (_isLoadingMore || !state.hasMore) {
      return;
    }

    _isLoadingMore = true;
    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final filters = <String, dynamic>{};
      if (state.readStatusFilter != ReadStatusFilter.all) {
        filters['read_status'] = state.readStatusFilter == ReadStatusFilter.read
            ? 'read'
            : 'unread';
      }
      final response = await ApiService().getAllContent(
        page: nextPage,
        pageSize: 20,
        filters: filters.isNotEmpty ? filters : null,
      );
      final newItems = response['content'] as List<ContentItem>;
      final hasMore = response['has_more'] as bool;
      final total = response['total'] as int;

      // Update uploaded URLs set with new items
      _uploadedUrls.addAll(newItems.where((item) => item.url != null).map((item) => item.url!));
      // Persist the updated URLs
      await _saveUploadedUrls();

      // Append new items to existing list
      final updatedItems = [...state.items, ...newItems];

      state = state.copyWith(
        items: updatedItems,
        currentPage: nextPage,
        hasMore: hasMore,
        totalItems: total,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Failed to load more content: $e',
      );
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Add new content item (legacy method, use addContentOptimistically instead)
  Future<void> addContent(ContentItem item) async {
    try {
      final updatedItems = [item, ...state.items];
      state = state.copyWith(items: updatedItems);
      if (item.url != null) {
        _uploadedUrls.add(item.url!);
      }

      // MVP: In production, this would sync to the backend
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to add content: $e');
    }
  }

  /// Remove an item by ID — used to clean up failed optimistic inserts
  void removeOptimisticItem(String itemId) {
    final updatedItems = state.items.where((item) => item.id != itemId).toList();
    state = state.copyWith(items: updatedItems);
  }

  /// Add content item locally (no backend call, used after upload-media returns)
  void addContentLocally(ContentItem item) {
    final updatedItems = [item, ...state.items];
    state = state.copyWith(items: updatedItems);
  }

  /// Add content optimistically (immediately update UI, then sync with backend)
  /// NOTE: Does NOT mark URL as uploaded - that happens only after successful backend upload
  Future<void> addContentOptimistically(ContentItem item) async {
    try {
      // Check for duplicates in current state only (don't check _uploadedUrls here)
      // Skip duplicate check for media content (no URL to compare)
      if (item.url != null && state.items.any((existing) => existing.url == item.url)) {
        debugPrint('Content with URL already exists in state, skipping: ${item.url}');
        return;
      }

      // Add to state immediately for instant UI update
      // Do NOT add to _uploadedUrls yet - wait for successful backend upload
      final updatedItems = [item, ...state.items];
      state = state.copyWith(
        items: updatedItems,
        totalItems: state.totalItems + 1,
      );
    } catch (e) {
      debugPrint('Error adding content optimistically: $e');
      state = state.copyWith(errorMessage: 'Failed to add content: $e');
    }
  }

  /// Mark URL as successfully uploaded (called after backend confirms upload)
  Future<void> markUrlAsUploaded(String url) async {
    if (!_uploadedUrls.contains(url)) {
      _uploadedUrls.add(url);
      await _saveUploadedUrls();
      debugPrint('Marked URL as uploaded: $url');
    }
  }

  /// Replace optimistic item with backend-saved item.
  /// Matches by URL for URL-type shares, or by [optimisticId] for media shares
  /// (where the backend returns url=null so URL matching fails).
  void replaceOptimisticItem(ContentItem backendItem, {String? optimisticId}) {
    final updatedItems = state.items.map((item) {
      final matchesUrl = backendItem.url != null &&
          backendItem.url!.isNotEmpty &&
          item.url == backendItem.url;
      final matchesId = optimisticId != null && item.id == optimisticId;
      if (matchesUrl || matchesId) {
        debugPrint('Replacing optimistic item (ID: ${item.id}) with backend item (ID: ${backendItem.id})');
        return backendItem;
      }
      return item;
    }).toList();

    state = state.copyWith(items: updatedItems);
  }

  /// Delete content item
  Future<void> deleteContent(String contentId) async {
    try {
      // Find the item to get its URL for tracking cleanup
      final itemToDelete = state.items.firstWhere(
        (item) => item.id == contentId,
        orElse: () => throw Exception('Content not found'),
      );

      // Call API to delete
      await ApiService().deleteContent(contentId);

      // Remove URL from tracking set
      _uploadedUrls.remove(itemToDelete.url);

      // Update local state
      final updatedItems = state.items.where((item) => item.id != contentId).toList();
      state = state.copyWith(items: updatedItems);
    } catch (e) {
      state = state.copyWith(errorMessage: 'Failed to delete content: $e');
    }
  }

  /// Mark content as done
  Future<void> markAsDone(String contentId) async {
    try {
      // Update local state immediately (optimistic update)
      final updatedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isDone: true);
        }
        return item;
      }).toList();
      state = state.copyWith(items: updatedItems);

      await ApiService().updateContent(contentId, isDone: true);
    } catch (e) {
      // Revert optimistic update on failure
      final revertedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isDone: false);
        }
        return item;
      }).toList();
      state = state.copyWith(
        items: revertedItems,
        errorMessage: 'Failed to mark as done: $e',
      );
    }
  }

  /// Undo mark as done
  Future<void> undoMarkAsDone(String contentId) async {
    try {
      // Update local state immediately (optimistic update)
      final updatedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isDone: false);
        }
        return item;
      }).toList();
      state = state.copyWith(items: updatedItems);

      await ApiService().updateContent(contentId, isDone: false);
    } catch (e) {
      // Revert optimistic update on failure
      final revertedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isDone: true);
        }
        return item;
      }).toList();
      state = state.copyWith(
        items: revertedItems,
        errorMessage: 'Failed to undo mark as done: $e',
      );
    }
  }

  /// Set read status filter and reload content
  Future<void> setReadStatusFilter(ReadStatusFilter filter) async {
    if (state.readStatusFilter == filter) return;
    state = state.copyWith(readStatusFilter: filter);
    await loadContent();
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String contentId) async {
    try {
      // Find current state before toggling
      final currentItem = state.items.firstWhere((item) => item.id == contentId);
      final newFavorite = !currentItem.isFavorite;

      // Update local state immediately (optimistic update)
      final updatedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isFavorite: newFavorite);
        }
        return item;
      }).toList();
      state = state.copyWith(items: updatedItems);

      await ApiService().updateContent(contentId, isFavorite: newFavorite);
    } catch (e) {
      // Revert optimistic update on failure
      final revertedItems = state.items.map((item) {
        if (item.id == contentId) {
          return item.copyWith(isFavorite: !item.isFavorite);
        }
        return item;
      }).toList();
      state = state.copyWith(
        items: revertedItems,
        errorMessage: 'Failed to toggle favorite: $e',
      );
    }
  }

  /// Update notes for a content item
  Future<void> updateNotes(String contentId, String notes) async {
    // Optimistic update
    final updatedItems = state.items.map((item) {
      if (item.id == contentId) {
        return item.copyWith(notes: notes);
      }
      return item;
    }).toList();
    state = state.copyWith(items: updatedItems);

    try {
      await ApiService().updateContent(contentId, notes: notes);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to save notes: $e',
      );
    }
  }

  /// Get content by ID
  ContentItem? getContentById(String id) {
    try {
      return state.items.firstWhere((item) => item.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Refresh content (reset to page 1)
  Future<void> refresh() async {
    // If already loading, skip to prevent concurrent operations
    if (_isLoading) {
      debugPrint('Refresh skipped - content loading already in progress');
      return;
    }
    // Reset to first page
    await loadContent();
  }

  /// Process pending shares immediately (called when app resumes)
  /// This is a public wrapper for _processPendingShares()
  Future<void> processPendingSharesImmediately() async {
    await _processPendingShares();
  }

  /// Clear uploaded URLs tracking (useful on logout)
  Future<void> clearUploadedUrls() async {
    _uploadedUrls.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyUploadedUrls);
      debugPrint('Cleared persisted uploaded URLs');
    } catch (e) {
      debugPrint('Error clearing uploaded URLs: $e');
    }
  }

  /// Refresh a single content item by ID (used for polling AI status updates)
  Future<void> refreshContentItem(String contentId) async {
    try {
      debugPrint('Refreshing content item: $contentId');

      // Fetch the latest version from API
      final updatedItem = await ApiService().getContentById(contentId);

      // Update the item in the state
      final updatedItems = state.items.map((item) {
        if (item.id == contentId) {
          return updatedItem;
        }
        return item;
      }).toList();

      state = state.copyWith(items: updatedItems);

      debugPrint('✓ Content item refreshed: $contentId');
      debugPrint('  AI Status: ${updatedItem.aiStatus?.name}');
      debugPrint('  Summary: ${updatedItem.summary.length > 50 ? updatedItem.summary.substring(0, 50) : updatedItem.summary}...');
    } catch (e) {
      debugPrint('❌ Error refreshing content item: $e');
      // Don't update error state for individual item refresh failures
    }
  }
}

/// Content provider
final contentProvider = StateNotifierProvider<ContentNotifier, ContentState>((ref) {
  return ContentNotifier(ref);
});

/// All content items provider (derived)
final allContentProvider = Provider<List<ContentItem>>((ref) {
  return ref.watch(contentProvider).items;
});

/// Recent saves provider (last 15 items)
final recentSavesProvider = Provider<List<ContentItem>>((ref) {
  final allContent = ref.watch(allContentProvider);
  return allContent.take(AppConstants.recentSavesLimit).toList();
});

/// Memory Feed State for individual sections
class MemoryFeedState {
  final List<ContentItem> items;
  final bool isLoading;
  final bool isLoadingMore;
  final String? errorMessage;
  final int currentPage;
  final bool hasMore;
  final int totalItems;

  const MemoryFeedState({
    required this.items,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.errorMessage,
    this.currentPage = 1,
    this.hasMore = false,
    this.totalItems = 0,
  });

  MemoryFeedState copyWith({
    List<ContentItem>? items,
    bool? isLoading,
    bool? isLoadingMore,
    String? errorMessage,
    int? currentPage,
    bool? hasMore,
    int? totalItems,
  }) {
    return MemoryFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage ?? this.errorMessage,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      totalItems: totalItems ?? this.totalItems,
    );
  }

  factory MemoryFeedState.initial() {
    return const MemoryFeedState(items: [], isLoading: true);
  }

  factory MemoryFeedState.loaded({
    required List<ContentItem> items,
    required int currentPage,
    required bool hasMore,
    required int totalItems,
  }) {
    return MemoryFeedState(
      items: items,
      isLoading: false,
      currentPage: currentPage,
      hasMore: hasMore,
      totalItems: totalItems,
    );
  }
}

/// Memory Feed Notifier for individual sections
class MemoryFeedNotifier extends StateNotifier<MemoryFeedState> {
  final int days;
  bool _isLoading = false;
  bool _isLoadingMore = false;

  MemoryFeedNotifier(this.days) : super(MemoryFeedState.initial()) {
    loadContent();
  }

  Future<void> loadContent() async {
    if (_isLoading) return;

    _isLoading = true;
    state = MemoryFeedState.initial();

    try {
      final response = await ApiService().getMemoryFeedContent(
        days,
        page: 1,
        pageSize: 20,
      );
      final items = response['content'] as List<ContentItem>;
      final total = response['total'] as int;
      final hasMore = response['has_more'] as bool;

      state = MemoryFeedState.loaded(
        items: items,
        currentPage: 1,
        hasMore: hasMore,
        totalItems: total,
      );
    } catch (e) {
      state = MemoryFeedState(
        items: const [],
        isLoading: false,
        errorMessage: 'Failed to load memory feed: $e',
      );
    } finally {
      _isLoading = false;
    }
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !state.hasMore) return;

    _isLoadingMore = true;
    state = state.copyWith(isLoadingMore: true);

    try {
      final nextPage = state.currentPage + 1;
      final response = await ApiService().getMemoryFeedContent(
        days,
        page: nextPage,
        pageSize: 20,
      );
      final newItems = response['content'] as List<ContentItem>;
      final hasMore = response['has_more'] as bool;
      final total = response['total'] as int;

      final updatedItems = [...state.items, ...newItems];

      state = state.copyWith(
        items: updatedItems,
        currentPage: nextPage,
        hasMore: hasMore,
        totalItems: total,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        errorMessage: 'Failed to load more: $e',
      );
    } finally {
      _isLoadingMore = false;
    }
  }
}

/// Memory feed providers for each section
final memoryFeed7DaysProvider = StateNotifierProvider<MemoryFeedNotifier, MemoryFeedState>((ref) {
  return MemoryFeedNotifier(7);
});

final memoryFeed30DaysProvider = StateNotifierProvider<MemoryFeedNotifier, MemoryFeedState>((ref) {
  return MemoryFeedNotifier(30);
});

final memoryFeed1YearProvider = StateNotifierProvider<MemoryFeedNotifier, MemoryFeedState>((ref) {
  return MemoryFeedNotifier(365);
});

/// Content by ID provider - searches in main content and all spaces
final contentByIdProvider = Provider.family<ContentItem?, String>((ref, id) {
  // First, try to find in main content provider
  final allContent = ref.watch(allContentProvider);
  try {
    return allContent.firstWhere((item) => item.id == id);
  } catch (e) {
    // If not found in main content, search in all spaces
    final spacesState = ref.watch(spacesProvider);
    for (final space in spacesState.spaces) {
      try {
        final spaceItem = space.contentItems.firstWhere((item) => item.id == id);
        // Convert SpaceContentItem to ContentItem
        return spaceItem.toContentItem();
      } catch (e) {
        // Continue searching in other spaces
        continue;
      }
    }
    // Not found in any space either
    return null;
  }
});
