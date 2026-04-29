import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/brain_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../models/wiki_page.dart';

class WikiPageScreen extends ConsumerStatefulWidget {
  final String slug;
  const WikiPageScreen({super.key, required this.slug});

  @override
  ConsumerState<WikiPageScreen> createState() => _WikiPageScreenState();
}

class _WikiPageScreenState extends ConsumerState<WikiPageScreen> {
  WikiPage? _page;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService().getWikiPage(widget.slug);
      setState(() {
        _page = WikiPage.fromJson(data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Wiki Page?'),
        content: Text('"${_page!.title}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ApiService().deleteWikiPage(_page!.id);
        if (mounted) {
          ref.read(wikiPagesProvider.notifier).loadPages(status: 'published');
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: Text(_page?.title ?? 'Wiki Page'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_page != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _page == null
                  ? const Center(child: Text('Page not found'))
                  : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    final page = _page!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Meta info bar
          _buildMetaBar(page, isDark),
          const SizedBox(height: 20),

          // Contradictions (if any)
          if (page.contradictions.where((c) => c.isOpen).isNotEmpty) ...[
            _buildContradictions(page, isDark),
            const SizedBox(height: 20),
          ],

          // Markdown content
          if (page.contentMarkdown != null && page.contentMarkdown!.isNotEmpty)
            _buildMarkdownContent(page.contentMarkdown!, isDark)
          else
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Icon(Icons.pending, size: 48, color: AppConstants.slateGray),
                  const SizedBox(height: 12),
                  Text(
                    page.isDraft
                        ? 'This page is being compiled...'
                        : 'No content available',
                    style: TextStyle(color: AppConstants.slateGray),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // Backlinks
          if (page.backlinks.isNotEmpty) _buildBacklinks(page, isDark),
        ],
      ),
    );
  }

  Widget _buildMetaBar(WikiPage page, bool isDark) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _MetaChip(
          icon: Icons.circle,
          iconColor: page.isPublished
              ? Colors.green
              : page.isStale
                  ? Colors.orange
                  : Colors.grey,
          label: page.status,
        ),
        _MetaChip(
          icon: Icons.source_outlined,
          label: '${page.sourceCount} sources',
        ),
        _MetaChip(
          icon: Icons.verified_outlined,
          label: '${(page.confidenceScore * 100).toInt()}%',
        ),
        if (page.entityType != null)
          _MetaChip(
            icon: Icons.category_outlined,
            label: page.entityType!,
          ),
      ],
    );
  }

  Widget _buildContradictions(WikiPage page, bool isDark) {
    final open = page.contradictions.where((c) => c.isOpen).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 18),
              const SizedBox(width: 8),
              Text(
                '${open.length} Contradiction${open.length > 1 ? 's' : ''} Detected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...open.take(3).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claim A: ${c.claimA}',
                      style: TextStyle(fontSize: 12, color: isDark ? AppConstants.starlight : AppConstants.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Claim B: ${c.claimB}',
                      style: TextStyle(fontSize: 12, color: isDark ? AppConstants.starlight : AppConstants.textPrimary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMarkdownContent(String markdown, bool isDark) {
    // Simple markdown rendering (paragraphs, headers, bold)
    final lines = markdown.split('\n');
    final widgets = <Widget>[];

    for (final line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      TextStyle style;
      if (line.startsWith('# ')) {
        style = TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
          height: 1.4,
        );
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(line.substring(2), style: style),
        ));
      } else if (line.startsWith('## ')) {
        style = TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
          height: 1.4,
        );
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(line.substring(3), style: style),
        ));
      } else if (line.startsWith('### ')) {
        style = TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
          height: 1.4,
        );
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(line.substring(4), style: style),
        ));
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('\u{2022} ', style: TextStyle(
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              )),
              Expanded(
                child: Text(
                  line.substring(2),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppConstants.starlight.withValues(alpha:0.9) : AppConstants.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ));
      } else {
        widgets.add(Text(
          line,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppConstants.starlight.withValues(alpha:0.9) : AppConstants.textPrimary,
            height: 1.6,
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildBacklinks(WikiPage page, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sources & References',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...page.backlinks.take(10).map((bl) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    bl.sourceType == 'wiki_page'
                        ? Icons.auto_stories
                        : Icons.article_outlined,
                    size: 16,
                    color: AppConstants.slateGray,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bl.contextSnippet ?? bl.sourceId,
                      style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;

  const _MetaChip({required this.icon, this.iconColor, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? AppConstants.slateGray),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppConstants.slateGray),
        ),
      ],
    );
  }
}
