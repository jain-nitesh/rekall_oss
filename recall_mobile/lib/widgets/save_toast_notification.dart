import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/content_item.dart';
import '../utils/constants.dart';

/// Minimalist toast notification for save operations
/// Shows progress bar and transforms to checkmark with haptic feedback
class SaveToastNotification {
  static OverlayEntry? _currentToast;

  /// Show save notification at top of screen
  static void show({
    required BuildContext context,
    required SourceApp sourceApp,
    required ContentCategory category,
    String? categoryName,
    String? categoryColorHex,
    String? sourceAppName,
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    // Remove existing toast if any
    hide();

    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _SaveToastWidget(
        sourceApp: sourceApp,
        category: category,
        categoryName: categoryName,
        categoryColorHex: categoryColorHex,
        sourceAppName: sourceAppName,
        onComplete: () {
          overlayEntry.remove();
          _currentToast = null;
        },
        duration: duration,
      ),
    );

    _currentToast = overlayEntry;
    overlay.insert(overlayEntry);
  }

  /// Hide current toast
  static void hide() {
    _currentToast?.remove();
    _currentToast = null;
  }
}

class _SaveToastWidget extends StatefulWidget {
  final SourceApp sourceApp;
  final ContentCategory category;
  final String? categoryName;
  final String? categoryColorHex;
  final String? sourceAppName;
  final VoidCallback onComplete;
  final Duration duration;

  const _SaveToastWidget({
    required this.sourceApp,
    required this.category,
    this.categoryName,
    this.categoryColorHex,
    this.sourceAppName,
    required this.onComplete,
    required this.duration,
  });

  @override
  State<_SaveToastWidget> createState() => _SaveToastWidgetState();
}

class _SaveToastWidgetState extends State<_SaveToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _progressAnimation;
  bool _isComplete = false;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    // Setup animations
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.2, curve: Curves.easeOut),
    );

    _progressAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.7, curve: Curves.easeInOut),
    );

    // Listen for completion
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _onSaveComplete();
      }
    });

    // Start animation
    _controller.forward();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSaveComplete() async {
    setState(() {
      _isComplete = true;
    });

    // Haptic feedback - medium impact
    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(duration: 50, amplitude: 128); // Medium impact
      }
    } catch (e) {
      // Silently fail if vibration not supported
    }

    // Auto-dismiss after showing checkmark
    _dismissTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(_slideAnimation),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingM),
            child: _buildToastCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildToastCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusL),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppConstants.deepSpace.withValues(alpha: 0.95),
                AppConstants.deepSpace.withValues(alpha: 0.90),
              ],
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusL),
            border: Border.all(
              color: AppConstants.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: AppConstants.deepSpace.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingL,
              vertical: AppConstants.spacingM,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Source app icon
                    _buildSourceIcon(),
                    const SizedBox(width: AppConstants.spacingM),

                    // Text and status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isComplete
                                ? 'Saved successfully!'
                                : 'Saving to ${_getCategoryName()}...',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppConstants.starlight,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: AppConstants.spacingXS),
                          Text(
                            _getSourceName(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppConstants.slateGray,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Status icon
                    if (_isComplete)
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                        builder: (context, value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppConstants.recallCyan,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppConstants.recallCyan
                                        .withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 20,
                                color: AppConstants.white,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),

                // Progress bar
                if (!_isComplete) ...[
                  const SizedBox(height: AppConstants.spacingM),
                  AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progressAnimation.value,
                          backgroundColor: AppConstants.white.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppConstants.recallCyan,
                          ),
                          minHeight: 3,
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceIcon() {
    final color = AppConstants.sourceAppColors[widget.sourceApp] ??
        AppConstants.textSecondary;

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingS),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Icon(
        AppConstants.sourceAppIcons[widget.sourceApp] ?? Icons.link,
        size: 20,
        color: color,
      ),
    );
  }

  String _getSourceName() {
    if (widget.sourceAppName != null && widget.sourceAppName!.isNotEmpty) {
      return widget.sourceAppName!;
    }
    return AppConstants.sourceAppNames[widget.sourceApp] ?? 'Unknown';
  }

  String _getCategoryName() {
    return AppConstants.categoryNameFor(
      widget.category,
      overrideName: widget.categoryName,
    );
  }
}
