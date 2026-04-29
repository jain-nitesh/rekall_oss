import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/brain_provider.dart';
import '../../utils/constants.dart';
import '../../utils/theme.dart';
import '../../utils/haptics.dart';
import '../../models/wiki_page.dart';
import '../../models/health_check.dart';
import '../../widgets/app_logo_header.dart';
import '../../widgets/premium_appbar.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import 'chat_screen.dart';
import 'wiki_page_screen.dart';
import 'entity_detail_screen.dart';

class BrainScreen extends ConsumerStatefulWidget {
  const BrainScreen({super.key});

  @override
  ConsumerState<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends ConsumerState<BrainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(wikiPagesProvider.notifier).loadPages(status: 'published');
      ref.read(entitiesProvider.notifier).loadEntities();
      ref.read(conversationsProvider.notifier).loadConversations();
      ref.read(healthChecksProvider.notifier).loadChecks();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh data when app comes back to foreground
      ref.read(wikiPagesProvider.notifier).loadPages(status: 'published');
      ref.read(entitiesProvider.notifier).loadEntities();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUser = ref.watch(currentUserProvider);
    final convState = ref.watch(conversationsProvider);
    final wikiState = ref.watch(wikiPagesProvider);
    final entityState = ref.watch(entitiesProvider);

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: PremiumAppBar.glassmorphic(
        titleWidget: AppLogoHeader(currentUser: currentUser),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(wikiPagesProvider.notifier).loadPages(status: 'published'),
            ref.read(entitiesProvider.notifier).loadEntities(),
            ref.read(conversationsProvider.notifier).loadConversations(),
          ]);
        },
        color: AppConstants.primaryBlueCyan,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Health insights carousel
              _buildHealthInsights(isDark),

              // Chat prompt hero section
              _buildChatPrompt(isDark, convState),

              const SizedBox(height: 24),

              // Recent conversations
              if (convState.conversations.isNotEmpty)
                _buildRecentConversations(isDark, convState),

              // Wiki pages section
              _buildWikiSection(isDark, wikiState),

              // Entities section
              _buildEntitiesSection(isDark, entityState),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthInsights(bool isDark) {
    final healthState = ref.watch(healthChecksProvider);
    final checks = healthState.checks;

    if (checks.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: checks.length > 5 ? 5 : checks.length,
        itemBuilder: (context, index) {
          final check = checks[index];
          return _HealthInsightChip(
            check: check,
            isDark: isDark,
            onDismiss: () {
              ref.read(healthChecksProvider.notifier).dismiss(check.id);
            },
          );
        },
      ),
    );
  }

  Widget _buildChatPrompt(bool isDark, ConversationsState convState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Ask your memory',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Get cited answers from everything you\'ve saved',
            style: TextStyle(
              fontSize: 14,
              color: AppConstants.slateGray,
            ),
          ),
          const SizedBox(height: 16),

          // Tappable chat input (not a real TextField)
          GestureDetector(
            onTap: () {
              if (convState.isAtLimit) return;
              AppHaptics.buttonPress();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppConstants.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? AppConstants.synapseIndigo.withValues(alpha:0.3)
                      : AppConstants.synapseIndigo.withValues(alpha:0.15),
                ),
                boxShadow: isDark
                    ? []
                    : [
                        BoxShadow(
                          color: AppConstants.synapseIndigo.withValues(alpha:0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology,
                    color: AppConstants.synapseIndigo.withValues(alpha:0.6),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'What do I know about...',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppConstants.slateGray,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.send,
                    color: AppConstants.synapseIndigo,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (convState.isAtLimit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Conversation limit reached (${convState.total}/${convState.maxAllowed}). Delete existing ones to create new.',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              ),
            ),

          const SizedBox(height: 12),

          // Suggestion chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SuggestionChip(
                label: 'What do I know about AI?',
                isDark: isDark,
                onTap: () {
                  AppHaptics.buttonPress();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChatScreen(initialQuery: 'What do I know about AI?'),
                    ),
                  );
                },
              ),
              _SuggestionChip(
                label: 'Summarize my recent saves',
                isDark: isDark,
                onTap: () {
                  AppHaptics.buttonPress();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ChatScreen(initialQuery: 'Summarize my recent saves'),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentConversations(bool isDark, ConversationsState convState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Text(
                'Recent Chats',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  AppHaptics.buttonPress();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => _FullChatListScreen()),
                  );
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
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: convState.conversations.length > 5 ? 5 : convState.conversations.length,
            itemBuilder: (context, index) {
              final conv = convState.conversations[index];
              return GestureDetector(
                onTap: () {
                  AppHaptics.buttonPress();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(conversationId: conv.id),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: const BoxConstraints(maxWidth: 200),
                  decoration: BoxDecoration(
                    color: isDark ? AppConstants.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: isDark ? null : AppTheme.shadowSoft,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.chat_bubble, size: 16, color: AppConstants.synapseIndigo),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          conv.title ?? 'Untitled',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWikiSection(bool isDark, WikiPagesState wikiState) {
    if (wikiState.isLoading && wikiState.pages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Icon(Icons.auto_stories, size: 18, color: AppConstants.synapseIndigo),
              const SizedBox(width: 8),
              Text(
                'Wiki Pages',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (wikiState.pages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${wikiState.total}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.synapseIndigo,
                    ),
                  ),
                ),
              const Spacer(),
              if (wikiState.pages.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    AppHaptics.buttonPress();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const _FullWikiListScreen()),
                    );
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
        if (wikiState.pages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Wiki pages are auto-created when an entity is mentioned 3+ times across your content.',
              style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
            ),
          )
        else
          ...wikiState.pages.take(5).map((page) => _WikiPageCard(page: page, isDark: isDark)),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEntitiesSection(bool isDark, EntitiesState entityState) {
    if (entityState.isLoading && entityState.entities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Icon(Icons.hub, size: 18, color: AppConstants.synapseIndigo),
              const SizedBox(width: 8),
              Text(
                'Entities',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              if (entityState.entities.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entityState.total}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppConstants.synapseIndigo,
                    ),
                  ),
                ),
              const Spacer(),
              if (entityState.entities.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    AppHaptics.buttonPress();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const _FullEntityListScreen()),
                    );
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
        if (entityState.entities.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Entities are auto-extracted from your content by the AI engine.',
              style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
            ),
          )
        else
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: entityState.entities.length > 15 ? 15 : entityState.entities.length,
              itemBuilder: (context, index) {
                final entity = entityState.entities[index];
                return GestureDetector(
                  onTap: () {
                    AppHaptics.buttonPress();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => EntityDetailScreen(entityId: entity.id)),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppConstants.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha:0.08) : AppConstants.borderColor,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(entity.typeEmoji, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          entity.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
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
    );
  }
}

// ===== Shared Components =====

class _SuggestionChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? AppConstants.synapseIndigo.withValues(alpha:0.1)
              : AppConstants.synapseIndigo.withValues(alpha:0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppConstants.synapseIndigo.withValues(alpha:0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppConstants.synapseIndigo,
          ),
        ),
      ),
    );
  }
}

class _HealthInsightChip extends StatelessWidget {
  final HealthCheck check;
  final bool isDark;
  final VoidCallback onDismiss;

  const _HealthInsightChip({
    required this.check,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final priorityColor = check.isHighPriority
        ? Colors.orange.shade700
        : AppConstants.synapseIndigo;

    return Container(
      width: 240,
      margin: const EdgeInsets.only(right: 10, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: priorityColor.withValues(alpha:0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Text(check.typeIcon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              check.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close, size: 16, color: AppConstants.slateGray),
          ),
        ],
      ),
    );
  }
}

class _WikiPageCard extends StatelessWidget {
  final WikiPage page;
  final bool isDark;

  const _WikiPageCard({required this.page, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WikiPageScreen(slug: page.slug)),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDark ? null : AppTheme.shadowSoft,
        ),
        child: Row(
          children: [
            if (page.entityType != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  page.entityType!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppConstants.synapseIndigo,
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${page.sourceCount} sources • ${(page.confidenceScore * 100).toInt()}% confidence',
                    style: TextStyle(fontSize: 11, color: AppConstants.slateGray),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppConstants.slateGray),
          ],
        ),
      ),
    );
  }
}

// ===== Full Chat List Screen (accessed via "See all") =====

class _FullChatListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: const Text('All Conversations'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // New chat button + counter
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: state.isAtLimit
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const ChatScreen()),
                            );
                          },
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('New Conversation'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: state.isAtLimit
                          ? Colors.grey
                          : AppConstants.synapseIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppConstants.surfaceDark : AppConstants.dividerColor,
                    borderRadius: BorderRadius.circular(12),
                    border: state.isAtLimit
                        ? Border.all(color: Colors.orange.shade400, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    '${state.total}/${state.maxAllowed}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: state.isAtLimit
                          ? Colors.orange.shade700
                          : isDark
                              ? AppConstants.starlight
                              : AppConstants.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.conversations.isEmpty
                    ? Center(
                        child: Text(
                          'No conversations yet',
                          style: TextStyle(color: AppConstants.slateGray),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.conversations.length,
                        itemBuilder: (context, index) {
                          final conv = state.conversations[index];
                          return Dismissible(
                            key: ValueKey(conv.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              AppHaptics.destructive();
                              return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Conversation?'),
                                  content: const Text('This conversation will be permanently deleted.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (_) {
                              ref.read(conversationsProvider.notifier).deleteConversation(conv.id);
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(conversationId: conv.id),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? AppConstants.surfaceDark : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: isDark ? null : AppTheme.shadowSoft,
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.chat_bubble, size: 20, color: AppConstants.synapseIndigo),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        conv.title ?? 'Untitled',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, size: 18, color: AppConstants.slateGray),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ===== Full Wiki List Screen (accessed via "See all") =====

class _FullWikiListScreen extends ConsumerStatefulWidget {
  const _FullWikiListScreen();

  @override
  ConsumerState<_FullWikiListScreen> createState() => _FullWikiListScreenState();
}

class _FullWikiListScreenState extends ConsumerState<_FullWikiListScreen> {
  String _searchQuery = '';
  String? _selectedCategory;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _reload());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    ref.read(wikiPagesProvider.notifier).loadPages(
      status: 'published',
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wikiPagesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Group pages by entity_type (category)
    final allPages = state.pages;
    final categories = <String>{};
    for (final p in allPages) {
      categories.add(p.entityType ?? 'Uncategorized');
    }
    final sortedCategories = categories.toList()..sort();

    // Filter by selected category
    final filteredPages = _selectedCategory == null
        ? allPages
        : allPages.where((p) => (p.entityType ?? 'Uncategorized') == _selectedCategory).toList();

    // Group filtered pages by category
    final grouped = <String, List<WikiPage>>{};
    for (final p in filteredPages) {
      final cat = p.entityType ?? 'Uncategorized';
      grouped.putIfAbsent(cat, () => []).add(p);
    }
    final groupKeys = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: const Text('All Wiki Pages'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search wiki pages...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: isDark ? AppConstants.surfaceDark : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _reload();
              },
            ),
          ),

          // Category filter chips
          if (sortedCategories.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All', style: TextStyle(fontSize: 12)),
                      selected: _selectedCategory == null,
                      selectedColor: AppConstants.synapseIndigo.withValues(alpha:0.2),
                      onSelected: (_) {
                        setState(() { _selectedCategory = null; });
                      },
                    ),
                  ),
                  ...sortedCategories.map((cat) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(cat, style: const TextStyle(fontSize: 12)),
                        selected: _selectedCategory == cat,
                        selectedColor: AppConstants.synapseIndigo.withValues(alpha:0.2),
                        onSelected: (_) {
                          setState(() { _selectedCategory = cat; });
                        },
                      ),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filteredPages.length} wiki pages',
                style: TextStyle(fontSize: 12, color: AppConstants.slateGray),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Grouped wiki list
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPages.isEmpty
                    ? Center(
                        child: Text(
                          'No wiki pages found',
                          style: TextStyle(color: AppConstants.slateGray),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _buildGroupedItems(groupKeys, grouped).length,
                        itemBuilder: (context, index) {
                          final item = _buildGroupedItems(groupKeys, grouped)[index];
                          if (item is String) {
                            // Category header
                            return Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppConstants.synapseIndigo,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${grouped[item]!.length}',
                                    style: TextStyle(fontSize: 11, color: AppConstants.slateGray),
                                  ),
                                ],
                              ),
                            );
                          }
                          final page = item as WikiPage;
                          return Dismissible(
                            key: ValueKey(page.id),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              AppHaptics.destructive();
                              return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Wiki Page?'),
                                  content: Text('"${page.title}" will be permanently deleted.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: TextButton.styleFrom(foregroundColor: AppConstants.errorColor),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (_) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await ApiService().deleteWikiPage(page.id);
                                _reload();
                              } catch (e) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Failed to delete: $e')),
                                  );
                                }
                              }
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete, color: Colors.white),
                            ),
                            child: GestureDetector(
                              onTap: () {
                                AppHaptics.buttonPress();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => WikiPageScreen(slug: page.slug),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark ? AppConstants.surfaceDark : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: isDark ? null : AppTheme.shadowSoft,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            page.title,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${page.sourceCount} sources • ${(page.confidenceScore * 100).toInt()}% confidence',
                                            style: TextStyle(fontSize: 11, color: AppConstants.slateGray),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right, size: 18, color: AppConstants.slateGray),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  List<dynamic> _buildGroupedItems(List<String> keys, Map<String, List<WikiPage>> grouped) {
    final items = <dynamic>[];
    for (final key in keys) {
      items.add(key);
      items.addAll(grouped[key]!);
    }
    return items;
  }
}

// ===== Full Entity List Screen (accessed via "See all") =====

class _FullEntityListScreen extends ConsumerStatefulWidget {
  const _FullEntityListScreen();

  @override
  ConsumerState<_FullEntityListScreen> createState() => _FullEntityListScreenState();
}

class _FullEntityListScreenState extends ConsumerState<_FullEntityListScreen> {
  String? _selectedType;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const _entityTypes = [
    null, 'person', 'company', 'technology', 'concept', 'topic', 'place', 'event',
  ];

  static const _entityTypeLabels = <String?, String>{
    null: 'All',
    'person': 'People',
    'company': 'Companies',
    'technology': 'Tech',
    'concept': 'Concepts',
    'topic': 'Topics',
    'place': 'Places',
    'event': 'Events',
  };

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    ref.read(entitiesProvider.notifier).loadEntities(
      entityType: _selectedType,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(entitiesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: const Text('All Entities'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search entities...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: isDark ? AppConstants.surfaceDark : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _reload();
              },
            ),
          ),

          // Type filter chips
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _entityTypes.map((type) {
                final isSelected = _selectedType == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      _entityTypeLabels[type]!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: isSelected,
                    selectedColor: AppConstants.synapseIndigo.withValues(alpha:0.2),
                    onSelected: (_) {
                      setState(() { _selectedType = type; });
                      _reload();
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),

          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${state.total} entities',
                style: TextStyle(fontSize: 12, color: AppConstants.slateGray),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Entity list
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.entities.isEmpty
                    ? Center(
                        child: Text(
                          'No entities found',
                          style: TextStyle(color: AppConstants.slateGray),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.entities.length,
                        itemBuilder: (context, index) {
                          final entity = state.entities[index];
                          return GestureDetector(
                            onTap: () {
                              AppHaptics.buttonPress();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => EntityDetailScreen(entityId: entity.id),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isDark ? AppConstants.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isDark ? null : AppTheme.shadowSoft,
                              ),
                              child: Row(
                                children: [
                                  Text(entity.typeEmoji, style: const TextStyle(fontSize: 22)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entity.name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${entity.entityType} • ${entity.mentionCount} mentions',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppConstants.slateGray,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, size: 18, color: AppConstants.slateGray),
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
  }
}
