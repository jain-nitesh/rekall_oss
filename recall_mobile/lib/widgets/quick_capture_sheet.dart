import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/content_provider.dart';
import '../providers/time_based_content_provider.dart';
import '../services/api_service.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';
import '../screens/capture/capture_screen.dart';

/// Quick capture bottom sheet for adding content directly from the feed.
/// Supports: paste URL, quick note, camera, gallery.
class QuickCaptureSheet extends ConsumerStatefulWidget {
  const QuickCaptureSheet({super.key});

  @override
  ConsumerState<QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<QuickCaptureSheet> {
  final _urlController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSavingUrl = false;
  bool _isSavingNote = false;
  bool _isUploadingMedia = false;
  String? _clipboardUrl;

  @override
  void initState() {
    super.initState();
    _checkClipboard();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null && data!.text!.isNotEmpty) {
        final text = data.text!.trim();
        if (_isUrl(text)) {
          setState(() {
            _clipboardUrl = text;
            _urlController.text = text;
          });
        }
      }
    } catch (_) {
      // Clipboard access may fail on some platforms
    }
  }

  bool _isUrl(String text) {
    return text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('www.');
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _isSavingUrl) return;

    // Ensure it's a proper URL
    final finalUrl = url.startsWith('http') ? url : 'https://$url';

    setState(() => _isSavingUrl = true);
    AppHaptics.buttonPress();

    try {
      final item = await ApiService().ingestContent(url: finalUrl);

      // Add to content feed
      ref.read(contentProvider.notifier).addContentLocally(item);
      ref.read(justInContentProvider.notifier).refresh();

      AppHaptics.success();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Link saved! AI is processing...'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppHaptics.error();
      if (mounted) {
        setState(() => _isSavingUrl = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _saveNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty || _isSavingNote) return;

    setState(() => _isSavingNote = true);
    AppHaptics.buttonPress();

    try {
      final item = await ApiService().ingestContent(
        url: '',
        title: note.length > 80 ? '${note.substring(0, 80)}...' : note,
        sharedText: note,
      );

      ref.read(contentProvider.notifier).addContentLocally(item);
      ref.read(justInContentProvider.notifier).refresh();

      AppHaptics.success();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note saved!'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppHaptics.error();
      if (mounted) {
        setState(() => _isSavingNote = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _openCamera() async {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CaptureScreen()),
    );
  }

  Future<void> _pickFromGallery({bool video = false}) async {
    if (_isUploadingMedia) return;

    try {
      final picker = ImagePicker();
      final XFile? file = video
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery);

      if (file == null) return;

      setState(() => _isUploadingMedia = true);
      AppHaptics.buttonPress();

      final contentType = video ? 'video' : 'image';
      final item = await ApiService().uploadMedia(
        filePath: file.path,
        contentType: contentType,
      );

      ref.read(contentProvider.notifier).addContentLocally(item);
      ref.read(justInContentProvider.notifier).refresh();

      AppHaptics.success();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${video ? 'Video' : 'Photo'} saved! AI is processing...'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppHaptics.error();
      if (mounted) {
        setState(() => _isUploadingMedia = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppConstants.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_circle,
                      color: AppConstants.primaryBlueCyan,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Add to ReKall',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // URL Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_clipboardUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Icon(Icons.content_paste, size: 14, color: AppConstants.primaryBlueCyan),
                            const SizedBox(width: 6),
                            Text(
                              'Found URL in clipboard',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppConstants.primaryBlueCyan,
                              ),
                            ),
                          ],
                        ),
                      ),
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Paste or type a URL...',
                        hintStyle: TextStyle(color: AppConstants.slateGray),
                        prefixIcon: Icon(Icons.link, color: AppConstants.slateGray, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppConstants.primaryBlueCyan, width: 1.5),
                        ),
                        filled: true,
                        fillColor: isDark ? AppConstants.backgroundDark : Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _urlController.text.trim().isNotEmpty && !_isSavingUrl
                            ? _saveUrl
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryBlueCyan,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.grey.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isSavingUrl
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save Link',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
                      ),
                    ),
                    Expanded(child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200)),
                  ],
                ),
              ),

              // Quick Note Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      minLines: 2,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Write a quick note...',
                        hintStyle: TextStyle(color: AppConstants.slateGray),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, top: 14, right: 8),
                          child: Icon(Icons.edit_note, color: AppConstants.slateGray, size: 20),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppConstants.primaryBlueCyan, width: 1.5),
                        ),
                        filled: true,
                        fillColor: isDark ? AppConstants.backgroundDark : Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _noteController.text.trim().isNotEmpty && !_isSavingNote
                            ? _saveNote
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppConstants.primaryBlueCyan,
                          side: BorderSide(
                            color: _noteController.text.trim().isNotEmpty
                                ? AppConstants.primaryBlueCyan
                                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSavingNote
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppConstants.primaryBlueCyan,
                                ),
                              )
                            : const Text(
                                'Save Note',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(fontSize: 13, color: AppConstants.slateGray),
                      ),
                    ),
                    Expanded(child: Divider(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200)),
                  ],
                ),
              ),

              // Media Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _MediaButton(
                        icon: Icons.camera_alt,
                        label: 'Camera',
                        isDark: isDark,
                        onTap: _openCamera,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MediaButton(
                        icon: Icons.photo_library,
                        label: 'Gallery',
                        isDark: isDark,
                        isLoading: _isUploadingMedia,
                        onTap: () => _pickFromGallery(),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24 + MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool isLoading;
  final VoidCallback onTap;

  const _MediaButton({
    required this.icon,
    required this.label,
    required this.isDark,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppConstants.backgroundDark : Colors.grey.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : AppConstants.borderColor,
            ),
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppConstants.primaryBlueCyan,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 22, color: AppConstants.primaryBlueCyan),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppConstants.starlight : AppConstants.textPrimary,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
