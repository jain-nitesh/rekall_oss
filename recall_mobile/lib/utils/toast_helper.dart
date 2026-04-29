import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Simple toast helper for showing messages without requiring BuildContext
class ToastHelper {
  static BuildContext? _context;

  /// Set the context to use for showing toasts
  static void setContext(BuildContext? context) {
    _context = context;
  }

  /// Show a simple toast message
  static void show(String message, {bool isSuccess = true}) {
    if (_context == null || !_context!.mounted) {
      debugPrint('ToastHelper: No context available, message: $message');
      return;
    }

    ScaffoldMessenger.of(_context!).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (isSuccess)
              const Icon(
                Icons.check_circle,
                color: AppConstants.white,
                size: 20,
              )
            else
              const Icon(
                Icons.error,
                color: AppConstants.white,
                size: 20,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        backgroundColor: isSuccess
            ? AppConstants.successColor
            : AppConstants.errorColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// Show success toast
  static void showSuccess(String message) {
    show(message, isSuccess: true);
  }

  /// Show error toast
  static void showError(String message) {
    show(message, isSuccess: false);
  }
}

