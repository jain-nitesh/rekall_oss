import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';

/// Premium bottom sheet with glassmorphism effect
///
/// Features:
/// - Glassmorphic background with BackdropFilter blur
/// - Gradient overlay
/// - Drag handle with spring animation
/// - Swipe-to-dismiss with haptic feedback
/// - Keyboard avoidance
///
/// Usage:
/// ```dart
/// showPremiumBottomSheet(
///   context: context,
///   child: MyContent(),
/// );
/// ```
Future<T?> showPremiumBottomSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? backgroundColor,
  double? initialChildSize,
  double? minChildSize,
  double? maxChildSize,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => PremiumBottomSheetContent(
      backgroundColor: backgroundColor,
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      child: child,
    ),
  );
}

/// Premium bottom sheet content widget
class PremiumBottomSheetContent extends StatefulWidget {
  final Widget child;
  final Color? backgroundColor;
  final double? initialChildSize;
  final double? minChildSize;
  final double? maxChildSize;

  const PremiumBottomSheetContent({
    super.key,
    required this.child,
    this.backgroundColor,
    this.initialChildSize,
    this.minChildSize,
    this.maxChildSize,
  });

  @override
  State<PremiumBottomSheetContent> createState() =>
      _PremiumBottomSheetContentState();
}

class _PremiumBottomSheetContentState extends State<PremiumBottomSheetContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _handleController;
  late Animation<double> _handleAnimation;

  @override
  void initState() {
    super.initState();
    _handleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _handleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _handleController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _handleController.dispose();
    super.dispose();
  }

  void _onDragStart() {
    _handleController.forward();
    AppHaptics.selection();
  }

  void _onDragEnd() {
    _handleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultBackgroundColor = isDark
        ? const Color(0xFF1E293B)
        : AppConstants.white;
    final bgColor = widget.backgroundColor ?? defaultBackgroundColor;

    return GestureDetector(
      onVerticalDragStart: (_) => _onDragStart(),
      onVerticalDragEnd: (_) => _onDragEnd(),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppConstants.blurElevated,
            sigmaY: AppConstants.blurElevated,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  bgColor.withValues(alpha: 0.95),
                  bgColor.withValues(alpha: 0.98),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(
                  color: AppConstants.borderColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: ScaleTransition(
                      scale: _handleAnimation,
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppConstants.textSecondary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  // Content
                  Flexible(
                    child: widget.child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draggable scrollable bottom sheet variant
class PremiumDraggableBottomSheet extends StatelessWidget {
  final Widget child;
  final Color? backgroundColor;
  final double initialChildSize;
  final double minChildSize;
  final double maxChildSize;

  const PremiumDraggableBottomSheet({
    super.key,
    required this.child,
    this.backgroundColor,
    this.initialChildSize = 0.5,
    this.minChildSize = 0.25,
    this.maxChildSize = 0.95,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultBackgroundColor = isDark
        ? const Color(0xFF1E293B)
        : AppConstants.white;
    final bgColor = backgroundColor ?? defaultBackgroundColor;

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      minChildSize: minChildSize,
      maxChildSize: maxChildSize,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: AppConstants.blurElevated,
              sigmaY: AppConstants.blurElevated,
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor.withValues(alpha: 0.95),
                    bgColor.withValues(alpha: 0.98),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border(
                  top: BorderSide(
                    color: AppConstants.borderColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppConstants.textSecondary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Scrollable content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: const ClampingScrollPhysics(),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Extension on BuildContext for easy bottom sheet access
extension BottomSheetExtension on BuildContext {
  /// Show premium bottom sheet
  Future<T?> showPremiumSheet<T>({
    required Widget child,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showPremiumBottomSheet<T>(
      context: this,
      child: child,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
    );
  }
}
