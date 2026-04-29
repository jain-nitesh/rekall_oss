import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Empty state widget for displaying when no content is available
/// Enhanced with fade + slide entrance animation and gradient text support
class EmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool useGradientTitle;
  final Gradient? titleGradient;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.useGradientTitle = false,
    this.titleGradient,
  });

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    // More pronounced slide animation
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingXL),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  size: AppConstants.iconMassive,
                  color: AppConstants.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: AppConstants.spacingL),
                _buildTitle(),
                const SizedBox(height: AppConstants.spacingM),
                Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppConstants.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.action != null) ...[
                  const SizedBox(height: AppConstants.spacingXL),
                  widget.action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final textWidget = Text(
      widget.title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: widget.useGradientTitle ? Colors.white : AppConstants.textPrimary,
      ),
      textAlign: TextAlign.center,
    );

    if (widget.useGradientTitle) {
      return ShaderMask(
        shaderCallback: (bounds) {
          final gradient = widget.titleGradient ??
              const LinearGradient(
                colors: AppConstants.primaryGradientEnhanced,
              );
          return gradient.createShader(bounds);
        },
        child: textWidget,
      );
    }

    return textWidget;
  }
}
