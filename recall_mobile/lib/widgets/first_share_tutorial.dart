import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';

/// First share tutorial overlay
/// Shows on first visit to home screen when content list is empty
/// Provides visual guidance on how to share content to ReKall
class FirstShareTutorial extends StatefulWidget {
  final VoidCallback onDismiss;

  const FirstShareTutorial({
    super.key,
    required this.onDismiss,
  });

  /// Check if tutorial should be shown
  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('first_share_tutorial_shown') ?? false);
  }

  /// Mark tutorial as shown
  static Future<void> markAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_share_tutorial_shown', true);
  }

  @override
  State<FirstShareTutorial> createState() => _FirstShareTutorialState();
}

class _FirstShareTutorialState extends State<FirstShareTutorial>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
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

  Future<void> _handleDismiss() async {
    HapticFeedback.lightImpact();
    await FirstShareTutorial.markAsShown();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: AppConstants.deepCharcoal.withValues(alpha: 0.8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: SlideTransition(
              position: _slideAnimation,
              child: Container(
                margin: const EdgeInsets.all(AppConstants.spacingL),
                padding: const EdgeInsets.all(AppConstants.spacingL),
                decoration: BoxDecoration(
                  color: AppConstants.white,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                  boxShadow: [
                    BoxShadow(
                      color: AppConstants.deepCharcoal.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: AppConstants.primaryGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.share,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: AppConstants.spacingL),

                    // Title
                    const Text(
                      'Start Saving Content',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.textPrimary,
                        letterSpacing: -0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: AppConstants.spacingM),

                    // Instructions
                    const Text(
                      'To save content to ReKall:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppConstants.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: AppConstants.spacingM),

                    _buildStep('1', 'Open any app (Instagram, YouTube, Reddit, etc.)', Icons.apps),
                    const SizedBox(height: AppConstants.spacingS),
                    _buildStep('2', 'Tap the Share button', Icons.ios_share),
                    const SizedBox(height: AppConstants.spacingS),
                    _buildStep('3', 'Select "ReKall"', Icons.check_circle),

                    const SizedBox(height: AppConstants.spacingL),

                    const Text(
                      'Content will be saved automatically with AI-powered summaries!',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppConstants.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: AppConstants.spacingM),

                    Container(
                      padding: const EdgeInsets.all(AppConstants.spacingS),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: AppConstants.primaryColor,
                          ),
                          const SizedBox(width: AppConstants.spacingS),
                          Expanded(
                            child: Text(
                              Platform.isIOS
                                  ? 'Tip: Scroll right in the share sheet and tap "More" to pin ReKall for quick access.'
                                  : 'Tip: The more you share to ReKall, the higher it appears in your share menu.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppConstants.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppConstants.spacingL),

                    // Got it button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleDismiss,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.spacingM,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppConstants.radiusL),
                          ),
                          elevation: 2,
                        ),
                        child: const Text(
                          'Got it!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppConstants.primaryColor.withValues(alpha: 0.1),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppConstants.primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingM),
        Icon(
          icon,
          size: 20,
          color: AppConstants.textSecondary,
        ),
        const SizedBox(width: AppConstants.spacingS),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              color: AppConstants.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
