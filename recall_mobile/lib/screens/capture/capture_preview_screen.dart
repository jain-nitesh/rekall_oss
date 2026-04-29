import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../services/api_service.dart';
import '../../providers/content_provider.dart';
import '../../providers/time_based_content_provider.dart';
import '../../utils/constants.dart';
import '../../utils/haptics.dart';

/// Preview captured media before saving to ReCall.
class CapturePreviewScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String contentType; // 'image' or 'video'

  const CapturePreviewScreen({
    super.key,
    required this.filePath,
    required this.contentType,
  });

  @override
  ConsumerState<CapturePreviewScreen> createState() => _CapturePreviewScreenState();
}

class _CapturePreviewScreenState extends ConsumerState<CapturePreviewScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  VideoPlayerController? _videoController;
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.contentType == 'video') {
      _videoController = VideoPlayerController.file(File(widget.filePath))
        ..initialize().then((_) {
          if (mounted) setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
        }).catchError((e) {
          if (mounted) {
            setState(() => _errorMessage = 'Could not load video: $e');
          }
        });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });

    AppHaptics.buttonPress();

    try {
      final item = await ApiService().uploadMedia(
        filePath: widget.filePath,
        contentType: widget.contentType,
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );

      // Add to content feed
      ref.read(contentProvider.notifier).addContentLocally(item);

      // Refresh time-based feed sections so home screen shows the new item
      ref.read(justInContentProvider.notifier).refresh();
      ref.read(todayContentProvider.notifier).refresh();

      if (mounted) {
        AppHaptics.success();
        // Pop both preview and camera screens
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.contentType == 'image'
                  ? 'Photo saved! AI is analyzing it...'
                  : 'Video saved! AI is processing it...',
            ),
            backgroundColor: AppConstants.primaryBlueCyan,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isUploading = false;
        _errorMessage = 'Upload failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.contentType == 'image' ? 'Photo Preview' : 'Video Preview',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isUploading ? null : () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Media preview
          Expanded(
            flex: 3,
            child: _buildMediaPreview(),
          ),

          // Input fields
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? AppConstants.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title field
                    TextField(
                      controller: _titleController,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add a title (optional)',
                        hintStyle: TextStyle(
                          color: isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha:0.1)
                                : AppConstants.borderColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha:0.1)
                                : AppConstants.borderColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Notes field
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add notes (optional)',
                        hintStyle: TextStyle(
                          color: isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textSecondary,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha:0.1)
                                : AppConstants.borderColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white.withValues(alpha:0.1)
                                : AppConstants.borderColor,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Error message
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),

                    // Save button
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isUploading ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryBlueCyan,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isUploading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Save to ReCall',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (widget.contentType == 'image') {
      return InteractiveViewer(
        child: Image.file(
          File(widget.filePath),
          fit: BoxFit.contain,
        ),
      );
    } else {
      // Video preview
      if (_videoController != null && _videoController!.value.isInitialized) {
        return GestureDetector(
          onTap: () {
            if (_videoController!.value.isPlaying) {
              _videoController!.pause();
            } else {
              _videoController!.play();
            }
            setState(() {});
          },
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
                    color: Colors.black.withValues(alpha:0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
            ],
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
  }
}
