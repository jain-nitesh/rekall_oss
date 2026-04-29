import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../models/entity.dart';

class EntityDetailScreen extends StatefulWidget {
  final String entityId;
  const EntityDetailScreen({super.key, required this.entityId});

  @override
  State<EntityDetailScreen> createState() => _EntityDetailScreenState();
}

class _EntityDetailScreenState extends State<EntityDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService().getEntityDetail(widget.entityId);
      setState(() {
        _detail = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppConstants.backgroundDark : AppConstants.softWhite,
      appBar: AppBar(
        title: Text(_detail?['name'] ?? 'Entity'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _detail == null
                  ? const Center(child: Text('Entity not found'))
                  : _buildContent(isDark),
    );
  }

  Widget _buildContent(bool isDark) {
    final d = _detail!;
    final name = d['name'] as String? ?? 'Unknown';
    final entityType = d['entity_type'] as String? ?? 'concept';
    final description = d['description'] as String?;
    final mentionCount = d['mention_count'] as int? ?? 0;
    final confidence = (d['confidence'] as num?)?.toDouble();
    final contentItems = d['content_items'] as List<dynamic>? ?? [];
    final relatedEntities = d['related_entities'] as List<dynamic>? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entity header
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  Entity(id: '', name: name, entityType: entityType).typeEmoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppConstants.synapseIndigo.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            entityType,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.synapseIndigo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '$mentionCount mentions',
                          style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
                        ),
                        if (confidence != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            '${(confidence * 100).toInt()}%',
                            style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Description
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppConstants.starlight.withValues(alpha:0.85) : AppConstants.textSecondary,
                height: 1.5,
              ),
            ),
          ],

          // Content items
          if (contentItems.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Content (${contentItems.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            ...contentItems.take(20).map((item) {
              final title = item['title'] as String? ?? 'Untitled';
              final category = item['category'] as String? ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppConstants.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.article_outlined, size: 18, color: AppConstants.slateGray),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (category.isNotEmpty)
                      Text(
                        category,
                        style: TextStyle(fontSize: 11, color: AppConstants.slateGray),
                      ),
                  ],
                ),
              );
            }),
          ],

          // Related entities
          if (relatedEntities.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Related Entities',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: relatedEntities.take(15).map((rel) {
                final relName = rel['name'] as String? ?? '?';
                final relType = rel['relationship_type'] as String? ?? '';
                return GestureDetector(
                  onTap: () {
                    final relId = rel['id'] as String?;
                    if (relId != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => EntityDetailScreen(entityId: relId),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppConstants.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppConstants.synapseIndigo.withValues(alpha:0.2),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          relName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                          ),
                        ),
                        if (relType.isNotEmpty)
                          Text(
                            relType.replaceAll('_', ' '),
                            style: TextStyle(fontSize: 10, color: AppConstants.slateGray),
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
    );
  }
}
