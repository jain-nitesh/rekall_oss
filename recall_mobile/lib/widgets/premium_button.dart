import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/haptics.dart';

/// Premium button with press animation
/// Features:
/// - AnimatedScale for press effect (scale to 0.96 on press)
/// - Haptic feedback on press
/// - Smooth easing curves
/// - Gradient background support
/// - Loading state with shimmer animation
/// - Customizable colors and styles
class PremiumButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double? elevation;
  final bool outlined;
  final bool fullWidth;
  final bool isLoading;
  final Widget? loadingWidget;

  const PremiumButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.gradient,
    this.padding,
    this.borderRadius,
    this.elevation,
    this.outlined = false,
    this.fullWidth = false,
    this.isLoading = false,
    this.loadingWidget,
  });

  /// Factory for primary button (filled with brand color or gradient)
  factory PremiumButton.primary({
    required VoidCallback? onPressed,
    required Widget child,
    Gradient? gradient,
    bool isLoading = false,
    EdgeInsetsGeometry? padding,
    bool fullWidth = false,
  }) {
    return PremiumButton(
      onPressed: isLoading ? null : onPressed,
      gradient: gradient ?? const LinearGradient(colors: AppConstants.primaryGradient),
      foregroundColor: Colors.white,
      padding: padding,
      fullWidth: fullWidth,
      isLoading: isLoading,
      child: child,
    );
  }

  /// Factory for secondary button (outlined)
  factory PremiumButton.secondary({
    required VoidCallback? onPressed,
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool fullWidth = false,
  }) {
    return PremiumButton(
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      foregroundColor: AppConstants.primaryColor,
      padding: padding,
      outlined: true,
      fullWidth: fullWidth,
      child: child,
    );
  }

  /// Factory for text button (no background)
  factory PremiumButton.text({
    required VoidCallback? onPressed,
    required Widget child,
    Color? foregroundColor,
    EdgeInsetsGeometry? padding,
  }) {
    return PremiumButton(
      onPressed: onPressed,
      backgroundColor: Colors.transparent,
      foregroundColor: foregroundColor ?? AppConstants.primaryColor,
      padding: padding,
      elevation: 0,
      child: child,
    );
  }

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      setState(() => _isPressed = true);
      AppHaptics.buttonPress();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.backgroundColor ?? AppConstants.primaryColor;
    final foregroundColor = widget.foregroundColor ?? Colors.white;
    final padding = widget.padding ??
        const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingL,
          vertical: AppConstants.spacingM,
        );
    final borderRadius =
        widget.borderRadius ?? BorderRadius.circular(AppConstants.radiusL);
    final elevation = widget.elevation ?? 2.0;

    // Loading widget
    final loadingChild = widget.loadingWidget ??
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
          ),
        );

    return AnimatedScale(
      scale: _isPressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.isLoading ? null : widget.onPressed,
        child: AnimatedOpacity(
          opacity: widget.isLoading ? 0.7 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: widget.fullWidth ? double.infinity : null,
            padding: padding,
            decoration: BoxDecoration(
              color: widget.outlined ? Colors.transparent : (widget.gradient == null ? backgroundColor : null),
              gradient: widget.outlined ? null : widget.gradient,
              borderRadius: borderRadius,
              border: widget.outlined
                  ? Border.all(color: foregroundColor, width: 1.5)
                  : null,
              boxShadow: elevation > 0 && !widget.outlined
                  ? [
                      BoxShadow(
                        color: backgroundColor.withValues(alpha: 0.3),
                        blurRadius: elevation * 4,
                        offset: Offset(0, elevation),
                      ),
                    ]
                  : null,
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: foregroundColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: foregroundColor,
                  size: 20,
                ),
                child: Center(
                  child: widget.isLoading ? loadingChild : widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon button with press animation
class PremiumIconButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color? color;
  final double size;
  final String? tooltip;

  const PremiumIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.color,
    this.size = 24,
    this.tooltip,
  });

  @override
  State<PremiumIconButton> createState() => _PremiumIconButtonState();
}

class _PremiumIconButtonState extends State<PremiumIconButton> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null) {
      setState(() => _isPressed = true);
      AppHaptics.buttonPress();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScale(
      scale: _isPressed ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        onTap: widget.onPressed,
        child: Icon(
          widget.icon,
          color: widget.color ?? AppConstants.textPrimary,
          size: widget.size,
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }

    return button;
  }
}
