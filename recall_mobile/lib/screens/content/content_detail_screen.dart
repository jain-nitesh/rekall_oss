import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:dotted_border/dotted_border.dart';
import '../../models/content_item.dart';
import '../../providers/content_provider.dart';
import '../../providers/spaces_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';
import '../../widgets/auth_banner.dart';
import '../../widgets/share_to_space_sheet.dart';
import '../../providers/connections_provider.dart';
import '../brain/chat_screen.dart';

class ContentDetailScreen extends ConsumerStatefulWidget {
  final String contentId;

  const ContentDetailScreen({
    super.key,
    required this.contentId,
  });

  @override
  ConsumerState<ContentDetailScreen> createState() => _ContentDetailScreenState();
}

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen> {
  bool _isRefreshing = false;
  bool _isFetchingFromApi = true;
  Timer? _pollingTimer;
  ContentItem? _fetchedContent;
  String? _fetchError;
  final TextEditingController _notesController = TextEditingController();
  bool _isEditingNotes = false;
  bool _notesInitialized = false;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    // Start polling for items that are still being processed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPollingIfNeeded();
      _fetchContentIfNeeded();
    });
  }

  /// Fetch content from API if not found in providers
  Future<void> _fetchContentIfNeeded() async {
    final content = ref.read(contentByIdProvider(widget.contentId));
    if (content != null) {
      if (mounted) setState(() => _isFetchingFromApi = false);
      return;
    }
    if (!_isFetchingFromApi) {
      setState(() {
        _isFetchingFromApi = true;
        _fetchError = null;
      });
    }
    try {
      final fetchedContent = await ApiService().getContentById(widget.contentId);
      if (mounted) {
        setState(() {
          _fetchedContent = fetchedContent;
          _isFetchingFromApi = false;
          _fetchError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingFromApi = false;
          _fetchError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _notesController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _initVideoPlayer(String url) {
    if (_videoController != null) return;
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) setState(() => _isVideoInitialized = true);
      }).catchError((e) {
        debugPrint('Video init error: $e');
      });
  }

  /// Start polling timer if content is still being processed
  void _startPollingIfNeeded() {
    final content = ref.read(contentByIdProvider(widget.contentId));
    if (content != null && _shouldPoll(content)) {
      _startPolling();
    }
  }

  /// Check if we should poll for updates
  bool _shouldPoll(ContentItem content) {
    return content.aiStatus == AIStatus.pending ||
           content.aiStatus == AIStatus.processing;
  }

  /// Start polling timer (every 5 seconds)
  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      final content = ref.read(contentByIdProvider(widget.contentId));
      if (content == null || !_shouldPoll(content)) {
        // Stop polling if content is no longer pending/processing
        timer.cancel();
        return;
      }

      // Refresh content item
      await _refreshContent();
    });
  }

  /// Manually refresh content item
  Future<void> _refreshContent() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);

    try {
      await ref.read(contentProvider.notifier).refreshContentItem(widget.contentId);

      // Check if we need to start/stop polling based on new state
      final content = ref.read(contentByIdProvider(widget.contentId));
      if (content != null) {
        if (_shouldPoll(content) && _pollingTimer == null) {
          _startPolling();
        } else if (!_shouldPoll(content) && _pollingTimer != null) {
          _pollingTimer?.cancel();
          _pollingTimer = null;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentFromProvider = ref.watch(contentByIdProvider(widget.contentId));
    // Use fetched content as fallback if not in providers
    final content = contentFromProvider ?? _fetchedContent;
    final spacesContainingContent = ref.watch(spacesContainingContentProvider(widget.contentId));

    // Log analytics event for content detail opened
    if (content != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AnalyticsService().logContentDetailOpened(
          contentId: content.id,
          category: content.category.name,
          sourceApp: content.sourceApp.name,
        );
      });
    }

    // Show loading state while fetching from API
    if (content == null && _isFetchingFromApi) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: Text('Loading...', style: TextStyle(color: theme.colorScheme.onSurface)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show error state if fetch failed (network error)
    if (content == null && _fetchError != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: Text('Error', style: TextStyle(color: theme.colorScheme.onSurface)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'Could not load content',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your connection and try again.',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _fetchError = null;
                      _isFetchingFromApi = true;
                    });
                    _fetchContentIfNeeded();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show not-found state if fetch succeeded but returned null
    if (content == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          title: Text('Not Found', style: TextStyle(color: theme.colorScheme.onSurface)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off, size: 64, color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  'Content not found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This content may have been deleted.',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final topNavHeight = MediaQuery.of(context).padding.top + 64.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Main scrollable content with pull-to-refresh
          RefreshIndicator(
            onRefresh: _refreshContent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Spacer so content starts below fixed nav bar
                SizedBox(height: topNavHeight),

                // Hero Image with Gradient Overlay and Title
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      height: 240,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Hero image
                            if (content.heroImageUrl != null || content.effectiveThumbnailUrl != null)
                              Image.network(
                                content.heroImageUrl ?? content.effectiveThumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: AppConstants.primaryGradientEnhanced,
                                      ),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        AppConstants.categoryIcons[content.category] ?? Icons.bookmark,
                                        color: Colors.white.withValues(alpha: 0.25),
                                        size: 80,
                                      ),
                                    ),
                                  );
                                },
                              )
                            else
                              Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: AppConstants.primaryGradientEnhanced,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    AppConstants.categoryIcons[content.category] ?? Icons.bookmark,
                                    color: Colors.white.withValues(alpha: 0.25),
                                    size: 80,
                                  ),
                                ),
                              ),
                            // Gradient overlay
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Color(0x66000000),
                                    Color(0xCC000000),
                                  ],
                                  stops: [0.0, 0.5, 1.0],
                                ),
                              ),
                            ),
                            // Source badge (top-right)
                            Positioned(
                              top: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.public,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      content.sourceAppName ??
                                          AppConstants.sourceAppNames[content.sourceApp] ??
                                          'Unknown',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Title and metadata (bottom)
                            Positioned(
                              bottom: 20,
                              left: 20,
                              right: 20,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    content.title,
                                    style: GoogleFonts.inter(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.2,
                                      letterSpacing: -0.5,
                                      shadows: const [
                                        Shadow(
                                          color: Color(0x99000000),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.schedule,
                                        color: Colors.white.withValues(alpha: 0.85),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      if (content.readingTimeMinutes != null) ...[
                                        Text(
                                          '${content.readingTimeMinutes} min read',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white.withValues(alpha: 0.85),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          child: Text(
                                            '•',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                          ),
                                        ),
                                      ],
                                      Text(
                                        content.getRelativeTime(),
                                        style: GoogleFonts.inter(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: AppConstants.primaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // View Photo CTA (photo content only)
                            if (content.isMedia && content.contentType != ContentType.video)
                              Positioned(
                                bottom: 16,
                                right: 16,
                                child: GestureDetector(
                                  onTap: () => _showFullScreenImage(content.mediaUrl ?? content.effectiveThumbnailUrl ?? ''),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.open_in_full, color: Colors.white, size: 13),
                                        const SizedBox(width: 5),
                                        Text(
                                          'View Photo',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Tags (below hero image)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Show tags if available, otherwise show category
                        ...(content.tags.isNotEmpty
                            ? content.tags
                            : [content.categoryName ?? content.category.name]
                        ).map((tag) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Container(
                              height: 32,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  tag.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Video Viewer Section (photos are shown via hero card CTA)
                if (content.isMedia && content.contentType == ContentType.video && content.mediaUrl != null)
                  _buildMediaViewerSection(content, theme),

                // Auth Banner (show if auth required or blocked)
                if (content.fetchErrorType == FetchErrorType.authRequired ||
                    content.fetchErrorType == FetchErrorType.blocked)
                  Column(
                    children: [
                      AuthBanner(errorType: content.fetchErrorType!),
                      const SizedBox(height: 16),
                    ],
                  ),

                // AI Processing Status Banner
                if (content.aiStatus == AIStatus.pending || content.aiStatus == AIStatus.processing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppConstants.primaryColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  content.aiStatus == AIStatus.processing
                                      ? 'Generating AI Summary...'
                                      : 'AI Summary Pending',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Pull down to refresh',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (content.aiStatus == AIStatus.pending || content.aiStatus == AIStatus.processing)
                  const SizedBox(height: 16),

                // AI Summary Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Top gradient border
                        Container(
                          height: 4,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppConstants.primaryColor,
                                Colors.purple.shade500,
                                AppConstants.primaryColor,
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: AppConstants.primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.auto_awesome,
                                          color: AppConstants.primaryColor,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'AI Summary',
                                        style: GoogleFonts.inter(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppConstants.primaryColor.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppConstants.primaryColor.withValues(alpha: 0.2),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'REKALL AI',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppConstants.primaryColor,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Summary text
                              Text(
                                content.summary,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                                ),
                              ),
                              // Key Takeaways
                              if (content.keyTakeaways != null && content.keyTakeaways!.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'KEY TAKEAWAYS',
                                        style: GoogleFonts.inter(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ...content.keyTakeaways!.map((takeaway) {
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.check_circle,
                                                color: AppConstants.primaryColor,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  takeaway,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 14,
                                                    height: 1.5,
                                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Ask Brain about this
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  initialQuery: 'Tell me more about "${content.title}"',
                                ),
                              ),
                            );
                          },
                          icon: Icon(Icons.psychology, color: AppConstants.synapseIndigo),
                          label: Text(
                            'Ask Brain about this',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppConstants.synapseIndigo,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppConstants.synapseIndigo.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _BrainSuggestionChip(
                              label: 'Key insights?',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      initialQuery: 'What are the key insights from "${content.title}"?',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BrainSuggestionChip(
                              label: 'Related saves?',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      initialQuery: 'How does "${content.title}" relate to my other saves?',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // OCR Text Section (below AI summary for photo content)
                if (content.isMedia && content.ocrText != null && content.ocrText!.trim().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildOcrTextSection(content.ocrText!, theme),
                ],

                // My Notes Section
                const SizedBox(height: 24),
                _buildNotesSection(content, theme),

                // Saved to Space Section
                if (spacesContainingContent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DottedBorder(
                      options: RoundedRectDottedBorderOptions(
                        radius: const Radius.circular(12),
                        strokeWidth: 1,
                        dashPattern: const [6, 3],
                        color: theme.colorScheme.outline,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                            Row(
                              children: [
                              // Avatar stack (placeholder)
                              SizedBox(
                                width: 60,
                                height: 32,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: 0,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: theme.colorScheme.outline,
                                          border: Border.all(
                                            color: theme.scaffoldBackgroundColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.person,
                                          size: 16,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 24,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: theme.colorScheme.outline,
                                          border: Border.all(
                                            color: theme.scaffoldBackgroundColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '+${spacesContainingContent.length > 1 ? spacesContainingContent.length - 1 : 1}',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Saved to Space',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    spacesContainingContent.first.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () {
                              AppHaptics.buttonPress();
                              _showAddToSpaceDialog(context, ref, content.id);
                            },
                            child: Text(
                              'Edit',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppConstants.primaryColor,
                              ),
                            ),
                          ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],

                // Connected Reading section
                if (content.connectionCount > 0) ...[
                  const SizedBox(height: 32),
                  _buildConnectedReadingSection(content.id, theme),
                ],

                // Bottom padding for fixed button
                const SizedBox(height: 160),
                ],
              ),
            ),
          ),

          // Fixed top navigation bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
              ),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline,
                      width: 0.5,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    InkWell(
                      onTap: () {
                        AppHaptics.buttonPress();
                        context.pop();
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          color: theme.colorScheme.onSurface,
                          size: 20,
                        ),
                      ),
                    ),
                    // Share button
                    InkWell(
                      onTap: () {
                        AppHaptics.buttonPress();
                        _shareContent(content.url ?? '', content.title);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                        ),
                        child: Icon(
                          Icons.ios_share,
                          color: theme.colorScheme.onSurface,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Fixed bottom button with gradient fade
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Gradient fade
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
                        theme.scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                ),
                // Button container
                Container(
                  color: theme.scaffoldBackgroundColor,
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 16,
                    top: 0,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outline,
                          width: 0.5,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.only(top: 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: content.isMedia
                          ? ElevatedButton(
                              onPressed: () {
                                AppHaptics.buttonPress();
                                _shareContent(content.mediaUrl ?? '', content.title);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 8,
                                shadowColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    content.contentType == ContentType.video
                                        ? 'Share Video'
                                        : 'Share Photo',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.ios_share, size: 20),
                                ],
                              ),
                            )
                          : ElevatedButton(
                              onPressed: () {
                                AppHaptics.buttonPress();
                                _openInAppBrowser(context, content.url ?? '', content.title);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppConstants.primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 8,
                                shadowColor: AppConstants.primaryColor.withValues(alpha: 0.25),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Read Original Article',
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.open_in_new, size: 20),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openInAppBrowser(BuildContext context, String url, String title) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _shareContent(String url, String title) async {
    await SharePlus.instance.share(ShareParams(text: '$title\n$url'));
  }

  Widget _buildNotesSection(ContentItem content, ThemeData theme) {
    // Initialize notes controller with current content notes (only once)
    if (!_notesInitialized) {
      _notesController.text = content.notes ?? '';
      _notesInitialized = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isEditingNotes
                ? AppConstants.primaryColor.withValues(alpha: 0.5)
                : theme.colorScheme.outline,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'My Notes',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  if (_isEditingNotes)
                    TextButton(
                      onPressed: () {
                        _saveNotes(content.id);
                      },
                      child: Text(
                        'Done',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Notes text field
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: TextField(
                controller: _notesController,
                maxLines: null,
                minLines: 2,
                maxLength: 5000,
                onTap: () {
                  if (!_isEditingNotes) {
                    setState(() => _isEditingNotes = true);
                  }
                },
                onEditingComplete: () => _saveNotes(content.id),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
                decoration: InputDecoration(
                  hintText: 'Add your thoughts, reminders, or key points...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 15,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveNotes(String contentId) {
    final notes = _notesController.text.trim();
    ref.read(contentProvider.notifier).updateNotes(contentId, notes);
    FocusScope.of(context).unfocus();
    setState(() => _isEditingNotes = false);
    AppHaptics.buttonPress();
  }

  Widget _buildConnectedReadingSection(String contentId, ThemeData theme) {
    final connectionsAsync = ref.watch(connectionsByItemProvider(contentId));

    return connectionsAsync.when(
      data: (connections) {
        if (connections.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub, size: 20, color: AppConstants.primaryBlueCyan),
                  const SizedBox(width: 8),
                  Text(
                    'Connected Reading',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final conn = connections[index];
                    // Show the "other" item (the one that isn't the current item)
                    final otherItem = conn.sourceItem.id == contentId
                        ? conn.targetItem
                        : conn.sourceItem;

                    return GestureDetector(
                      onTap: () => context.push('/content/${otherItem.id}'),
                      child: Container(
                        width: 240,
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppConstants.primaryBlueCyan.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              otherItem.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const Spacer(),
                            if (conn.aiExplanation != null)
                              Text(
                                conn.aiExplanation!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppConstants.primaryBlueCyan,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              conn.similarityPercent,
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildMediaViewerSection(ContentItem content, ThemeData theme) {
    final isVideo = content.contentType == ContentType.video;

    if (isVideo) {
      // Initialize video player lazily
      _initVideoPlayer(content.mediaUrl!);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isVideo ? Icons.videocam : Icons.photo,
                  color: AppConstants.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isVideo ? 'Video' : 'Photo',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Media content
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: isVideo
                ? _buildVideoPlayer(theme)
                : _buildImageViewer(content.mediaUrl!, theme),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildImageViewer(String imageUrl, ThemeData theme) {
    return GestureDetector(
      onTap: () => _showFullScreenImage(imageUrl),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 400),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 200,
                color: theme.colorScheme.surface,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 48, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 8),
                      Text('Could not load image', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text('Tap to view', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlayer(ThemeData theme) {
    if (!_isVideoInitialized || _videoController == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
        setState(() {});
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
            if (!_videoController!.value.isPlaying)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            // Progress bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _videoController!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppConstants.primaryColor,
                  bufferedColor: Colors.white.withValues(alpha: 0.3),
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOcrTextSection(String ocrText, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.text_fields, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                'Extracted Text',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline, width: 1),
            ),
            child: SelectableText(
              ocrText,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.6,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showAddToSpaceDialog(BuildContext context, WidgetRef ref, String contentId) {
    final content = ref.read(contentByIdProvider(contentId));
    if (content == null) return;

    showShareToSpaceSheet(
      context,
      contentId: contentId,
      contentTitle: content.title,
    );
  }
}

class _BrainSuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BrainSuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppConstants.synapseIndigo.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppConstants.synapseIndigo.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.psychology, size: 14, color: AppConstants.synapseIndigo),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppConstants.synapseIndigo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
