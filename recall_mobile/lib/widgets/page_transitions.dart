import 'package:flutter/material.dart';

/// Premium page transitions for ReKall
/// Provides fade, slide, and shared axis transitions with smooth animations

/// Fade transition - Simple, elegant opacity animation
class FadePageTransition extends PageRouteBuilder {
  final Widget page;

  FadePageTransition({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            );

            return FadeTransition(
              opacity: curvedAnimation,
              child: child,
            );
          },
        );
}

/// Slide transition - iOS-style horizontal slide
class SlidePageTransition extends PageRouteBuilder {
  final Widget page;
  final AxisDirection direction;

  SlidePageTransition({
    required this.page,
    this.direction = AxisDirection.left, // Default: slide from right
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 350),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Determine slide direction
            Offset beginOffset;
            switch (direction) {
              case AxisDirection.left:
                beginOffset = const Offset(1.0, 0.0); // From right
                break;
              case AxisDirection.right:
                beginOffset = const Offset(-1.0, 0.0); // From left
                break;
              case AxisDirection.up:
                beginOffset = const Offset(0.0, 1.0); // From bottom
                break;
              case AxisDirection.down:
                beginOffset = const Offset(0.0, -1.0); // From top
                break;
            }

            return SlideTransition(
              position: Tween<Offset>(
                begin: beginOffset,
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            );
          },
        );
}

/// Shared Axis transition - Material Design 3 style
/// Combines fade and scale for modern feel
class SharedAxisPageTransition extends PageRouteBuilder {
  final Widget page;
  final SharedAxisTransitionType transitionType;

  SharedAxisPageTransition({
    required this.page,
    this.transitionType = SharedAxisTransitionType.scaled,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            switch (transitionType) {
              case SharedAxisTransitionType.scaled:
                // Incoming page scales up and fades in
                return FadeTransition(
                  opacity: curvedAnimation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0).animate(curvedAnimation),
                    child: child,
                  ),
                );

              case SharedAxisTransitionType.horizontal:
                // Horizontal slide with fade
                return FadeTransition(
                  opacity: curvedAnimation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.3, 0.0),
                      end: Offset.zero,
                    ).animate(curvedAnimation),
                    child: child,
                  ),
                );

              case SharedAxisTransitionType.vertical:
                // Vertical slide with fade
                return FadeTransition(
                  opacity: curvedAnimation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.3),
                      end: Offset.zero,
                    ).animate(curvedAnimation),
                    child: child,
                  ),
                );
            }
          },
        );
}

enum SharedAxisTransitionType {
  scaled,
  horizontal,
  vertical,
}

/// Helper extension for easy navigation with transitions
extension NavigationTransitions on BuildContext {
  /// Navigate with fade transition
  Future<T?> fadeTo<T extends Object?>(Widget page) {
    return Navigator.of(this).push<T>(FadePageTransition(page: page) as Route<T>);
  }

  /// Navigate with slide transition
  Future<T?> slideTo<T extends Object?>(Widget page, {AxisDirection direction = AxisDirection.left}) {
    return Navigator.of(this).push<T>(SlidePageTransition(page: page, direction: direction) as Route<T>);
  }

  /// Navigate with shared axis transition
  Future<T?> sharedAxisTo<T extends Object?>(Widget page, {SharedAxisTransitionType type = SharedAxisTransitionType.scaled}) {
    return Navigator.of(this).push<T>(SharedAxisPageTransition(page: page, transitionType: type) as Route<T>);
  }
}
