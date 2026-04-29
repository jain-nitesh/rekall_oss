import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Premium loading indicator with fade-in animation
/// Features:
/// - Smooth fade-in animation (400ms)
/// - Thin progress indicator (2.5px stroke)
/// - Optional message parameter
/// - Consistent branding with app colors
class PremiumLoadingIndicator extends StatefulWidget {
  final String? message;
  final Color? color;
  final double size;
  final double strokeWidth;

  const PremiumLoadingIndicator({
    super.key,
    this.message,
    this.color,
    this.size = 40,
    this.strokeWidth = 2.5,
  });

  /// Factory for full-screen loading overlay
  factory PremiumLoadingIndicator.fullScreen({
    String? message,
  }) {
    return PremiumLoadingIndicator(
      message: message,
      size: 48,
      strokeWidth: 3,
    );
  }

  /// Factory for inline loading (small)
  factory PremiumLoadingIndicator.inline({
    Color? color,
  }) {
    return PremiumLoadingIndicator(
      color: color,
      size: 24,
      strokeWidth: 2,
    );
  }

  @override
  State<PremiumLoadingIndicator> createState() => _PremiumLoadingIndicatorState();
}

class _PremiumLoadingIndicatorState extends State<PremiumLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                strokeWidth: widget.strokeWidth,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.color ?? AppConstants.primaryColor,
                ),
              ),
            ),
            if (widget.message != null) ...[
              const SizedBox(height: AppConstants.spacingM),
              Text(
                widget.message!,
                style: TextStyle(
                  fontSize: 14,
                  color: AppConstants.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading overlay that covers the entire screen
class LoadingOverlay extends StatelessWidget {
  final String? message;
  final bool isLoading;

  const LoadingOverlay({
    super.key,
    this.message,
    this.isLoading = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();

    return Container(
      color: AppConstants.deepCharcoal.withValues(alpha: 0.5),
      child: PremiumLoadingIndicator.fullScreen(message: message),
    );
  }
}

/// Shimmer effect for skeleton loaders
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final bool isLoading;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration period;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.isLoading = true,
    this.baseColor,
    this.highlightColor,
    this.period = const Duration(milliseconds: 2000),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading) {
      return widget.child;
    }

    final baseColor = widget.baseColor ?? AppConstants.dividerColor;
    final highlightColor =
        widget.highlightColor ?? AppConstants.borderColor.withValues(alpha: 0.3);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                0.0,
                _controller.value,
                1.0,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// Pulsing loading indicator (alternative to circular progress)
class PulsingDot extends StatefulWidget {
  final Color? color;
  final double size;

  const PulsingDot({
    super.key,
    this.color,
    this.size = 12,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: ScaleTransition(
        scale: _animation,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color ?? AppConstants.primaryColor,
          ),
        ),
      ),
    );
  }
}

/// Three pulsing dots in a row
class PulsingDots extends StatelessWidget {
  final Color? color;
  final double size;

  const PulsingDots({
    super.key,
    this.color,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulsingDot(color: color, size: size),
        SizedBox(width: size * 0.8),
        PulsingDot(color: color, size: size),
        SizedBox(width: size * 0.8),
        PulsingDot(color: color, size: size),
      ],
    );
  }
}
