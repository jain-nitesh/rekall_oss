import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../models/conversation.dart';
import '../content/content_detail_screen.dart';
import 'wiki_page_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? conversationId;
  final String? initialQuery;
  const ChatScreen({super.key, this.conversationId, this.initialQuery});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final List<String> _suggestions = [];
  String? _conversationId;
  bool _isSending = false;
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversationId;
    if (_conversationId != null) {
      _loadHistory();
    } else if (widget.initialQuery != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.text = widget.initialQuery!;
        _send();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (_conversationId == null) return;
    setState(() => _isLoadingHistory = true);
    try {
      final data = await ApiService().getConversation(_conversationId!);
      final conv = Conversation.fromJson(data);
      setState(() {
        _messages.clear();
        _messages.addAll(conv.messages);
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    _controller.clear();

    // Add user message immediately
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _isSending = true;
      _suggestions.clear();
    });
    _scrollToBottom();

    try {
      final data = await ApiService().sendChatMessage(
        question: text,
        conversationId: _conversationId,
      );
      final response = ChatResponse.fromJson(data);

      setState(() {
        _conversationId = response.conversationId;
        _messages.add(ChatMessage(
          role: 'assistant',
          content: response.answer,
          referencedItems: response.citedSources,
          referencedWikiPages: response.citedWikiPages,
          citationMap: response.citationMap,
        ));
        _suggestions.clear();
        _suggestions.addAll(response.followUpSuggestions);
        _isSending = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          role: 'assistant',
          content: 'Sorry, something went wrong. Please try again.',
        ));
        _isSending = false;
      });
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: const Text('Memory Chat'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Messages
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: _messages.length + (_isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            return _buildTypingIndicator(isDark);
                          }
                          return _MessageBubble(
                            message: _messages[index],
                            isDark: isDark,
                          );
                        },
                      ),
          ),

          // Follow-up suggestions
          if (_suggestions.isNotEmpty) _buildSuggestions(isDark),

          // Input
          _buildInput(isDark),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.psychology, size: 64, color: AppConstants.synapseIndigo.withValues(alpha:0.5)),
            const SizedBox(height: 16),
            Text(
              'Ask your memory',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask questions about anything you\'ve saved.\nAnswers are cited from your content, entities,\nand compiled wiki pages.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppConstants.slateGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _SuggestionChip(
                  label: 'What do I know about AI?',
                  onTap: () {
                    _controller.text = 'What do I know about AI?';
                    _send();
                  },
                ),
                _SuggestionChip(
                  label: 'Summarize my recent saves',
                  onTap: () {
                    _controller.text = 'Summarize my recent saves';
                    _send();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? AppConstants.surfaceDark : AppConstants.dividerColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppConstants.synapseIndigo,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Searching your memory...',
              style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _suggestions.map((s) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _SuggestionChip(
            label: s,
            onTap: () {
              _controller.text = s;
              _send();
            },
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildInput(bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        8,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppConstants.surfaceDark : AppConstants.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppConstants.starlight.withValues(alpha:0.05)
                : AppConstants.dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: TextStyle(
                fontSize: 15,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Ask your memory...',
                hintStyle: TextStyle(color: AppConstants.slateGray),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: isDark
                    ? AppConstants.backgroundDark
                    : AppConstants.dividerColor,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: AppConstants.synapseIndigo,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, size: 20, color: Colors.white),
              onPressed: _isSending ? null : _send,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isDark;

  const _MessageBubble({required this.message, required this.isDark});

  /// Strip raw citation markers like [CONTENT_ITEM 1], [WIKI_PAGE 2], [ENTITY 3]
  static final _citationMarkerPattern = RegExp(r'\s*\[(CONTENT_ITEM|WIKI_PAGE|ENTITY)\s+\d+\]');

  String _cleanContent(String content) {
    return content.replaceAll(_citationMarkerPattern, '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? AppConstants.synapseIndigo
              : isDark
                  ? AppConstants.surfaceDark
                  : AppConstants.dividerColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Render content with tappable inline citations for assistant messages
            if (!isUser && message.citationMap.isNotEmpty)
              _buildRichContent(context)
            else
              Text(
                !isUser ? _cleanContent(message.content) : message.content,
                style: TextStyle(
                  fontSize: 14,
                  color: isUser
                      ? Colors.white
                      : isDark
                          ? AppConstants.starlight
                          : AppConstants.textPrimary,
                  height: 1.4,
                ),
              ),
            // Show cited sources for assistant messages
            if (!isUser && message.referencedItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: message.referencedItems.map((ref) {
                  return GestureDetector(
                    onTap: () => _navigateToSource(context, ref.id, ref.type),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ref.title,
                        style: TextStyle(
                          fontSize: 10,
                          color: AppConstants.synapseIndigo,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (!isUser && message.referencedWikiPages.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: message.referencedWikiPages.map((ref) {
                  return GestureDetector(
                    onTap: () {
                      if (ref.slug.isNotEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WikiPageScreen(slug: ref.slug),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha:0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_stories, size: 10, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text(
                            ref.title,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds rich text with tappable [CONTENT_ITEM N] / [WIKI_PAGE N] citations.
  Widget _buildRichContent(BuildContext context) {
    final textColor = isDark ? AppConstants.starlight : AppConstants.textPrimary;
    final content = message.content;

    // Match patterns like [CONTENT_ITEM 1], [WIKI_PAGE 2], [ENTITY 3]
    final citationPattern = RegExp(r'\[(CONTENT_ITEM|WIKI_PAGE|ENTITY)\s+(\d+)\]');
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in citationPattern.allMatches(content)) {
      // Add text before this citation
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
        ));
      }

      final citationKey = match.group(0)!; // e.g. [CONTENT_ITEM 1]
      final citation = message.citationMap[citationKey];

      if (citation != null) {
        // Tappable citation chip
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: GestureDetector(
            onTap: () => _navigateToSource(context, citation.id, citation.type, slug: citation.slug),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: citation.type == 'wiki_page'
                    ? Colors.green.withValues(alpha:0.15)
                    : AppConstants.synapseIndigo.withValues(alpha:0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                citation.title.length > 25
                    ? '${citation.title.substring(0, 25)}...'
                    : citation.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: citation.type == 'wiki_page'
                      ? Colors.green.shade700
                      : AppConstants.synapseIndigo,
                ),
              ),
            ),
          ),
        ));
      } else {
        // Unknown citation, skip the marker
      }

      lastEnd = match.end;
    }

    // Add remaining text after last citation
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: TextStyle(fontSize: 14, color: textColor, height: 1.4),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }

  void _navigateToSource(BuildContext context, String id, String type, {String slug = ''}) {
    if (type == 'wiki_page' && slug.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WikiPageScreen(slug: slug)),
      );
    } else if (type == 'content_item') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ContentDetailScreen(contentId: id)),
      );
    }
    // entity taps could navigate to entity detail in the future
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppConstants.synapseIndigo.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppConstants.synapseIndigo.withValues(alpha:0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppConstants.synapseIndigo,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
