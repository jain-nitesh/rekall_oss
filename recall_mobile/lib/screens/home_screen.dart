import 'package:flutter/material.dart';
import '../utils/static_data.dart';
import '../models/content_item.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final content = StaticData.getAllContent();
    final user = StaticData.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ReKall'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Welcome back, ${user.name}!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${content.length} saved items',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          Text(
            'Recent Saves',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          ...content.map((item) => _buildContentCard(context, item)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_home_legacy',
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context, ContentItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(
            _getIconForSourceApp(item.sourceApp),
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              item.summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              item.getRelativeTime(),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        isThreeLine: true,
        onTap: () {},
      ),
    );
  }

  IconData _getIconForSourceApp(SourceApp app) {
    switch (app) {
      case SourceApp.youtube:
        return Icons.play_circle;
      case SourceApp.medium:
        return Icons.article;
      case SourceApp.github:
        return Icons.code;
      case SourceApp.twitter:
        return Icons.tag;
      case SourceApp.reddit:
        return Icons.forum;
      case SourceApp.linkedin:
        return Icons.business;
      default:
        return Icons.link;
    }
  }
}
