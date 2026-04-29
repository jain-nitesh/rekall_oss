import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Centralized haptic feedback system for consistent tactile interactions
///
/// Usage:
/// ```dart
/// await AppHaptics.trigger(HapticType.light);  // Button press
/// await AppHaptics.trigger(HapticType.success); // Action completed
/// ```
enum HapticType {
  /// Ultra-light haptic for chips, filters, and subtle interactions
  ultraLight,

  /// Light haptic for buttons, cards, and standard interactions
  light,

  /// Medium haptic for swipe actions and important interactions
  medium,

  /// Heavy haptic for destructive actions
  heavy,

  /// Success pattern (double-tap: medium → light)
  success,

  /// Warning pattern (single medium with longer duration)
  warning,

  /// Error pattern (triple-tap for attention)
  error,
}

/// Centralized haptic feedback manager
class AppHaptics {
  /// Trigger a haptic feedback based on type
  ///
  /// Different types produce different tactile patterns:
  /// - ultraLight: Selection clicks
  /// - light: Standard button presses
  /// - medium: Swipe actions, threshold crossings
  /// - heavy: Destructive actions (delete, etc.)
  /// - success: Double-tap pattern (medium → light)
  /// - warning: Single medium with emphasis
  /// - error: Triple-tap pattern for errors
  static Future<void> trigger(HapticType type) async {
    switch (type) {
      case HapticType.ultraLight:
        await HapticFeedback.selectionClick();
        break;

      case HapticType.light:
        await HapticFeedback.lightImpact();
        break;

      case HapticType.medium:
        await HapticFeedback.mediumImpact();
        break;

      case HapticType.heavy:
        await HapticFeedback.heavyImpact();
        break;

      case HapticType.success:
        // Double-tap pattern: medium → light
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        await HapticFeedback.lightImpact();
        break;

      case HapticType.warning:
        // Single medium haptic
        await HapticFeedback.mediumImpact();
        break;

      case HapticType.error:
        // Triple-tap pattern: heavy → heavy → heavy
        for (int i = 0; i < 3; i++) {
          await HapticFeedback.heavyImpact();
          if (i < 2) {
            await Future.delayed(const Duration(milliseconds: 50));
          }
        }
        break;
    }
  }

  /// Trigger vibration (deprecated - use trigger instead)
  @Deprecated('Use AppHaptics.trigger() instead')
  static Future<void> vibrate(HapticType type) async {
    await trigger(type);
  }

  // Convenience methods for common haptic patterns

  /// Trigger haptic for button press
  static Future<void> buttonPress() async {
    await trigger(HapticType.light);
  }

  /// Trigger light haptic feedback
  static Future<void> light() async {
    await trigger(HapticType.light);
  }

  /// Trigger haptic for selection (chips, filters)
  static Future<void> selection() async {
    await trigger(HapticType.ultraLight);
  }

  /// Trigger haptic for swipe action
  static Future<void> swipe() async {
    await trigger(HapticType.medium);
  }

  /// Trigger haptic for destructive action (delete)
  static Future<void> destructive() async {
    await trigger(HapticType.heavy);
  }

  /// Trigger heavy haptic feedback
  static Future<void> heavy() async {
    await trigger(HapticType.heavy);
  }

  /// Trigger haptic for successful action completion
  static Future<void> success() async {
    await trigger(HapticType.success);
  }

  /// Trigger haptic for error
  static Future<void> error() async {
    await trigger(HapticType.error);
  }

  /// Trigger haptic for warning
  static Future<void> warning() async {
    await trigger(HapticType.warning);
  }
}

/// Extension on BuildContext for easy haptic access
extension HapticExtension on BuildContext {
  /// Trigger haptic feedback
  Future<void> haptic(HapticType type) async {
    await AppHaptics.trigger(type);
  }
}
