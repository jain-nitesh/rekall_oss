import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/constants.dart';

/// A rich visual guide showing how to share content to ReKall.
/// Shows step-by-step with illustrated phone mockups.
void showShareGuideDialog(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ShareGuideSheet(),
  );
}

class _ShareGuideSheet extends StatefulWidget {
  const _ShareGuideSheet();

  @override
  State<_ShareGuideSheet> createState() => _ShareGuideSheetState();
}

class _ShareGuideSheetState extends State<_ShareGuideSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _steps = [
    _ShareStep(
      icon: Icons.article_outlined,
      phoneIcon: Icons.language,
      title: 'Find something interesting',
      description: 'Open any app — Chrome, Twitter, Reddit, YouTube, Instagram, LinkedIn...',
      phoneTitle: 'My favorite article',
      phoneSubtitle: 'Any app or browser',
      accentColor: Color(0xFF6366F1),
    ),
    _ShareStep(
      icon: Icons.ios_share,
      phoneIcon: Icons.ios_share,
      title: 'Tap the Share button',
      description: 'Look for the share icon — it\'s usually at the bottom or top of the screen.',
      phoneTitle: 'Share',
      phoneSubtitle: 'Tap to open share sheet',
      accentColor: Color(0xFF0EA5E9),
    ),
    _ShareStep(
      icon: Icons.apps,
      phoneIcon: Icons.grid_view_rounded,
      title: 'Select ReKall',
      description: 'Scroll through the share sheet and tap ReKall. That\'s it!',
      phoneTitle: 'ReKall',
      phoneSubtitle: 'Tap to save instantly',
      accentColor: Color(0xFF10B981),
    ),
    _ShareStep(
      icon: Icons.auto_awesome,
      phoneIcon: Icons.auto_awesome,
      title: 'AI does the rest',
      description: 'ReKall automatically summarizes, categorizes, and makes it searchable.',
      phoneTitle: 'Saved!',
      phoneSubtitle: 'AI summary ready in seconds',
      accentColor: Color(0xFFF59E0B),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDarkMode ? AppConstants.surfaceDark : AppConstants.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXL),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: AppConstants.spacingM),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? AppConstants.slateGray.withValues(alpha: 0.3)
                    : AppConstants.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingL),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: AppConstants.primaryGradient,
                    ),
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  child: const Icon(
                    Icons.share,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How to Save Content',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: isDarkMode
                              ? AppConstants.starlight
                              : AppConstants.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        '4 simple steps',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDarkMode
                              ? AppConstants.slateGray
                              : AppConstants.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDarkMode
                        ? AppConstants.slateGray
                        : AppConstants.textSecondary,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Page indicator dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _steps.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: _currentPage == i ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? _steps[_currentPage].accentColor
                      : (isDarkMode
                          ? Colors.white.withValues(alpha: 0.15)
                          : AppConstants.borderColor),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          const SizedBox(height: AppConstants.spacingM),

          // Swipeable step pages
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _steps.length,
              onPageChanged: (page) => setState(() => _currentPage = page),
              itemBuilder: (context, index) => _buildStepPage(
                _steps[index],
                index,
                isDarkMode,
              ),
            ),
          ),

          // Bottom nav
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppConstants.spacingL,
              AppConstants.spacingM,
              AppConstants.spacingL,
              AppConstants.spacingM + bottomPadding,
            ),
            child: Row(
              children: [
                if (_currentPage > 0)
                  TextButton(
                    onPressed: () => _pageController.previousPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: Text(
                      'Back',
                      style: GoogleFonts.inter(
                        color: isDarkMode
                            ? AppConstants.slateGray
                            : AppConstants.textSecondary,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 60),
                const Spacer(),
                if (_currentPage < _steps.length - 1)
                  ElevatedButton(
                    onPressed: () => _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _steps[_currentPage].accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusL),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Next',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward, size: 18),
                      ],
                    ),
                  )
                else
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _steps[_currentPage].accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.radiusL),
                      ),
                    ),
                    child: Text(
                      'Got it!',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // Platform-specific pin tip
          Container(
            margin: EdgeInsets.only(
              left: AppConstants.spacingL,
              right: AppConstants.spacingL,
              bottom: AppConstants.spacingS,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingM,
              vertical: AppConstants.spacingS,
            ),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.04)
                  : AppConstants.primaryColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppConstants.radiusM),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 16,
                  color: isDarkMode
                      ? AppConstants.primaryBlueCyan
                      : AppConstants.primaryColor,
                ),
                const SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: Text(
                    Platform.isIOS
                        ? 'Tip: Tap "More" in the share sheet to pin ReKall for quick access.'
                        : 'Tip: The more you share to ReKall, the higher it appears.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: isDarkMode
                          ? AppConstants.slateGray
                          : AppConstants.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPage(
    _ShareStep step,
    int index,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingL),
      child: Column(
        children: [
          // Phone mockup illustration
          Expanded(
            child: Center(
              child: _buildPhoneMockup(step, isDarkMode),
            ),
          ),

          const SizedBox(height: AppConstants.spacingL),

          // Step number badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: step.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Step ${index + 1}',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: step.accentColor,
              ),
            ),
          ),

          const SizedBox(height: AppConstants.spacingS),

          // Title
          Text(
            step.title,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDarkMode
                  ? AppConstants.starlight
                  : AppConstants.textPrimary,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppConstants.spacingS),

          // Description
          Text(
            step.description,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: isDarkMode
                  ? AppConstants.slateGray
                  : AppConstants.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: AppConstants.spacingL),
        ],
      ),
    );
  }

  /// Builds a simplified phone-shaped illustration for each step
  Widget _buildPhoneMockup(_ShareStep step, bool isDarkMode) {
    return Container(
      width: 200,
      height: 320,
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF1A1A2E)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFFE2E8F0),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: step.accentColor.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: Column(
          children: [
            // Status bar
            Container(
              height: 32,
              color: isDarkMode
                  ? const Color(0xFF0D0D1A)
                  : const Color(0xFFEEF2FF),
              child: Center(
                child: Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Phone content area
            Expanded(
              child: _buildPhoneContent(step, isDarkMode),
            ),

            // Bottom bar with share icon highlight for step 2
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: isDarkMode
                  ? const Color(0xFF0D0D1A)
                  : const Color(0xFFEEF2FF),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Icon(Icons.arrow_back_ios, size: 16,
                      color: isDarkMode ? Colors.white30 : Colors.black26),
                  _buildBottomBarIcon(
                    Icons.ios_share,
                    step.phoneIcon == Icons.ios_share,
                    step.accentColor,
                    isDarkMode,
                  ),
                  Icon(Icons.more_vert, size: 16,
                      color: isDarkMode ? Colors.white30 : Colors.black26),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBarIcon(
    IconData icon,
    bool highlighted,
    Color accentColor,
    bool isDarkMode,
  ) {
    if (!highlighted) {
      return Icon(icon, size: 16,
          color: isDarkMode ? Colors.white30 : Colors.black26);
    }
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: accentColor),
    );
  }

  Widget _buildPhoneContent(_ShareStep step, bool isDarkMode) {
    // Different content for each step
    if (step.phoneIcon == Icons.language) {
      // Step 1: Browser-like content
      return _buildBrowserContent(isDarkMode);
    } else if (step.phoneIcon == Icons.ios_share) {
      // Step 2: Share button highlighted
      return _buildShareButtonContent(step, isDarkMode);
    } else if (step.phoneIcon == Icons.grid_view_rounded) {
      // Step 3: Share sheet with ReKall highlighted
      return _buildShareSheetContent(step, isDarkMode);
    } else {
      // Step 4: Saved confirmation
      return _buildSavedContent(step, isDarkMode);
    }
  }

  Widget _buildBrowserContent(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE8ECF4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 12,
                    color: isDarkMode ? Colors.white38 : Colors.black38),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('example.com/article',
                    style: TextStyle(fontSize: 10,
                        color: isDarkMode ? Colors.white54 : Colors.black54)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Article content placeholder
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8ECF4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Icon(Icons.image_outlined, size: 30,
                  color: isDarkMode ? Colors.white24 : Colors.black26),
            ),
          ),
          const SizedBox(height: 10),
          _mockTextLine(0.9, isDarkMode, height: 10),
          const SizedBox(height: 6),
          _mockTextLine(0.7, isDarkMode, height: 8),
          const SizedBox(height: 4),
          _mockTextLine(0.8, isDarkMode, height: 8),
          const SizedBox(height: 4),
          _mockTextLine(0.5, isDarkMode, height: 8),
        ],
      ),
    );
  }

  Widget _buildShareButtonContent(_ShareStep step, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mockTextLine(0.9, isDarkMode, height: 10),
          const SizedBox(height: 6),
          _mockTextLine(0.6, isDarkMode, height: 8),
          const SizedBox(height: 12),
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8ECF4),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 10),
          _mockTextLine(0.8, isDarkMode, height: 8),
          const SizedBox(height: 4),
          _mockTextLine(0.7, isDarkMode, height: 8),
          const Spacer(),
          // Highlighted share button
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: step.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: step.accentColor, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ios_share, size: 18, color: step.accentColor),
                  const SizedBox(width: 6),
                  Text('Share',
                    style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: step.accentColor)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildShareSheetContent(_ShareStep step, bool isDarkMode) {
    return Column(
      children: [
        // Dimmed content behind
        Padding(
          padding: const EdgeInsets.all(12),
          child: Opacity(
            opacity: 0.3,
            child: Column(
              children: [
                _mockTextLine(0.9, isDarkMode, height: 8),
                const SizedBox(height: 4),
                _mockTextLine(0.6, isDarkMode, height: 8),
              ],
            ),
          ),
        ),
        const Spacer(),
        // Share sheet
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E1E36) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Share sheet drag handle
              Container(
                width: 30, height: 3,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              // App icons row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildShareAppIcon('Copy', Icons.copy, Colors.grey, false, isDarkMode),
                  _buildShareAppIcon('ReKall', Icons.auto_awesome, step.accentColor, true, isDarkMode),
                  _buildShareAppIcon('Notes', Icons.note, Colors.orange, false, isDarkMode),
                  _buildShareAppIcon('More', Icons.more_horiz, Colors.grey, false, isDarkMode),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShareAppIcon(
    String label,
    IconData icon,
    Color color,
    bool highlighted,
    bool isDarkMode,
  ) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: highlighted
                ? color.withValues(alpha: 0.2)
                : (isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(10),
            border: highlighted
                ? Border.all(color: color, width: 2)
                : null,
          ),
          child: Icon(icon, size: 18, color: highlighted ? color : Colors.grey),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
            color: highlighted
                ? color
                : (isDarkMode ? Colors.white54 : Colors.black54),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedContent(_ShareStep step, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: step.accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle, size: 32, color: step.accentColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Saved to ReKall!',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isDarkMode ? AppConstants.starlight : AppConstants.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Mock content card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _mockTextLine(0.8, isDarkMode, height: 9),
                const SizedBox(height: 6),
                _mockTextLine(0.95, isDarkMode, height: 6, light: true),
                const SizedBox(height: 3),
                _mockTextLine(0.7, isDarkMode, height: 6, light: true),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: step.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('AI Summary',
                        style: GoogleFonts.inter(fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: step.accentColor)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8ECF4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Technology',
                        style: GoogleFonts.inter(fontSize: 8,
                            color: isDarkMode ? Colors.white54 : Colors.black45)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mockTextLine(double widthFraction, bool isDarkMode,
      {double height = 8, bool light = false}) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFraction,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: light
              ? (isDarkMode ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8ECF4))
              : (isDarkMode ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFD5DBE5)),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _ShareStep {
  final IconData icon;
  final IconData phoneIcon;
  final String title;
  final String description;
  final String phoneTitle;
  final String phoneSubtitle;
  final Color accentColor;

  const _ShareStep({
    required this.icon,
    required this.phoneIcon,
    required this.title,
    required this.description,
    required this.phoneTitle,
    required this.phoneSubtitle,
    required this.accentColor,
  });
}
