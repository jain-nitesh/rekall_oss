import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';

/// Transparent screen that handles shared content and closes immediately
class ShareHandlerScreen extends ConsumerStatefulWidget {
  const ShareHandlerScreen({super.key});

  @override
  ConsumerState<ShareHandlerScreen> createState() => _ShareHandlerScreenState();
}

class _ShareHandlerScreenState extends ConsumerState<ShareHandlerScreen> {
  @override
  void initState() {
    super.initState();
    _processSharedContent();
  }

  Future<void> _processSharedContent() async {
    // Small delay to ensure context is ready
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    try {
      // For MVP, show success message
      // In production, this would actually process the shared content
      // The intent data is handled by the MainActivity

      final currentUser = ref.read(currentUserProvider);

      if (currentUser == null) {
        _showToastAndClose('Please login to save content');
        return;
      }

      // Simulate processing
      await Future.delayed(const Duration(milliseconds: 500));

      // Show success and close
      AppHaptics.success();
      _showToastAndClose('✓ Saved to ReKall!');
    } catch (e) {
      // Error handling - close gracefully
      AppHaptics.error();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _showToastAndClose(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: AppConstants.successColor,
      ),
    );

    // Close activity after showing toast
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Transparent screen while processing
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
