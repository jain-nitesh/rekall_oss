import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

class ImportBookmarksScreen extends ConsumerStatefulWidget {
  const ImportBookmarksScreen({super.key});

  @override
  ConsumerState<ImportBookmarksScreen> createState() => _ImportBookmarksScreenState();
}

class _ImportBookmarksScreenState extends ConsumerState<ImportBookmarksScreen> {
  bool _isImporting = false;
  String? _importStatus;
  int _totalItems = 0;
  int _processedItems = 0;
  String? _errorMessage;
  bool _importComplete = false;

  Future<void> _importFromSource(String source) async {
    AppHaptics.buttonPress();

    // Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: source == 'chrome' ? ['html', 'htm'] : ['csv', 'html', 'htm'],
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      setState(() {
        _errorMessage = 'Could not read the selected file';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _importStatus = 'Uploading ${file.name}...';
      _errorMessage = null;
      _importComplete = false;
    });

    try {
      final apiService = ApiService();
      Map<String, dynamic> importResult;

      switch (source) {
        case 'chrome':
          importResult = await apiService.importChromeBookmarks(file.bytes!, file.name);
          break;
        case 'pocket':
          importResult = await apiService.importPocketBookmarks(file.bytes!, file.name);
          break;
        case 'raindrop':
          importResult = await apiService.importRaindropBookmarks(file.bytes!, file.name);
          break;
        default:
          throw 'Unknown source: $source';
      }

      setState(() {
        _isImporting = false;
        _importComplete = true;
        _totalItems = importResult['total_items'] as int? ?? 0;
        _processedItems = importResult['created'] as int? ?? 0;
        _importStatus = 'Import complete!';
      });

      AppHaptics.success();
    } catch (e) {
      setState(() {
        _isImporting = false;
        _errorMessage = e.toString();
        _importStatus = null;
      });
      AppHaptics.error();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Bookmarks'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Connect your reading history',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacingS),
            Text(
              'Import your bookmarks and ReKall will discover connections between everything you\'ve ever saved.',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                height: 1.5,
              ),
            ),

            const SizedBox(height: AppConstants.spacingXL),

            // Import sources
            _buildSourceCard(
              icon: Icons.language,
              title: 'Chrome',
              description: 'Export from chrome://bookmarks → ⋮ → Export bookmarks',
              fileType: 'HTML file',
              source: 'chrome',
              isDarkMode: isDarkMode,
            ),

            const SizedBox(height: AppConstants.spacingM),

            _buildSourceCard(
              icon: Icons.bookmark,
              title: 'Pocket',
              description: 'Export from getpocket.com/export',
              fileType: 'HTML or CSV file',
              source: 'pocket',
              isDarkMode: isDarkMode,
            ),

            const SizedBox(height: AppConstants.spacingM),

            _buildSourceCard(
              icon: Icons.cloud,
              title: 'Raindrop.io',
              description: 'Export from Settings → Export → CSV',
              fileType: 'CSV file',
              source: 'raindrop',
              isDarkMode: isDarkMode,
            ),

            // Progress / Status
            if (_isImporting || _importStatus != null) ...[
              const SizedBox(height: AppConstants.spacingXL),
              _buildProgressSection(isDarkMode),
            ],

            // Error
            if (_errorMessage != null) ...[
              const SizedBox(height: AppConstants.spacingL),
              Container(
                padding: const EdgeInsets.all(AppConstants.spacingM),
                decoration: BoxDecoration(
                  color: AppConstants.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppConstants.radiusM),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppConstants.errorColor),
                    const SizedBox(width: AppConstants.spacingS),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppConstants.errorColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Success CTA
            if (_importComplete) ...[
              const SizedBox(height: AppConstants.spacingXL),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    AppHaptics.buttonPress();
                    // Navigate to connections tab
                    context.go('/');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConstants.primaryBlueCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusM),
                    ),
                  ),
                  child: const Text(
                    'View Your Connections',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard({
    required IconData icon,
    required String title,
    required String description,
    required String fileType,
    required String source,
    required bool isDarkMode,
  }) {
    return GestureDetector(
      onTap: _isImporting ? null : () => _importFromSource(source),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingL),
        decoration: BoxDecoration(
          color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.05)
                : AppConstants.borderColor.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppConstants.primaryBlueCyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppConstants.primaryBlueCyan, size: 24),
            ),
            const SizedBox(width: AppConstants.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                    ),
                  ),
                  Text(
                    fileType,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.upload_file,
              color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressSection(bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingL),
      decoration: BoxDecoration(
        color: AppConstants.primaryBlueCyan.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: AppConstants.primaryBlueCyan.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          if (_isImporting)
            const CircularProgressIndicator(),
          if (_importComplete)
            Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: AppConstants.spacingM),
          Text(
            _importStatus ?? '',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
          ),
          if (_importComplete) ...[
            const SizedBox(height: AppConstants.spacingS),
            Text(
              '$_processedItems bookmarks imported ($_totalItems total, ${_totalItems - _processedItems} duplicates skipped)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDarkMode ? AppConstants.slateGray : AppConstants.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
