import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';

/// Premium AppBar with glassmorphism effect
///
/// Features:
/// - Glassmorphic background with BackdropFilter blur
/// - Gradient overlay (top to bottom fade)
/// - Scroll-aware blur intensity
/// - Consistent styling across all screens
///
/// Usage:
/// ```dart
/// PremiumAppBar(
///   title: 'Screen Title',
///   actions: [
///     PremiumIconButton(...),
///   ],
/// )
/// ```
class PremiumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final bool transparent;
  final double blurIntensity;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool centerTitle;
  final double elevation;
  final PreferredSizeWidget? bottom;

  const PremiumAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.transparent = false,
    this.blurIntensity = 16.0,
    this.backgroundColor,
    this.foregroundColor,
    this.centerTitle = false,
    this.elevation = 0,
    this.bottom,
  });

  /// Glassmorphic AppBar (default)
  factory PremiumAppBar.glassmorphic({
    String? title,
    Widget? titleWidget,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = false,
    double blurIntensity = 16.0,
    PreferredSizeWidget? bottom,
  }) {
    return PremiumAppBar(
      title: title,
      titleWidget: titleWidget,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      blurIntensity: blurIntensity,
      transparent: false,
      bottom: bottom,
    );
  }

  /// Transparent AppBar (for detail screens)
  factory PremiumAppBar.transparent({
    String? title,
    Widget? titleWidget,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = false,
    PreferredSizeWidget? bottom,
  }) {
    return PremiumAppBar(
      title: title,
      titleWidget: titleWidget,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      transparent: true,
      bottom: bottom,
    );
  }

  /// Scroll-aware AppBar (blur increases with scroll)
  /// Use with `NotificationListener<ScrollNotification>` to track scroll offset
  factory PremiumAppBar.scrollAware({
    required double scrollOffset,
    String? title,
    Widget? titleWidget,
    List<Widget>? actions,
    Widget? leading,
    bool centerTitle = false,
    double scrollThreshold = 50.0,
    PreferredSizeWidget? bottom,
  }) {
    final shouldBlur = scrollOffset > scrollThreshold;
    return PremiumAppBar(
      title: title,
      titleWidget: titleWidget,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      blurIntensity: shouldBlur ? 16.0 : 0.0,
      transparent: !shouldBlur,
      bottom: bottom,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final defaultBackgroundColor = isDark
        ? AppConstants.deepSpace
        : AppConstants.white;
    final defaultForegroundColor = isDark
        ? AppConstants.starlight
        : AppConstants.textPrimary;

    // Background colors for gradient
    final bgColor = backgroundColor ?? defaultBackgroundColor;
    final fgColor = foregroundColor ?? defaultForegroundColor;

    // Build title widget
    final titleWidget_ = titleWidget ??
        (title != null
            ? Text(
                title!,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              )
            : null);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: transparent ? 0 : blurIntensity,
          sigmaY: transparent ? 0 : blurIntensity,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: transparent
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bgColor.withValues(alpha: 0.95),
                      bgColor.withValues(alpha: 0.85),
                    ],
                  ),
            border: transparent
                ? null
                : Border(
                    bottom: BorderSide(
                      color: AppConstants.borderColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
          ),
          // Build AppBar conditionally based on whether leading is provided
          child: leading != null
              ? AppBar(
                  title: titleWidget_,
                  leading: leading,
                  actions: actions,
                  backgroundColor: Colors.transparent,
                  foregroundColor: fgColor,
                  elevation: elevation,
                  centerTitle: centerTitle,
                  systemOverlayStyle: isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                  iconTheme: IconThemeData(
                    color: fgColor,
                    size: AppConstants.iconMedium,
                    weight: 300,
                    opticalSize: 24,
                    fill: 0.0,
                  ),
                  bottom: bottom,
                )
              : AppBar(
                  title: titleWidget_,
                  // Don't pass leading at all - let Flutter add back button automatically
                  automaticallyImplyLeading: true,
                  actions: actions,
                  backgroundColor: Colors.transparent,
                  foregroundColor: fgColor,
                  elevation: elevation,
                  centerTitle: centerTitle,
                  systemOverlayStyle: isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                  iconTheme: IconThemeData(
                    color: fgColor,
                    size: AppConstants.iconMedium,
                    weight: 300,
                    opticalSize: 24,
                    fill: 0.0,
                  ),
                  bottom: bottom,
                ),
        ),
      ),
    );
  }
}

